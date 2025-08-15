const std = @import("std");
const testing = std.testing;
const vk = @import("vk_headers");
const State = @import("state.zig");
const proc_definitions = @import("proc_definitions.zig");
const wrappers = @import("vk_wrappers");

var instance_table: State.InstanceState = .{};
var device_table: State.DeviceState = .{};

pub export fn VK_LAYER_GAMEBOX_persist_CreateInstance(pCreateInfo: *const vk.c.VkInstanceCreateInfo, pAllocator: ?*const vk.c.VkAllocationCallbacks, pInstance: *vk.Instance) callconv(.c) vk.c.VkResult {
    std.debug.print("CreateInstance\n", .{});
    // Find the VkLayerInstanceCreateInfo/VkLayerDeviceCreateInfo structure in the VkInstanceCreateInfo/VkDeviceCreateInfo structure.
    const chain_info = vk.get_chain_info_instance(pCreateInfo, vk.c.VK_LAYER_LINK_INFO) orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;
    const layer_info: *vk.c.VkLayerInstanceLink = chain_info.u.pLayerInfo orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;

    // Get the next entity's vkGet*ProcAddr from the "pLayerInfo" field.
    const next_GetInstanceProcAddr = layer_info.pfnNextGetInstanceProcAddr orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;

    // For CreateInstance get the next entity's vkCreateInstance by calling the "pfnNextGetInstanceProcAddr": pfnNextGetInstanceProcAddr(NULL, "vkCreateInstance").
    const next_CreateInstance: vk.c.PFN_vkCreateInstance = @ptrCast(next_GetInstanceProcAddr(null, "vkCreateInstance") orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED);

    // Advance the linked list to the next node: pLayerInfo = pLayerInfo->pNext.
    chain_info.u.pLayerInfo = layer_info.pNext;

    // Call down the chain either vkCreateDevice or vkCreateInstance
    const next_result = next_CreateInstance.?(pCreateInfo, pAllocator, pInstance);
    if (next_result != vk.c.VK_SUCCESS)
        return next_result;

    // Initialize the layer dispatch table by calling the next entity's Get*ProcAddr function once for each Vulkan function needed in the dispatch table
    const state = instance_table.append(pInstance.*, @ptrCast(pAllocator), .{
        next_GetInstanceProcAddr,
    }) orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;
    std.debug.print("CreateInstance created {x} instance {x}\n", .{ @intFromPtr(state), @intFromPtr(pInstance.*) });

    return vk.c.VK_SUCCESS;
}

pub export fn VK_LAYER_GAMEBOX_persist_GetInstanceProcAddr(instance: vk.Instance, name: ?[*:0]const u8) callconv(.c) vk.c.PFN_vkVoidFunction {
    if (name == null)
        return null;
    std.debug.print("GetInstanceProcAddr(instance={x}, name={s})\n", .{ @intFromPtr(instance), name.? });
    if (instance == null)
        return null;

    // intercept core commands
    if (proc_definitions.InstanceFunctions.get(std.mem.span(name.?))) |proc| {
        return proc;
    } else {
        const state = instance_table.find(instance) orelse {
            std.debug.print("Instance is not recognized.\n", .{});
            return null;
        };

        // Other command
        return state.nextGetInstanceProcAddr.?(instance, name);
    }
}

pub fn EnumeratePhysicalDevices(instance: vk.Instance, pPhysicalDeviceCount: *u32, pPhysicalDevices: ?[*]vk.c.VkPhysicalDevice) callconv(.c) vk.c.VkResult {
    if (instance == null)
        return vk.c.VK_ERROR_UNKNOWN;
    const state = instance_table.find(instance) orelse {
        std.debug.print("Instance is not recognized.\n", .{});
        return vk.c.VK_ERROR_UNKNOWN;
    };

    const next_result = state.pfnEnumeratePhysicalDevices.?(instance, pPhysicalDeviceCount, pPhysicalDevices);
    if (next_result != vk.c.VK_SUCCESS and next_result != vk.c.VK_INCOMPLETE)
        return next_result;

    // For successful or incomplete results:
    std.debug.print("ABC: instance={x}, {x}, {x}\n", .{ @intFromPtr(instance), @intFromPtr(pPhysicalDevices), pPhysicalDeviceCount.* });
    if (pPhysicalDevices) |phys_dev_arr| {
        // Map physical devices to our own
        for (phys_dev_arr[0..pPhysicalDeviceCount.*]) |phys_dev| {
            state.add_device(phys_dev) catch {
                return vk.c.VK_ERROR_OUT_OF_HOST_MEMORY;
            };
        }
    }
    std.debug.print("ABC!\n", .{});
    return next_result;
}

