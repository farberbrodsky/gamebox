/// Assumptions:
/// - std is imported: const std = @import("std");
/// - vk is imported: const vk = @import("vkheaders.zig");
pub fn generateFunctionMap(writer: anytype) !void {
    try writer.writeAll("/* ENTER AUTOGEN: generateFunctionMap */");

    try writer.print("std.StaticStringMap(vk.c.PFN_vkVoidFunction).initComptime([_]struct { []const u8, vk.c.PFN_vkVoidFunction } {");
    try writer.print("});");

    try writer.writeAll("/* LEAVE AUTOGEN: generateFunctionMap */");
}
