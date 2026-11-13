const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const zls = b.dependency("zls", .{ .target = b.graph.host, .optimize = optimize });
    const source = b.addModule("formatter", .{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "zls", .module = zls.module("zls") }},
    });
    const executable = b.addExecutable(.{ .name = "zig-import-sorter", .root_module = source });
    b.installArtifact(executable);
    const tests = b.addTest(.{ .root_module = source });
    const test_step = b.step("test", "Test import sorting, formatting, and CLI behavior");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    addCliTests(b, executable, test_step);
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
    dependency: ?*std.Build.Dependency = null,
    passthrough_args: bool = true,
};

pub fn addSortImports(b: *std.Build, options: Options) *std.Build.Step.Run {
    const dependency = options.dependency orelse b.dependency("zig-import-sorter", .{});
    const executable = dependency.artifact("zig-import-sorter");
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
    if (options.passthrough_args) run.addPassthruArgs();
    return run;
}

fn addCliTests(b: *std.Build, executable: *std.Build.Step.Compile, test_step: *std.Build.Step) void {
    const cases = [_]struct { args: []const []const u8, exit_code: u8 }{
        .{ .args = &.{}, .exit_code = 0 },
        .{ .args = &.{"--unknown"}, .exit_code = 2 },
        .{ .args = &.{"--import-sorter-default-path"}, .exit_code = 2 },
        .{ .args = &.{ "--import-sorter-write", "--import-sorter-check" }, .exit_code = 2 },
    };
    for (cases) |case| {
        const run = b.addRunArtifact(executable);
        run.addArgs(case.args);
        run.expectExitCode(case.exit_code);
        if (case.exit_code != 0) run.expectStdErrMatch("error:");
        test_step.dependOn(&run.step);
    }
    const fixtures = b.addWriteFiles();
    const dirty = fixtures.add("dirty.zig", "const zebra = @import(\"zebra\");\nconst alpha = @import(\"alpha\");\n");
    const clean = fixtures.add("clean.zon", ".{ .value = 42 }\n");
    for ([_]struct { path: std.Build.LazyPath, exit_code: u8 }{
        .{ .path = dirty, .exit_code = 1 },
        .{ .path = clean, .exit_code = 0 },
    }) |case| {
        const run = createRun(b, executable, .{ .paths = &.{case.path}, .check = true, .passthrough_args = false });
        run.expectExitCode(case.exit_code);
        if (case.exit_code != 0) run.expectStdErrMatch("error:");
        test_step.dependOn(&run.step);
    }
}
