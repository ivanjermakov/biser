const std = @import("std");
const Io = std.Io;

pub fn serializeAlloc(comptime T: anytype, alloc: std.mem.Allocator, value: T) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(alloc);
    defer alloc_writer.deinit();
    try serializeWriter(T, value, &alloc_writer.writer);
    const bytes = alloc_writer.writer.buffered();
    return try alloc.dupe(u8, bytes);
}

fn serializeWriter(comptime T: anytype, value: T, writer: *std.Io.Writer) !void {
    switch (@typeInfo(T)) {
        .int, .float, .bool => {
            try writer.writeAll(std.mem.asBytes(&value));
        },
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                try serializeWriter(field.type, @field(value, field.name), writer);
            }
        },
        .pointer => |info| {
            switch (info.size) {
                .slice => {
                    const len = std.math.cast(u32, value.len) orelse @panic("slice too long");
                    try serializeWriter(u32, len, writer);
                    for (value) |item| {
                        try serializeWriter(info.child, item, writer);
                    }
                },
                else => @panic(std.fmt.comptimePrint("cannot serialize {}", .{info})),
            }
        },
        else => @panic(std.fmt.comptimePrint("cannot serialize {}", .{T})),
    }
}

test "serialize" {
    const alloc = std.testing.allocator;
    const A = struct { a: u8 };
    const B = struct { a: u8, b: u32, c: A };
    inline for (.{
        .{ u8, 4, &.{4} },
        .{ u32, 4, &.{ 4, 0, 0, 0 } },
        .{ f16, 12.34, &.{ 0x2C, 0x4A } },
        .{ A, A{ .a = 4 }, &.{4} },
        .{ B, B{ .a = 5, .b = 1, .c = A{ .a = 4 } }, &.{ 5, 1, 0, 0, 0, 4 } },
        .{ []u8, @constCast(&[_]u8{ 0, 1, 2 }), &.{ 3, 0, 0, 0, 0, 1, 2 } },
    }) |d| {
        const t = d[0];
        const value = d[1];
        const expected = d[2];
        const buf = try serializeAlloc(t, alloc, value);
        defer alloc.free(buf);
        try std.testing.expectEqualSlices(u8, expected, buf);
    }
}
