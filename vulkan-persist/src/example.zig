//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const field_serializer = @import("field_serializer.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&.{});
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    var serialized = std.ArrayList(u8).empty;

    try field_serializer.serializeField(alloc, &serialized, .{ .length = 3 }, 1234);
    try stdout.print("hello {any}\n", .{serialized});
    serialized.clearAndFree(alloc);

    try field_serializer.serializeField(alloc, &serialized, .{ .length = 300 }, 1234);
    try stdout.print("hello {any}\n", .{serialized});
    serialized.clearAndFree(alloc);

    try stdout.flush(); // Don't forget to flush!
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("vulkan_persist_lib");

test {
    std.testing.refAllDeclsRecursive(@This());
}
