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
            try assertSize(info.child);
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
        .array => |info| {
            for (value) |item| {
                try serializeWriter(info.child, item, writer);
            }
        },
        else => @panic(std.fmt.comptimePrint("cannot serialize {}", .{T})),
    }
}

pub const DeserializeOptions = struct {
    offset: ?*usize = null,
};
pub fn deserialize(comptime T: anytype, buf: []const u8, opts: DeserializeOptions) !T {
    var value: T = undefined;
    var offset: usize = 0;
    switch (@typeInfo(T)) {
        .int, .float, .bool => {
            if (buf.len < @sizeOf(T)) return error.Eof;
            @memcpy(std.mem.asBytes(&value), buf[0..@sizeOf(T)]);
            if (opts.offset) |off| off.* += @sizeOf(T);
        },
        .@"struct" => |info| {
            inline for (info.fields) |field_info| {
                const field = try deserialize(field_info.type, buf[offset..], opts);
                @field(value, field_info.name) = field;
                offset += @sizeOf(field_info.type);
            }
        },
        .pointer => |info| {
            try assertSize(info.child);
            switch (info.size) {
                .slice => {
                    if (buf.len < @sizeOf(u32)) return error.Eof;
                    value.len = try deserialize(u32, buf[0..], opts);
                    offset += @sizeOf(u32);
                    if (buf.len < offset + value.len * @sizeOf(info.child)) return error.Eof;
                    value.ptr = @as([*]info.child, @alignCast(@ptrCast(@constCast(buf[offset..].ptr))));
                    if (opts.offset) |off| off.* += value.len * @sizeOf(info.child);
                },
                else => @panic(std.fmt.comptimePrint("cannot deserialize {}", .{info})),
            }
        },
        .array => |info| {
            try assertSize(info.child);
            if (buf.len < offset + value.len * @sizeOf(info.child)) return error.Eof;
            @memcpy(std.mem.asBytes(value[0..]), buf[offset..]);
            if (opts.offset) |off| off.* += value.len * @sizeOf(info.child);
        },
        else => @panic(std.fmt.comptimePrint("cannot deserialize {}", .{T})),
    }
    return value;
}

fn assertSize(comptime T: anytype) !void {
    const expected = @sizeOf(T);
    switch (@typeInfo(T)) {
        .int, .float, .bool => {},
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                try assertSize(field.type);
            }
        },
        .pointer => |info| {
            if (expected != @sizeOf(info.child)) {
                return error.SizeMismatch;
            }
        },
        .array => |info| {
            try assertSize(info.child);
        },
        else => @panic(std.fmt.comptimePrint("unsupported {}", .{T})),
    }
}

test "serialize" {
    const alloc = std.testing.allocator;
    const A = struct { a: u8 };
    const B = struct { a: u8, b: u32, c: A };
    const C = struct { a: []A };
    inline for (.{
        .{ u8, 4, &.{4} },
        .{ u32, 4, &.{ 4, 0, 0, 0 } },
        .{ f16, 12.34, &.{ 0x2C, 0x4A } },
        .{ A, A{ .a = 4 }, &.{4} },
        .{ B, B{ .a = 5, .b = 1, .c = A{ .a = 4 } }, &.{ 5, 1, 0, 0, 0, 4 } },
        .{ []u8, @constCast(&[_]u8{ 1, 2, 3 }), &.{ 3, 0, 0, 0, 1, 2, 3 } },
        .{ C, C{ .a = @constCast(&[_]A{ .{ .a = 1 }, .{ .a = 2 }, .{ .a = 3 } }) }, &.{ 3, 0, 0, 0, 1, 2, 3 } },
        .{ [2]f32, .{ 1, 2 }, &.{ 0, 0, 0x80, 0x3F, 0, 0, 0, 0x40 } },
    }) |d| {
        const t = d[0];
        const value = d[1];
        const expected = d[2];
        const buf = try serializeAlloc(t, alloc, value);
        defer alloc.free(buf);
        try std.testing.expectEqualSlices(u8, expected, buf);
    }
}

test "deserialize" {
    const A = struct { a: u8 };
    const B = struct { a: u8, b: u32, c: A };
    const C = struct { a: []A };
    inline for (.{
        .{ u8, 4, &.{4} },
        .{ u32, 4, &.{ 4, 0, 0, 0 } },
        .{ f16, 12.34, &.{ 0x2C, 0x4A } },
        .{ A, A{ .a = 4 }, &.{4} },
        .{ B, B{ .a = 5, .b = 1, .c = A{ .a = 4 } }, &.{ 5, 1, 0, 0, 0, 4 } },
        .{ []u8, @constCast(&[_]u8{ 1, 2, 3 }), &.{ 3, 0, 0, 0, 1, 2, 3 } },
        .{ C, C{ .a = @constCast(&[_]A{ .{ .a = 1 }, .{ .a = 2 }, .{ .a = 3 } }) }, &.{ 3, 0, 0, 0, 1, 2, 3 } },
        .{ [2]f32, .{ 1, 2 }, &.{ 0, 0, 0x80, 0x3F, 0, 0, 0, 0x40 } },
    }) |d| {
        const t = d[0];
        const expected = d[1];
        const buf = d[2];
        var offset: usize = 0;
        const actual = try deserialize(t, buf, .{ .offset = &offset });
        try std.testing.expectEqualDeep(expected, actual);
        try std.testing.expectEqual(buf.len, offset);
    }
}

test "deserialize no segfault" {
    try std.testing.expectError(error.Eof, deserialize(u8, &.{}, .{}));
    try std.testing.expectError(error.Eof, deserialize(struct { a: u8 }, &.{}, .{}));
    try std.testing.expectError(error.Eof, deserialize([]u8, &.{ 1, 0, 0, 0 }, .{}));
}
