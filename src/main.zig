const std = @import("std");

const formatSource = @import("format_source.zig").formatSource;

pub fn main(init: std.process.Init) !u8 {
    const arguments = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(arguments);
    var should_write = true;
    var selected_mode: ?bool = null;
    var positional = false;
    var files: std.ArrayList([]const u8) = .empty;
    defer {
        for (files.items) |path| {
            init.gpa.free(path);
        }
        files.deinit(init.gpa);
    }
    var separator: usize = 1;
    while (separator < arguments.len and !std.mem.eql(u8, arguments[separator], "--user-args")) : (separator += 1) {}
    std.debug.assert(separator < arguments.len);
    var has_paths = false;
    for (arguments[separator + 1 ..]) |argument| {
        if (!positional and std.mem.eql(u8, argument, "--")) {
            positional = true;
            continue;
        }
        if (!positional and std.mem.startsWith(u8, argument, "-")) {
            const mode = if (std.mem.eql(u8, argument, "-w") or std.mem.eql(u8, argument, "--write")) true else if (std.mem.eql(u8, argument, "-c") or std.mem.eql(u8, argument, "--check")) false else {
                std.log.err("unknown option: {s}", .{argument});
                return 2;
            };
            if (selected_mode) |previous| {
                if (previous != mode) {
                    std.log.err("--write and --check cannot be combined", .{});
                    return 2;
                }
            }
            selected_mode = mode;
            should_write = mode;
            continue;
        }
        has_paths = true;
        try collectFiles(init.io, init.gpa, argument, &files);
    }
    if (!has_paths) {
        for (arguments[1..separator]) |path| {
            try collectFiles(init.io, init.gpa, path, &files);
        }
    }
    std.mem.sort([]const u8, files.items, {}, lessThan);
    const context: FileContext = .{ .io = init.io, .allocator = init.gpa, .environ = init.environ_map };
    var has_failure = false;
    for (files.items, 0..) |path, index| {
        if (index != 0 and std.mem.eql(u8, path, files.items[index - 1])) {
            continue;
        }
        const status = processFile(context, path, should_write) catch |err| {
            std.log.err("{s}: {s}", .{ path, @errorName(err) });
            has_failure = true;
            continue;
        };
        if (status != .clean) {
            try std.Io.File.stderr().writeStreamingAll(init.io, path);
            try std.Io.File.stderr().writeStreamingAll(init.io, "\n");
        }
        has_failure = has_failure or status == .needs_formatting;
    }
    if (has_failure) {
        std.log.err("formatting check failed; run zig build fmt", .{});
        return 1;
    }
    return 0;
}

const FileStatus = enum { clean, formatted, needs_formatting };

const FileContext = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
};

fn collectFiles(io: std.Io, allocator: std.mem.Allocator, path: []const u8, files: *std.ArrayList([]const u8)) !void {
    const stat = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
    switch (stat.kind) {
        .file => {
            if (isSource(path)) {
                const owned_path = try allocator.dupe(u8, path);
                errdefer allocator.free(owned_path);
                try files.append(allocator, owned_path);
            }
        },
        .directory => {
            var directory = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
            defer directory.close(io);
            var iterator = directory.iterate();
            while (try iterator.next(io)) |entry| {
                if (entry.name[0] == '.' or std.mem.eql(u8, entry.name, "zig-out") or std.mem.eql(u8, entry.name, "zig-pkg")) {
                    continue;
                }
                if (entry.kind != .file and entry.kind != .directory) {
                    continue;
                }
                const child = try std.Io.Dir.path.join(allocator, &.{ path, entry.name });
                defer allocator.free(child);
                try collectFiles(io, allocator, child, files);
            }
        },
        else => return error.UnsupportedPath,
    }
}

fn processFile(context: FileContext, path: []const u8, should_write: bool) !FileStatus {
    const original = try std.Io.Dir.cwd().readFileAlloc(context.io, path, context.allocator, .limited(16 * 1024 * 1024));
    defer context.allocator.free(original);
    const mode: std.zig.Ast.Mode = if (std.mem.endsWith(u8, path, ".zon")) .zon else .zig;
    const formatted = try formatSource(context.io, context.allocator, context.environ, original, mode);
    defer context.allocator.free(formatted);
    if (std.mem.eql(u8, original, formatted)) {
        return .clean;
    }
    if (should_write) {
        const stat = try std.Io.Dir.cwd().statFile(context.io, path, .{ .follow_symlinks = false });
        var file = try std.Io.Dir.cwd().createFileAtomic(context.io, path, .{ .replace = true, .permissions = stat.permissions });
        defer file.deinit(context.io);
        try file.file.writeStreamingAll(context.io, formatted);
        try file.replace(context.io);
        return .formatted;
    }
    return .needs_formatting;
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn isSource(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".zig") or std.mem.endsWith(u8, path, ".zon");
}

test {
    _ = @import("format_source_tests.zig");
}

test "check leaves dirty files unchanged and write produces a clean result" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const source = "const zebra = @import(\"zebra\");\nconst alpha = @import(\"alpha\");\n";
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.zig", .data = source });
    const path = try directory.dir.realPathFileAlloc(std.testing.io, "fixture.zig", std.testing.allocator);
    defer std.testing.allocator.free(path);
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    const context: FileContext = .{ .io = std.testing.io, .allocator = std.testing.allocator, .environ = &environ };
    try std.testing.expectEqual(FileStatus.needs_formatting, try processFile(context, path, false));
    const unchanged = try directory.dir.readFileAlloc(std.testing.io, "fixture.zig", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(unchanged);
    try std.testing.expectEqualStrings(source, unchanged);
    try std.testing.expectEqual(FileStatus.formatted, try processFile(context, path, true));
    try std.testing.expectEqual(FileStatus.clean, try processFile(context, path, false));
    const invalid = "const invalid = ;\n";
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fixture.zig", .data = invalid });
    try std.testing.expectError(error.InvalidSyntax, processFile(context, path, true));
    const retained = try directory.dir.readFileAlloc(std.testing.io, "fixture.zig", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(retained);
    try std.testing.expectEqualStrings(invalid, retained);
}
