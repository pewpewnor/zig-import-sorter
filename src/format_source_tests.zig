const std = @import("std");

const formatSource = @import("format_source.zig").formatSource;

fn format(source: []const u8, mode: std.zig.Ast.Mode) ![]u8 {
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    return formatSource(std.testing.io, std.testing.allocator, &environ, source, mode);
}

test "organizes aliases and preserves computed declarations and unicode" {
    const source =
        \\const zebra = @import("zebra");
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\const alpha = @import("alpha");
        \\
        \\pub const label = "日本語 🦎";
        \\pub const Action = alpha.Action("move");
        \\
    ;
    const actual = try format(source, .zig);
    defer std.testing.allocator.free(actual);
    const expected =
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\
        \\const alpha = @import("alpha");
        \\const zebra = @import("zebra");
        \\
        \\pub const label = "日本語 🦎";
        \\pub const Action = alpha.Action("move");
        \\
    ;
    try std.testing.expectEqualStrings(expected, actual);
    const repeated = try format(actual, .zig);
    defer std.testing.allocator.free(repeated);
    try std.testing.expectEqualStrings(actual, repeated);
}

test "formats zon without treating it as zig declarations" {
    const actual = try format(".{.name=.example,.version=\"0.1.0\"}", .zon);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(".{ .name = .example, .version = \"0.1.0\" }\n", actual);
}

test "rejects invalid syntax and preserves compile error fixtures" {
    try std.testing.expectError(error.InvalidSyntax, format("const broken = ;", .zig));
    const actual = try format("const value = missing;\n", .zig);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("const value = missing;\n", actual);
}

test "uses zig formatting without applying unrelated fixes" {
    const actual = try format("pub fn hello( unused: u8 ) void {var x:u8=1;_ = x;}", .zig);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("pub fn hello(unused: u8) void {\n    var x: u8 = 1;\n    _ = x;\n}\n", actual);
}

test "applies byte offsets after unicode text and normalizes crlf" {
    const source = "pub const label = \"日本語 🦎\";\r\nconst zebra = @import(\"zebra\");\r\nconst alpha = @import(\"alpha\");\r\n";
    const actual = try format(source, .zig);
    defer std.testing.allocator.free(actual);
    try std.testing.expect(std.mem.find(u8, actual, "日本語 🦎") != null);
    try std.testing.expect(std.mem.findScalar(u8, actual, '\r') == null);
    const alpha = std.mem.find(u8, actual, "const alpha") orelse return error.MissingImport;
    const zebra = std.mem.find(u8, actual, "const zebra") orelse return error.MissingImport;
    try std.testing.expect(alpha < zebra);
    const repeated = try format(actual, .zig);
    defer std.testing.allocator.free(repeated);
    try std.testing.expectEqualStrings(actual, repeated);
}

test "formats empty sources and rejects invalid zon" {
    const empty = try format("", .zig);
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqualStrings("", empty);
    try std.testing.expectError(error.InvalidSyntax, format(".{ .value = }", .zon));
}

test "preserves documentation and comments while organizing imports" {
    const source =
        \\//! Module documentation.
        \\const zebra = @import("zebra"); // zebra comment
        \\const alpha = @import("alpha"); // alpha comment
        \\
        \\/// Public documentation.
        \\pub const value = 42;
        \\
    ;
    const actual = try format(source, .zig);
    defer std.testing.allocator.free(actual);
    for ([_][]const u8{ "//! Module documentation.", "// zebra comment", "// alpha comment", "/// Public documentation.", "pub const value = 42;" }) |text| {
        try std.testing.expect(std.mem.find(u8, actual, text) != null);
    }
    const repeated = try format(actual, .zig);
    defer std.testing.allocator.free(repeated);
    try std.testing.expectEqualStrings(actual, repeated);
}
