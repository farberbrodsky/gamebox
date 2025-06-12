const std = @import("std");
/// Most of the definitions come straight from the headers, but we have some additional wrappers to make things nicer.
pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vk_layer.h");
});

pub const Instance = c.VkInstance;
pub const Device = c.VkDevice;

/// This is fun if you want to play nice and use Vulkan's provided allocator
/// We do not create this object: it is casted from VkAllocationCallbacks.
pub const Allocator = extern struct {
    pUserData: ?*anyopaque,
    pfnAllocation: c.PFN_vkAllocationFunction,
    pfnReallocation: c.PFN_vkReallocationFunction,
    pfnFree: c.PFN_vkFreeFunction,
    pfnInternalAllocation: c.PFN_vkInternalAllocationNotification,
    pfnInternalFree: c.PFN_vkInternalFreeNotification,

    pub fn allocator(self: *const Allocator) std.mem.Allocator {
        return .{
            .ptr = @constCast(self),
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free
            }
        };
    }

    fn alloc(ctx: *const anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        std.debug.print("vkalloc({d})\n", .{len});
        _ = ret_addr;
        const self: *const Allocator = @ptrCast(@alignCast(ctx));
        return @ptrCast(self.pfnAllocation.?(self.pUserData, len, @intFromEnum(alignment), c.VK_SYSTEM_ALLOCATION_SCOPE_INSTANCE));
    }

    /// resize is unsupported because there is no equivalent in with pfnReallocation
    fn resize(ctx: *const anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        std.debug.print("vkresize -> false\n", .{});
        _ = .{ ctx, memory, alignment, new_len, ret_addr };
        return false;
    }

    fn remap(ctx: *const anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        std.debug.print("vkremap({x}, {d})\n", .{@intFromPtr(memory.ptr), new_len});
        _ = ret_addr;
        const self: *const Allocator = @ptrCast(@alignCast(ctx));
        return @ptrCast(self.pfnReallocation.?(self.pUserData, memory.ptr, new_len, @intFromEnum(alignment), c.VK_SYSTEM_ALLOCATION_SCOPE_INSTANCE));
    }

    fn free(ctx: *const anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        std.debug.print("vkfree({d})\n", .{@intFromPtr(buf.ptr)});
        _ = .{ alignment, ret_addr };
        const self: *const Allocator = @ptrCast(@alignCast(ctx));
        self.pfnFree.?(self.pUserData, buf.ptr);
    }
};


/// Helper type for get_chain_info
const TypedLink = extern struct {
    sType: c.VkStructureType,
    pNext: ?*@This()
};

/// Helper type for get_chain_info
const TypedLinkFunc = extern struct {
    sType: c.VkStructureType,
    pNext: ?*@This(),
    function: c.VkLayerFunction
};

/// Adapted from the Vulkan-Profiles repository, and mentioned in LoaderLayerInterface.md
fn get_chain_info_generic(list: *TypedLink, item_type: c_int, func: c.VkLayerFunction) ?*TypedLinkFunc {
    var lnk = list.pNext;

    while (lnk) |s| : (lnk = s.pNext) {
        // interested in finding the first LOADER_INSTANCE_CREATE_INFO member, where function == func
        if (s.sType != item_type)
            continue;

        const info: *TypedLinkFunc = @ptrCast(s);
        if (info.function == func)
            return info;
    }

    return null;
}

pub fn get_chain_info_instance(pCreateInfo: *const c.VkInstanceCreateInfo, func: c.VkLayerFunction) ?*c.VkLayerInstanceCreateInfo {
    return @ptrCast(get_chain_info_generic(@alignCast(@ptrCast(@constCast(pCreateInfo))), c.VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO, func));
}

pub fn get_chain_info_device(pCreateInfo: *const c.VkDeviceCreateInfo, func: c.VkLayerFunction) ?*c.VkLayerDeviceCreateInfo {
    return @ptrCast(get_chain_info_generic(@alignCast(@ptrCast(@constCast(pCreateInfo))), c.VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO, func));
}
