const CodeWriter = @import("CodeWriter.zig");
/// Assumptions:
/// - std is imported: const std = @import("std");
/// - vk is imported: const vk = @import("vk_headers");
pub fn generateFunctionMap(cw: *CodeWriter, const_name: []const u8, function_names: []const struct { []const u8, []const u8 }) void {
    cw.enterContextComment("generateFunctionMap");
    defer cw.leaveContextComment("generateFunctionMap");

    cw.startLine();
    cw.print("pub const {s} = ", .{const_name});
    cw.raw("std.StaticStringMap(vk.c.PFN_vkVoidFunction).initComptime([_]struct { []const u8, vk.c.PFN_vkVoidFunction } {");
    cw.endLine();
    cw.enterIndent();
    for (function_names) |function_name| {
        cw.line(".{{ \"{s}\", @ptrCast({s}) }},", .{ function_name[0], function_name[1] });
    }
    defer cw.leaveIndent();
    cw.lineRaw("});");
}
