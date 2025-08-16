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

pub fn generateDispatchTableStruct(cw: *CodeWriter, struct_name: []const u8, function_names: []const struct { []const u8, []const u8 }) void {
    cw.enterContextComment("generateDispatchTableStruct");
    defer cw.leaveContextComment("generateDispatchTableStruct");

    cw.line("pub const {s} = struct {{", .{struct_name});
    cw.enterIndent();
    for (function_names) |function_name| {
        cw.line("{s}: ?vk.c.PFN_vkVoidFunction = null,", .{function_name[0]});
    }
    cw.leaveIndent();
    cw.line("};", .{});
}
