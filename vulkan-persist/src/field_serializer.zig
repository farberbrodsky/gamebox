const std = @import("std");

const SerializerParams = struct {
    is_optional1: ?bool = null,
    is_optional2: ?bool = null,
    /// -2 - null terminated, always
    /// -1 - no length, ever
    /// 0 or positive - number of items in an array
    length: isize = -1,
    /// size of each atomic item
    /// Usually the size of a pointer, but sometimes less: such as char
    item_size: usize = @sizeOf(usize),
};

/// Optimizes length encoding for small lengths up to 254:
/// byte 0 <255: the entire length
/// byte 0 =255: a little endian usize representation comes after it
fn encodeLengthInteger(out_alloc: std.mem.Allocator, out: *std.ArrayList(u8), length: usize) !void {
    if (length < 255) {
        (try out.addOne(out_alloc)).* = @intCast(length);
    } else {
        const arr = try out.addManyAsArray(out_alloc, 1 + @sizeOf(isize));
        arr[0] = 255;
        arr[1..].* = @bitCast(std.mem.nativeToLittle(usize, length));
    }
}

test "length encoding" {
    const alloc = std.testing.allocator;
    var serialized = std.ArrayList(u8).empty;

    try encodeLengthInteger(alloc, &serialized, 3);
    try std.testing.expectEqualSlices(u8, &.{3}, serialized.items);
    serialized.clearAndFree(alloc);

    try encodeLengthInteger(alloc, &serialized, 256);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 1, 0, 0, 0, 0, 0, 0 }, serialized.items);
    serialized.clearAndFree(alloc);
}

pub inline fn serializeField(out_alloc: std.mem.Allocator, out: *std.ArrayList(u8), serializer_params: SerializerParams, value: usize) !void {
    _ = .{ out_alloc, out, serializer_params, value };
    const length = serializer_params.length;

    std.debug.assert(length >= -2);

    switch (length) {
        -2 => {
            // null terminated, always
        },
        -1 => {
            // no length, ever
        },
        else => {
            // this is an array
            const unsigned_length: usize = @intCast(@as(isize, length));
            try encodeLengthInteger(out_alloc, out, unsigned_length);
        },
    }
}
