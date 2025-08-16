const CodeWriter = @import("CodeWriter.zig");
/// Assumptions:
/// - vk is imported: const vk = @import("vk_headers");
pub fn generateFunctionList(cw: *CodeWriter, const_name: []const u8, function_names: []const struct { []const u8, []const u8 }) void {
    cw.enterContextComment("generateFunctionList");
    defer cw.leaveContextComment("generateFunctionList");

    cw.startLine();
    cw.print("pub const {s} = ", .{const_name});
    cw.raw("[_]struct { []const u8, vk.c.PFN_vkVoidFunction } {");
    cw.endLine();
    cw.enterIndent();
    for (function_names) |function_name| {
        cw.line(".{{ \"{s}\", @ptrCast(&{s}) }},", .{ function_name[0], function_name[1] });
    }
    defer cw.leaveIndent();
    cw.lineRaw("};");
}
