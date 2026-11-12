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
    addRuns(b, executable, &.{ "build.zig", "build.zig.zon", "src" });
}

pub fn addSteps(b: *std.Build, paths: []const []const u8) void {
    const dependency = b.dependency("zig-imports-sorter", .{});
    const executable = b.addExecutable(.{
        .name = "zig-imports-sorter",
        .root_module = dependency.module("formatter"),
    });
    addRuns(b, executable, paths);
}

fn addRuns(b: *std.Build, executable: *std.Build.Step.Compile, paths: []const []const u8) void {
    const run = b.addRunArtifact(executable);
    run.has_side_effects = true;
    run.setCwd(b.path("."));
    for (paths) |path| {
        if (std.mem.endsWith(u8, path, ".zig") or std.mem.endsWith(u8, path, ".zon")) {
            run.addFileArg(b.path(path));
        } else {
            run.addDirectoryArg(b.path(path));
        }
    }
    run.addArg("--user-args");
    if (b.option(bool, "fmt-check", "Check formatting without writing changes") orelse false) {
        run.addArg("--check");
    }
    run.addPassthruArgs();
    b.step("fmt", "Organize imports and format Zig sources (-w/--write or -c/--check)").dependOn(&run.step);
}
