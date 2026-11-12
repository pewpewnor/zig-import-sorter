# zig-import-sorter

A Zig build dependency that sorts imports in `.zig` and `.zon` files with ZLS.

## Use from `build.zig`

```zig
const std = @import("std");
const import_sorter = @import("zig-import-sorter");

pub fn build(b: *std.Build) void {
    const paths = &.{ b.path("build.zig"), b.path("src") };
    const fmt = import_sorter.addImportSorter(b, .{ .paths = paths });
    b.step("fmt", "Sort imports and format Zig files").dependOn(&fmt.step);

    const check = import_sorter.addImportSorter(b, .{ .paths = paths, .check = true });
    b.step("fmt-check", "Check import ordering and formatting").dependOn(&check.step);
}
```

`addImportSorter` returns a run step; choose the step names yourself. Paths use
`[]const std.Build.LazyPath`. To run Zig's built-in formatter too, add `b.addFmt`
and make the `fmt` and `fmt-check` steps depend on both runs.

## Commands

```sh
zig build fmt
zig build fmt-check
zig build fmt -- src/example.zig
zig build fmt -- --import-sorter-check src/example.zig
```

Explicit paths replace the configured paths. Directories are searched recursively;
hidden entries, `zig-out`, `zig-pkg`, and symlinks found inside directories are skipped.
`.zig` and `.zon` files have imports organized and are formatted.
Other file types are ignored.

The run accepts `--import-sorter-write` or `--import-sorter-check` (the default is
write mode). The build API forwards configured paths with
`--import-sorter-default-path PATH`. Flags can appear before or after paths; use
`--` before a path beginning with `-`. Write and check modes cannot be combined.
