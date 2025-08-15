const std = @import("std");
const Self = @This();

writer: std.io.AnyWriter,
indent: u32 = 0,
err: ?anyerror = null,

pub fn enterIndent(self: *Self) void {
    self.indent += 1;
}

pub fn leaveIndent(self: *Self) void {
    self.indent -= 1;
}

pub fn line(self: *Self, comptime format: []const u8, args: anytype) void {
    self.writer.writeByteNTimes(' ', 4 * self.indent) catch |err| {
        self.err = err;
        return;
    };
    self.writer.print(format, args) catch |err| {
        self.err = err;
        return;
    };
    self.writer.writeByte('\n') catch |err| {
        self.err = err;
        return;
    };
}
