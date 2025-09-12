const std = @import("std");
const Self = @This();

writer: *std.Io.Writer,
indent: u32 = 0,
err: ?anyerror = null,

pub fn enterIndent(self: *Self) void {
    self.indent += 1;
}

pub fn leaveIndent(self: *Self) void {
    self.indent -= 1;
}

pub fn line(self: *Self, comptime format: []const u8, args: anytype) void {
    self.startLine();
    self.print(format, args);
    self.endLine();
}

pub fn startLine(self: *Self) void {
    if (self.err != null)
        return;
    self.writer.splatByteAll(' ', 4 * self.indent) catch |err| {
        self.err = err;
    };
}

pub fn endLine(self: *Self) void {
    if (self.err != null)
        return;
    self.writer.writeByte('\n') catch |err| {
        self.err = err;
    };
}

pub fn print(self: *Self, comptime format: []const u8, args: anytype) void {
    if (self.err != null)
        return;
    self.writer.print(format, args) catch |err| {
        self.err = err;
        return;
    };
}

pub fn raw(self: *Self, str: []const u8) void {
    self.print("{s}", .{str});
}

pub fn lineRaw(self: *Self, str: []const u8) void {
    self.line("{s}", .{str});
}

pub fn enterContextComment(self: *Self, name: []const u8) void {
    self.line("// ENTER: {s}", .{name});
}

pub fn leaveContextComment(self: *Self, name: []const u8) void {
    self.line("// LEAVE: {s}", .{name});
}
