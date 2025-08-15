const std = @import("std");
const CodeWriter = @import("CodeWriter.zig");
const Command = @import("../generate_vk_wrappers.zig").Command;

pub fn generateWrapperFunction(cw: *CodeWriter, wrapper_name: []const u8, command: *const Command) void {
    cw.enterContextComment("generateWrapperFunction");
    defer cw.leaveContextComment("generateWrapperFunction");

    cw.startLine();
    cw.print("fn {s}(", .{wrapper_name});
    if (command.params) |command_params| for (0.., command_params) |i, param| {
        _ = param;
        if (i != 0) {
            cw.raw(", ");
        }
        cw.print("a{d}: usize", .{i});
    };
    cw.raw(") usize {");
    cw.endLine();
    cw.enterIndent();
    cw.lineRaw("// TODO");
    cw.leaveIndent();
    cw.lineRaw("}");
}
