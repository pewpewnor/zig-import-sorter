# zig-imports-sorter

Build dependency that uses ZLS to organize imports and formats Zig sources.
No standalone executable is installed.

Add the dependency as `zig-imports-sorter`, then register the formatting step in
`build.zig`:

```zig
const imports_sorter = @import("zig-imports-sorter");

pub fn build(b: *std.Build) void {
    imports_sorter.addSteps(b, &.{ "build.zig", "build.zig.zon", "src" });
}
```

```sh
zig build fmt                         # Write changes to the configured paths
zig build fmt -- -w                   # Same, explicit write mode
zig build fmt -- --write              # Long form
zig build fmt -- -c                   # Check without writing; fail if dirty
zig build fmt -- --check              # Long form
zig build test fmt -Dfmt-check        # Combine step without forwarding flags
zig build fmt -- src/example.zig      # Format one file
zig build fmt -- -c src/example.zig   # Check one file
zig build fmt -- src/a.zig src/b.zig  # Format selected files
```

Explicit files or directories replace the configured paths. Directories are
searched recursively for `.zig` and `.zon` files, skipping hidden entries,
`zig-out`, and `zig-pkg`. Flags can appear before or after paths; use `--`
before paths starting with `-`. Write and check modes cannot be combined,
including `-Dfmt-check` with `--write`.

Writing by default matches `zig fmt`; use check mode in CI.
