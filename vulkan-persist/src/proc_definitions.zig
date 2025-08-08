const std = @import("std");
const testing = std.testing;
const vk = @import("vkheaders.zig");
const so = @import("so.zig");

const FunctionPair = struct { []const u8, vk.c.PFN_vkVoidFunction };

pub const InstanceFunctions = std.StaticStringMap(vk.c.PFN_vkVoidFunction).initComptime([_]FunctionPair{
    .{ "vkCreateInstance", @ptrCast(&so.VK_LAYER_GAMEBOX_persist_CreateInstance) },
    .{ "vkCreateDevice", @ptrCast(&so.VK_LAYER_GAMEBOX_persist_CreateDevice) },
    .{ "vkEnumeratePhysicalDevices", @ptrCast(&so.EnumeratePhysicalDevices) },
});

pub const DeviceFunctions = std.StaticStringMap(vk.c.PFN_vkVoidFunction).initComptime([_]FunctionPair{});
