const std = @import("std");

pub fn build(b: *std.Build) void {
    const zls = b.dependency("zls", .{ .target = b.graph.host, .optimize = .debug });
    const source = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
        .optimize = .debug,
        .imports = &.{.{ .name = "zls", .module = zls.module("zls") }},
    });
    const executable = b.addExecutable(.{ .name = "zig-imports-sorter", .root_module = source });
    b.installArtifact(executable);
    const tests = b.addTest(.{ .root_module = source });
    b.step("test", "Test import sorting and Zig formatting").dependOn(&b.addRunArtifact(tests).step);
    const check = b.step("check", "Compile zig-imports-sorter and its tests");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    addRuns(b, executable, &.{ "build.zig", "build.zig.zon", "src" });
}

pub fn addSteps(b: *std.Build, paths: []const []const u8) void {
    const dependency = b.dependency("zig-imports-sorter", .{});
    addRuns(b, dependency.artifact("zig-imports-sorter"), paths);
}

fn addRuns(b: *std.Build, executable: *std.Build.Step.Compile, paths: []const []const u8) void {
    inline for (.{ "fmt", "fmt-check" }, .{ "--write", "--check" }, .{ "Organize imports and format Zig sources", "Check Zig formatting and import organization" }) |name, argument, description| {
        const run = b.addRunArtifact(executable);
        run.has_side_effects = true;
        run.addArg(argument);
        for (paths) |path| {
            if (std.mem.endsWith(u8, path, ".zig") or std.mem.endsWith(u8, path, ".zon")) {
                run.addFileArg(b.path(path));
            } else {
                run.addDirectoryArg(b.path(path));
            }
        }
        b.step(name, description).dependOn(&run.step);
    }
}
