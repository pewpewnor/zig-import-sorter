# zig-imports-sorter

Build dependency that uses ZLS to organize imports and formats Zig sources.
No standalone executable is installed.

Add the dependency as `zig-imports-sorter`, then create formatter runs and
attach them to your own steps in `build.zig`:

```zig
const std = @import("std");
const imports_sorter = @import("zig-imports-sorter");

pub fn build(b: *std.Build) void {
    const paths = &.{ "build.zig", "build.zig.zon", "src" };
    const fmt = imports_sorter.addRun(b, .{ .paths = paths });
    b.step("fmt", "Organize imports and format Zig sources").dependOn(&fmt.step);

    const fmt_check = imports_sorter.addRun(b, .{ .paths = paths, .check = true });
    b.step("fmt-check", "Check Zig source formatting").dependOn(&fmt_check.step);
}
```

`addRun` returns a `*std.Build.Step.Run`; it does not register named steps or
build options. Callers choose step names and can attach the runs to other steps.

```sh
zig build fmt                         # Write changes to the configured paths
zig build fmt -- -w                   # Same, explicit write mode
zig build fmt -- --write              # Long form
zig build fmt -- -c                   # Check without writing; fail if dirty
zig build fmt -- --check              # Long form
zig build test fmt-check             # Combine steps without forwarding flags
zig build fmt -- src/example.zig      # Format one file
zig build fmt -- -c src/example.zig   # Check one file
zig build fmt -- src/a.zig src/b.zig  # Format selected files
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
including a run configured with `.check = true` and `--write`.

Writing by default matches `zig fmt`; use check mode in CI.
