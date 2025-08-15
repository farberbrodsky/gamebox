const CodeWriter = @import("CodeWriter.zig");
const Command = @import("../generate_vk_wrappers.zig").Command;

pub fn generateWrapperFunction(cw: *CodeWriter, wrapper_name: []const u8, command: *Command) void {
    cw.enterContextComment("generateWrapperFunction");
    defer cw.leaveContextComment("generateWrapperFunction");

    cw.line("fn {s}() usize {{", .{wrapper_name});
    _ = command;
    cw.lineRaw("}");
}