pub export fn VK_LAYER_GAMEBOX_persist_CreateDevice(gpu: vk.c.VkPhysicalDevice, pCreateInfo: *const vk.c.VkDeviceCreateInfo, pAllocator: ?*const vk.c.VkAllocationCallbacks, pDevice: *vk.Device) callconv(.c) vk.c.VkResult {
    var iter = instance_table.iterate();
    const parent_state = while (iter.next()) |entry| {
        if (entry.has_device(gpu)) {
            break entry;
        }
    } else {
        std.debug.print("Instance is not recognized for physical device {x}.\n", .{@intFromPtr(gpu)});
        return vk.c.VK_ERROR_INITIALIZATION_FAILED;
    };

    std.debug.print("CreateDevice\n", .{});
    // Find the VkLayerInstanceCreateInfo/VkLayerDeviceCreateInfo structure in the VkInstanceCreateInfo/VkDeviceCreateInfo structure.
    const chain_info = vk.get_chain_info_device(pCreateInfo, vk.c.VK_LAYER_LINK_INFO) orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;
    const layer_info: *vk.c.VkLayerDeviceLink = chain_info.u.pLayerInfo orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;

    // Get the next entity's vkGet*ProcAddr from the "pLayerInfo" field.
    const next_GetInstanceProcAddr = layer_info.pfnNextGetInstanceProcAddr orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;
    const next_GetDeviceProcAddr = layer_info.pfnNextGetDeviceProcAddr orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;

    // For CreateDevice get the next entity's vkCreateDevice by calling the "pfnNextGetInstanceProcAddr": pfnNextGetInstanceProcAddr(instance, "vkCreateDevice"), passing the already created instance handle.
    const next_CreateDevice: vk.c.PFN_vkCreateDevice = @ptrCast(next_GetInstanceProcAddr(@ptrCast(parent_state.header.instance), "vkCreateDevice") orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED);

    // Advance the linked list to the next node: pLayerInfo = pLayerInfo->pNext.
    chain_info.u.pLayerInfo = layer_info.pNext;

    // Call down the chain either vkCreateDevice or vkCreateInstance
    const next_result = next_CreateDevice.?(@ptrCast(gpu), pCreateInfo, pAllocator, pDevice);
    if (next_result != vk.c.VK_SUCCESS)
        return next_result;

    // Initialize the layer dispatch table by calling the next entity's Get*ProcAddr function once for each Vulkan function needed in the dispatch table
    // ...!!!
    const state = device_table.append(pDevice.*, @ptrCast(pAllocator), .{ parent_state, next_GetDeviceProcAddr }) orelse return vk.c.VK_ERROR_INITIALIZATION_FAILED;
    std.debug.print("CreateDevice created {x} device {x}\n", .{ @intFromPtr(state), @intFromPtr(pDevice.*) });

    return vk.c.VK_SUCCESS;
}

pub export fn VK_LAYER_GAMEBOX_persist_GetDeviceProcAddr(device: vk.Device, name: ?[*:0]const u8) callconv(.c) vk.c.PFN_vkVoidFunction {
    if (name == null)
        return null;
    std.debug.print("GetDeviceProcAddr(device={x}, name={s})\n", .{ @intFromPtr(device), name.? });
    if (device == null)
        return null;

    const state = device_table.find(device) orelse {
        std.debug.print("Device is not recognized.\n", .{});
        return null;
    };

    // TODO: use proc_definitions.DeviceFunctions

    return state.pfnGetDeviceProcAddr.?(device, name);
}
