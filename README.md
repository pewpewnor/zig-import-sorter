# zig-import-sorter

Build dependency that uses ZLS to organize imports and formats Zig sources.
No standalone executable is installed.

Add the dependency as `zig-import-sorter`, then create formatter runs and
attach them to your own steps in `build.zig`:

```zig
const std = @import("std");
const import_sorter = @import("zig-import-sorter");

pub fn build(b: *std.Build) void {
    const paths = &.{ b.path("build.zig"), b.path("build.zig.zon"), b.path("src") };
    const fmt = import_sorter.addImportSorter(b, .{ .paths = paths });
    b.step("fmt", "Organize imports and format Zig sources").dependOn(&fmt.step);

    const fmt_check = import_sorter.addImportSorter(b, .{ .paths = paths, .check = true });
    b.step("fmt-check", "Check Zig source formatting").dependOn(&fmt_check.step);
}
```

`addImportSorter` returns a `*std.Build.Step.Run`; it does not register named steps or
build options. Callers choose step names and can attach the runs to other steps.
Its `paths` option accepts `[]const std.Build.LazyPath`, just like `b.addFmt`,
so both can share the same paths.

To also run Zig's built-in formatter, wire both formatters into the same steps:

```zig
const std = @import("std");
const import_sorter = @import("zig-import-sorter");

pub fn build(b: *std.Build) void {
    const paths = &.{ b.path("build.zig"), b.path("build.zig.zon"), b.path("src") };

    const imports_fmt = import_sorter.addImportSorter(b, .{ .paths = paths });
    const zig_fmt = b.addFmt(.{ .paths = paths });
    zig_fmt.step.dependOn(&imports_fmt.step);
    b.step("fmt", "Organize imports and format Zig sources").dependOn(&zig_fmt.step);

    const imports_check = import_sorter.addImportSorter(b, .{ .paths = paths, .check = true });
    const zig_fmt_check = b.addFmt(.{ .paths = paths, .check = true });
    const fmt_check = b.step("fmt-check", "Check import ordering and Zig source formatting");
    fmt_check.dependOn(&imports_check.step);
    fmt_check.dependOn(&zig_fmt_check.step);
}
```

Here, `zig build fmt` sorts imports before running `zig fmt`, and
`zig build fmt-check` checks both import ordering and Zig formatting.
The built-in formatter always uses the configured `paths`; forwarded flags and paths
apply only to the import sorter. Use `fmt-check` to check both without writing.

```sh
zig build fmt
zig build fmt -- --imports-sorter-write
zig build fmt -- --imports-sorter-check
zig build test fmt-check
zig build fmt -- src/example.zig
zig build fmt -- --imports-sorter-check src/example.zig
zig build fmt -- src/a.zig src/b.zig
```

Explicit files or directories replace the configured paths. Both write and check
modes support these file types, whether passed directly or found in a directory:

- `.zig`: organize imports and format Zig source code.
- `.zon`: format Zig Object Notation, including `build.zig.zon`.

Other file types are ignored. Directories are searched recursively, skipping
hidden entries (names starting with `.`), `zig-out`, and `zig-pkg`. Symbolic
links inside directories are skipped. Explicitly passing an unsupported path
type, such as a symbolic link, fails. Explicit hidden files and directories can
be passed as paths; hidden entries inside directories are still skipped.

Flags can appear before or after paths; use `--`
before paths starting with `-`. Write and check modes cannot be combined,
including a run configured with `.check = true` and `--imports-sorter-write`.

Sorter flags are `--imports-sorter-write` and `--imports-sorter-check`.
The build API passes configured paths using `--imports-sorter-default-path PATH`;
explicit positional paths replace those defaults. No argument separator is needed
between configured paths and forwarded arguments. Use `--` only to end option
parsing for paths starting with `-`.
