const std = @import("std");

const zls = @import("zls");

pub fn formatSource(io: std.Io, allocator: std.mem.Allocator, environ: *const std.process.Environ.Map, source: []const u8, mode: std.zig.Ast.Mode) ![]u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch_allocator = arena.allocator();
    const organized = switch (mode) {
        .zig => try organizeImports(io, scratch_allocator, environ, source),
        .zon => source,
    };
    var tree = try std.zig.Ast.parse(scratch_allocator, try scratch_allocator.dupeSentinel(u8, organized, 0), .{ .mode = mode });
    defer tree.deinit(scratch_allocator);
    if (tree.errors.len != 0) {
        return error.InvalidSyntax;
    }
    return tree.renderAlloc(allocator);
}

fn organizeImports(io: std.Io, allocator: std.mem.Allocator, environ: *const std.process.Environ.Map, source: []const u8) ![]const u8 {
    var configuration: zls.configuration.Manager = try .init(io, allocator, environ);
    defer configuration.deinit();
    const server: *zls.Server = try .create(.{
        .io = io,
        .allocator = allocator,
        .transport = null,
        .config_manager = &configuration,
    });
    defer server.destroy();
    const uri: zls.Uri = try .parse(allocator, "untitled:///format.zig");
    try server.document_store.openLspSyncedDocument(uri, source);
    const handle = server.document_store.getHandle(uri) orelse return error.MissingDocument;
    if (handle.tree.errors.len != 0) {
        return error.InvalidSyntax;
    }
    var analyser = server.initAnalyser(allocator, handle);
    defer analyser.deinit();
    var builder: zls.code_actions.Builder = .{
        .arena = allocator,
        .analyser = &analyser,
        .handle = handle,
        .offset_encoding = .@"utf-8",
        .only_kinds = .init(.{ .@"source.organizeImports" = true }),
    };
    try builder.generateCodeAction(.empty);
    if (builder.actions.items.len == 0) {
        return source;
    }
    if (builder.actions.items.len != 1) {
        return error.UnexpectedCodeAction;
    }
    const action = builder.actions.items[0];
    if (action.kind == null or !action.kind.?.eql(.@"source.organizeImports")) {
        return error.UnexpectedCodeAction;
    }
    const edit = action.edit orelse return error.MissingEdits;
    const changes = edit.changes orelse return error.MissingEdits;
    const edits = changes.map.get(uri.raw) orelse return error.MissingEdits;
    return zls.diff.applyTextEdits(allocator, source, edits, .@"utf-8");
}
