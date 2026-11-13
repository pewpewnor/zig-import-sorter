const std = @import("std");

const formatSource = @import("format_source.zig").formatSource;

pub fn main(init: std.process.Init) !u8 {
    const arguments = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(arguments);
    var options = parseArguments(init.gpa, arguments[1..]) catch |err| {
        std.log.err("invalid arguments: {s}", .{@errorName(err)});
        return 2;
    };
    defer options.deinit(init.gpa);
    var files: std.ArrayList([]const u8) = .empty;
    defer {
        for (files.items) |path| init.gpa.free(path);
        files.deinit(init.gpa);
    }
    for (options.paths()) |path| {
        try collectFiles(init.io, init.gpa, path, &files);
    }
    std.mem.sort([]const u8, files.items, {}, lessThan);
    const context: FileContext = .{ .io = init.io, .allocator = init.gpa, .environ = init.environ_map };
    var has_failure = false;
    for (files.items, 0..) |path, index| {
        if (index != 0 and std.mem.eql(u8, path, files.items[index - 1])) {
            continue;
        }
        const status = processFile(context, path, options.should_write) catch |err| {
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

const Arguments = struct {
    should_write: bool = true,
    explicit_paths: std.ArrayList([]const u8) = .empty,
    default_paths: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *Arguments, allocator: std.mem.Allocator) void {
        self.explicit_paths.deinit(allocator);
        self.default_paths.deinit(allocator);
    }

    fn paths(self: Arguments) []const []const u8 {
        return if (self.explicit_paths.items.len != 0) self.explicit_paths.items else self.default_paths.items;
    }
};

fn parseArguments(allocator: std.mem.Allocator, arguments: []const []const u8) !Arguments {
    var result: Arguments = .{};
    errdefer result.deinit(allocator);
    var selected_mode: ?bool = null;
    var positional = false;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        if (!positional and std.mem.eql(u8, argument, "--import-sorter-default-path")) {
            index += 1;
            if (index == arguments.len) return error.MissingDefaultPath;
            try result.default_paths.append(allocator, arguments[index]);
        } else if (!positional and std.mem.eql(u8, argument, "--")) {
            positional = true;
        } else if (!positional and std.mem.startsWith(u8, argument, "-")) {
            const mode = if (std.mem.eql(u8, argument, "--import-sorter-write")) true else if (std.mem.eql(u8, argument, "--import-sorter-check")) false else return error.UnknownOption;
            if (selected_mode) |previous| {
                if (previous != mode) return error.ConflictingModes;
            }
            selected_mode = mode;
            result.should_write = mode;
        } else {
            try result.explicit_paths.append(allocator, argument);
        }
    }
    return result;
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

test "arguments select defaults and explicit paths replace them" {
    const allocator = std.testing.allocator;
    var empty = try parseArguments(allocator, &.{});
    defer empty.deinit(allocator);
    try std.testing.expect(empty.should_write);
    try std.testing.expectEqual(@as(usize, 0), empty.paths().len);

    var defaults = try parseArguments(allocator, &.{ "--import-sorter-default-path", "src", "--import-sorter-default-path", "build.zig" });
    defer defaults.deinit(allocator);
    try std.testing.expectEqualSlices([]const u8, &.{ "src", "build.zig" }, defaults.paths());

    var explicit = try parseArguments(allocator, &.{ "--import-sorter-default-path", "missing", "one.zig", "--import-sorter-check", "two.zon" });
    defer explicit.deinit(allocator);
    try std.testing.expect(!explicit.should_write);
    try std.testing.expectEqualSlices([]const u8, &.{ "one.zig", "two.zon" }, explicit.paths());
}

test "arguments handle terminator repeated modes and invalid options" {
    const allocator = std.testing.allocator;
    var positional = try parseArguments(allocator, &.{ "--import-sorter-check", "--import-sorter-check", "--", "-file.zig", "--import-sorter-write" });
    defer positional.deinit(allocator);
    try std.testing.expect(!positional.should_write);
    try std.testing.expectEqualSlices([]const u8, &.{ "-file.zig", "--import-sorter-write" }, positional.paths());
    var write = try parseArguments(allocator, &.{ "--import-sorter-write", "--import-sorter-write" });
    defer write.deinit(allocator);
    try std.testing.expect(write.should_write);
    try std.testing.expectError(error.UnknownOption, parseArguments(allocator, &.{ "file.zig", "--unknown" }));
    try std.testing.expectError(error.MissingDefaultPath, parseArguments(allocator, &.{ "--import-sorter-default-path", "src", "--import-sorter-default-path" }));
    try std.testing.expectError(error.ConflictingModes, parseArguments(allocator, &.{ "--import-sorter-write", "--import-sorter-check" }));
    try std.testing.expectError(error.ConflictingModes, parseArguments(allocator, &.{ "--import-sorter-check", "--import-sorter-write" }));
}

test "file discovery recurses and excludes hidden build and unrelated entries" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    for ([_][]const u8{ "nested", ".hidden", "zig-out", "zig-pkg" }) |path| {
        try directory.dir.createDir(io, path, .default_dir);
    }
    for ([_][]const u8{ "root.zig", "nested/build.zig.zon", "readme.md", ".hidden.zig", ".hidden/skip.zig", "zig-out/skip.zig", "zig-pkg/skip.zig" }) |path| {
        try directory.dir.writeFile(io, .{ .sub_path = path, .data = "" });
    }
    const root = try directory.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    var files: std.ArrayList([]const u8) = .empty;
    defer {
        for (files.items) |path| allocator.free(path);
        files.deinit(allocator);
    }
    try collectFiles(io, allocator, root, &files);
    std.mem.sort([]const u8, files.items, {}, lessThan);
    try std.testing.expectEqual(@as(usize, 2), files.items.len);
    try std.testing.expect(std.mem.endsWith(u8, files.items[0], "nested/build.zig.zon"));
    try std.testing.expect(std.mem.endsWith(u8, files.items[1], "root.zig"));
    const ignored = try std.Io.Dir.path.join(allocator, &.{ root, "readme.md" });
    defer allocator.free(ignored);
    try collectFiles(io, allocator, ignored, &files);
    try std.testing.expectEqual(@as(usize, 2), files.items.len);
    const missing = try std.Io.Dir.path.join(allocator, &.{ root, "missing.zig" });
    defer allocator.free(missing);
    try std.testing.expectError(error.FileNotFound, collectFiles(io, allocator, missing, &files));
}

test "file discovery skips symlinks and rejects explicit symlink paths" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(io, .{ .sub_path = "source.zig", .data = "" });
    directory.dir.symLink(io, "source.zig", "link.zig", .{}) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    try directory.dir.symLink(io, ".", "loop", .{ .is_directory = true });
    const root = try directory.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    var files: std.ArrayList([]const u8) = .empty;
    defer {
        for (files.items) |path| allocator.free(path);
        files.deinit(allocator);
    }
    try collectFiles(io, allocator, root, &files);
    try std.testing.expectEqual(@as(usize, 1), files.items.len);
    try std.testing.expect(std.mem.endsWith(u8, files.items[0], "source.zig"));
    const link = try std.Io.Dir.path.join(allocator, &.{ root, "link.zig" });
    defer allocator.free(link);
    try std.testing.expectError(error.UnsupportedPath, collectFiles(io, allocator, link, &files));
}

fn parseWithAllocator(allocator: std.mem.Allocator) !void {
    var arguments = try parseArguments(allocator, &.{ "--import-sorter-default-path", "src", "file.zig", "--import-sorter-check" });
    defer arguments.deinit(allocator);
    try std.testing.expect(!arguments.should_write);
    try std.testing.expectEqual(@as(usize, 1), arguments.paths().len);
}

test "argument parsing releases allocations on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parseWithAllocator, .{});
}
