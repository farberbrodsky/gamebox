const CodeWriter = @import("CodeWriter.zig");
/// Assumptions:
/// - std is imported: const std = @import("std");
/// - vk is imported: const vk = @import("vk_headers");
pub fn generateFunctionMap(const_name: []const u8, cw: *CodeWriter, function_names: []const []const u8) void {
    cw.enterContextComment("generateFunctionMap");
    defer cw.leaveContextComment("generateFunctionMap");

    cw.startLine();
    cw.print("const {s} = ", .{const_name});
    cw.raw("std.StaticStringMap(vk.c.PFN_vkVoidFunction).initComptime([_]struct { []const u8, vk.c.PFN_vkVoidFunction } {");
    cw.endLine();
    cw.enterIndent();
    for (function_names) |function_name| {
        cw.line(".{{ \"{s}\", @ptrCast(0) }},", .{function_name});
    }
    defer cw.leaveIndent();
    cw.lineRaw("});");
}
