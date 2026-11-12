const std = @import("std");

pub fn build(b: *std.Build) void {
    const zls = b.dependency("zls", .{ .target = b.graph.host, .optimize = .debug });
    const source = b.addModule("formatter", .{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
        .optimize = .debug,
        .imports = &.{.{ .name = "zls", .module = zls.module("zls") }},
    });
    const executable = b.addExecutable(.{ .name = "zig-imports-sorter", .root_module = source });
    const tests = b.addTest(.{ .root_module = source });
    b.step("test", "Test import sorting and Zig formatting").dependOn(&b.addRunArtifact(tests).step);
    const check = b.step("check", "Compile the formatter and its tests");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    const paths = &.{ "build.zig", "build.zig.zon", "src" };
    const fmt = createRun(b, executable, .{ .paths = paths });
    b.step("fmt", "Organize imports and format Zig sources").dependOn(&fmt.step);
    const fmt_check = createRun(b, executable, .{ .paths = paths, .check = true });
    b.step("fmt-check", "Check Zig source formatting").dependOn(&fmt_check.step);
}

pub const Options = struct {
    paths: []const []const u8,
    check: bool = false,
};

pub fn addRun(b: *std.Build, options: Options) *std.Build.Step.Run {
    const dependency = b.dependency("zig-imports-sorter", .{});
    const executable = b.addExecutable(.{
        .name = "zig-imports-sorter",
        .root_module = dependency.module("formatter"),
    });
    return createRun(b, executable, options);
}

fn createRun(b: *std.Build, executable: *std.Build.Step.Compile, options: Options) *std.Build.Step.Run {
    const run = b.addRunArtifact(executable);
    run.has_side_effects = true;
    run.setCwd(b.path("."));
    for (options.paths) |path| {
        if (std.mem.endsWith(u8, path, ".zig") or std.mem.endsWith(u8, path, ".zon")) {
            run.addFileArg(b.path(path));
        } else {
            run.addDirectoryArg(b.path(path));
        }
    }
    run.addArg("--user-args");
    if (options.check) {
        run.addArg("--check");
    }
    run.addPassthruArgs();
    return run;
}
