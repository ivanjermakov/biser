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
    const info = @typeInfo(T);
    switch (info) {
        .int, .float, .bool => {
            try writer.writeAll(std.mem.asBytes(&value));
        },
        else => @panic("not implemented"),
    }
}

test "serialize" {
    const alloc = std.testing.allocator;
    inline for (.{
        .{ u8, 4, &.{4} },
        .{ u32, 4, &.{ 4, 0, 0, 0 } },
        .{ f16, 12.34, &.{ 0x2C, 0x4A } },
    }) |d| {
        const t = d[0];
        const value = d[1];
        const expected = d[2];
        const buf = try serializeAlloc(t, alloc, value);
        defer alloc.free(buf);
        try std.testing.expectEqualSlices(u8, expected, buf);
    }
}
