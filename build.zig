const std = @import("std");

pub fn build(b: *std.Build) void {
    const zls = b.dependency("zls", .{ .target = b.graph.host, .optimize = .debug });
    const source = b.addModule("formatter", .{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
        .optimize = .debug,
        .imports = &.{.{ .name = "zls", .module = zls.module("zls") }},
    });
    const executable = b.addExecutable(.{ .name = "zig-import-sorter", .root_module = source });
    const tests = b.addTest(.{ .root_module = source });
    b.step("test", "Test import sorting and Zig formatting").dependOn(&b.addRunArtifact(tests).step);
    const check = b.step("check", "Compile the formatter and its tests");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    const paths = &.{ b.path("build.zig"), b.path("build.zig.zon"), b.path("src") };
    const fmt = createRun(b, executable, .{ .paths = paths });
    const zig_fmt = b.addFmt(.{ .paths = paths });
    zig_fmt.step.dependOn(&fmt.step);
    b.step("fmt", "Organize imports and format Zig sources").dependOn(&zig_fmt.step);
    const fmt_check = createRun(b, executable, .{ .paths = paths, .check = true });
    const zig_fmt_check = b.addFmt(.{ .paths = paths, .check = true });
    const fmt_check_step = b.step("fmt-check", "Check import ordering and Zig source formatting");
    fmt_check_step.dependOn(&fmt_check.step);
    fmt_check_step.dependOn(&zig_fmt_check.step);
}

pub const Options = struct {
    paths: []const std.Build.LazyPath,
    check: bool = false,
};

pub fn addImportSorter(b: *std.Build, options: Options) *std.Build.Step.Run {
    const dependency = b.dependency("zig-import-sorter", .{});
    const executable = b.addExecutable(.{
        .name = "zig-import-sorter",
        .root_module = dependency.module("formatter"),
    });
    return createRun(b, executable, options);
}

fn createRun(b: *std.Build, executable: *std.Build.Step.Compile, options: Options) *std.Build.Step.Run {
    const run = b.addRunArtifact(executable);
    run.has_side_effects = true;
    run.setCwd(b.path("."));
    for (options.paths) |path| {
        run.addArg("--import-sorter-default-path");
        run.addDirectoryArg2(path, .{});
    }
    if (options.check) {
        run.addArg("--import-sorter-check");
    }
    run.addPassthruArgs();
    return run;
}
