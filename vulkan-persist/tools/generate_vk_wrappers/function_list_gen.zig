const CodeWriter = @import("CodeWriter.zig");

/// The FunctionListEntry struct represents both the information necesary for a Function List, and a Dispatch Table.
/// This is because they usually go together, and it is useful to build the same structure for both.
pub const FunctionListEntry = struct {
    command_name: []const u8 = &.{},
    wrapper_name: []const u8 = &.{},
    function_type: []const u8 = &.{},
};

/// Within function_entries, only makes use of command_name and wrapper_name.
pub fn generateFunctionList(cw: *CodeWriter, const_name: []const u8, function_entries: []const FunctionListEntry) void {
    cw.enterContextComment("generateFunctionList");
    defer cw.leaveContextComment("generateFunctionList");

    cw.startLine();
    cw.print("pub const {s} = ", .{const_name});
    cw.raw("[_]struct { []const u8, vk.c.PFN_vkVoidFunction } {");
    cw.endLine();
    cw.enterIndent();
    for (function_entries) |function_entry| {
        cw.line(".{{ \"{s}\", @ptrCast(&{s}) }},", .{ function_entry.command_name, function_entry.wrapper_name });
    }
    defer cw.leaveIndent();
    cw.lineRaw("};");
}

/// Only uses the left part - original function name, not its wrapper name
pub fn generateDispatchTableStruct(cw: *CodeWriter, struct_name: []const u8, function_entries: []const FunctionListEntry) void {
    cw.enterContextComment("generateDispatchTableStruct");
    defer cw.leaveContextComment("generateDispatchTableStruct");

    cw.line("pub const {s} = struct {{", .{struct_name});
    cw.enterIndent();
    for (function_entries) |function_entry| {
        cw.line("{s}: ?{s} = null,", .{ function_entry.command_name, function_entry.function_type });
    }
    cw.leaveIndent();
    cw.lineRaw("};");
}
