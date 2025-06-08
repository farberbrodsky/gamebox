const std = @import("std");
const testing = std.testing;
const vk = @import("vkheaders.zig");

pub export fn VK_LAYER_GAMEBOX_persist_CreateInstance(pCreateInfo: *const vk.c.VkInstanceCreateInfo, pAllocator: *const vk.c.VkAllocationCallbacks, pInstance: ?*vk.Instance) callconv(.c) vk.c.VkResult {
    std.debug.print("CreateInstance\n", .{});
    // Find the VkLayerInstanceCreateInfo/VkLayerDeviceCreateInfo structure in the VkInstanceCreateInfo/VkDeviceCreateInfo structure.
    const chain_info = vk.get_chain_info(pCreateInfo, vk.c.VK_LAYER_LINK_INFO) orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;
    const layer_info: *vk.c.VkLayerInstanceLink = chain_info.u.pLayerInfo orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;

    // Get the next entity's vkGet*ProcAddr from the "pLayerInfo" field.
    const next_GetInstanceProcAddr = layer_info.pfnNextGetInstanceProcAddr orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;

    // For CreateInstance get the next entity's vkCreateInstance by calling the "pfnNextGetInstanceProcAddr": pfnNextGetInstanceProcAddr(NULL, "vkCreateInstance").
    // (For CreateDevice get the next entity's vkCreateDevice by calling the "pfnNextGetInstanceProcAddr": pfnNextGetInstanceProcAddr(instance, "vkCreateDevice"), passing the already created instance handle.)
    const next_CreateInstance: vk.c.PFN_vkCreateInstance = @ptrCast(next_GetInstanceProcAddr(null, "vkCreateInstance") orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED);

    // Advanced the linked list to the next node: pLayerInfo = pLayerInfo->pNext.
    chain_info.u.pLayerInfo = layer_info.pNext;

    // Call down the chain either vkCreateDevice or vkCreateInstance
    const next_result = next_CreateInstance.?(pCreateInfo, pAllocator, pInstance);
    if (next_result != vk.c.VK_SUCCESS)
        return next_result;

    // Initialize the layer dispatch table by calling the next entity's Get*ProcAddr function once for each Vulkan function needed in the dispatch table
    // ...!!!
    return vk.c.VK_SUCCESS;
}


pub export fn VK_LAYER_GAMEBOX_persist_GetInstanceProcAddr(instance: ?*vk.Instance, name: ?[*:0]const u8) callconv(.c) vk.c.PFN_vkVoidFunction {
    if (name == null)
        return null;
    std.debug.print("GetInstanceProcAddr({s})\n", .{name.?});
    if (instance == null)
        return null;

    // intercept core commands
    const command_id = std.meta.stringToEnum(enum {
        vkCreateInstance
    }, std.mem.span(name.?));

    if (command_id) |c| return switch (c) {
        .vkCreateInstance => @ptrCast(&VK_LAYER_GAMEBOX_persist_CreateInstance)
    } else {
        // Other command
        return null;
    }
}

pub export fn VK_LAYER_GAMEBOX_persist_GetDeviceProcAddr(device: ?*vk.Device, name: ?[*:0]const u8) callconv(.c) vk.c.PFN_vkVoidFunction {
    _ = device;
    std.debug.print("GetDeviceProcAddr({s})\n", .{name.?});
    return null;
}
