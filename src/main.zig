const std = @import("std");
const linux = @import("std.os.linux");

const STACK_SIZE = 1024 * 1024;

pub fn evil_twin(arg: usize) callconv(.c) u8 {
    _ = arg;
    return 3;
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // linux.mmap()
    // linux.clone()
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
