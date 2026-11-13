# zig-import-sorter

A Zig build dependency that sorts imports in `.zig` and `.zon` files with ZLS.

## Use from `build.zig`

```zig
const std = @import("std");
const import_sorter = @import("zig-import-sorter");

pub fn build(b: *std.Build) void {
    const paths = &.{ b.path("build.zig"), b.path("src") };
    const fmt = import_sorter.addSortImports(b, .{ .paths = paths });
    b.step("fmt", "Sort imports and format Zig files").dependOn(&fmt.step);

    const check = import_sorter.addSortImports(b, .{ .paths = paths, .check = true });
    b.step("fmt-check", "Check import ordering and formatting").dependOn(&check.step);
}
```

`addSortImports` returns a run step and formats sources as well as sorting imports.
Paths use `[]const std.Build.LazyPath`.

## API options

| Option | Default | Purpose |
| --- | --- | --- |
| `paths` | Required | Files and directories to process. |
| `check` | `false` | Report changes without writing files. |
| `dependency` | Resolved as `zig-import-sorter` | Use an existing or renamed dependency. |
| `passthrough_args` | `true` | Forward build arguments after `--`. |

### Custom dependency

```zig
const dependency = b.dependency("sorter", .{ .optimize = .ReleaseSafe });
const run = import_sorter.addSortImports(b, .{
    .dependency = dependency,
    .paths = paths,
});
b.step("sort-imports", "Sort configured paths").dependOn(&run.step);
```

The executable runs on the host, using the consuming project's working directory.

### Combining with `b.addFmt`

If you need an additional Zig formatter step, run it after the sorter:

```zig
const zig_fmt = b.addFmt(.{ .paths = paths });
zig_fmt.step.dependOn(&fmt.step);
b.step("format", "Sort imports, then format sources").dependOn(&zig_fmt.step);
```

## Commands

```sh
zig build fmt
zig build fmt-check
zig build fmt -- src/example.zig
zig build fmt -- --import-sorter-check src/example.zig
```

### Paths

Explicit paths replace the configured paths. Directories are searched recursively;
hidden entries, `zig-out`, `zig-pkg`, and symlinks found inside directories are skipped.
Other file types are ignored.

### Flags

The run accepts `--import-sorter-write` or `--import-sorter-check` (the default is
write mode). The build API forwards configured paths with
`--import-sorter-default-path PATH`. Flags can appear before or after paths; use
`--` before a path beginning with `-`. Write and check modes cannot be combined.

## Development

Requires Zig 0.17.1 or later.

```sh
zig build test
zig build check
zig build fmt-check
```
