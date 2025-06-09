const std = @import("std");
/// Most of the definitions come straight from the headers, but we have some additional wrappers to make things nicer.
pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vk_layer.h");
});

pub const Instance = c.VkInstance;
pub const Device = c.VkDevice;

/// This is fun if you want to play nice and use Vulkan's provided allocator
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
        _ = ret_addr;
        const self: *const Allocator = @ptrCast(@alignCast(ctx));
        return @ptrCast(self.pfnAllocation.?(self.pUserData, len, @intFromEnum(alignment), c.VK_SYSTEM_ALLOCATION_SCOPE_INSTANCE));
    }

    /// resize is unsupported because there is no equivalent in with pfnReallocation
    fn resize(ctx: *const anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = .{ ctx, memory, alignment, new_len, ret_addr };
        return false;
    }

    fn remap(ctx: *const anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *const Allocator = @ptrCast(@alignCast(ctx));
        return @ptrCast(self.pfnReallocation.?(self.pUserData, memory.ptr, new_len, @intFromEnum(alignment), c.VK_SYSTEM_ALLOCATION_SCOPE_INSTANCE));
    }

    fn free(ctx: *const anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = .{ alignment, ret_addr };
        const self: *const Allocator = @ptrCast(@alignCast(ctx));
        self.pfnFree.?(self.pUserData, buf.ptr);
    }
};

/// Adapted from the Vulkan-Profiles repository, and mentioned in LoaderLayerInterface.md
pub fn get_chain_info(pCreateInfo: *const c.VkInstanceCreateInfo, func: c.VkLayerFunction) ?*c.VkLayerInstanceCreateInfo {
    var lnk: ?*extern struct {
        sType: c.VkStructureType,
        pNext: ?*@This()
    } = @alignCast(@ptrCast(@constCast(pCreateInfo.pNext)));

    while (lnk != null) : (lnk = lnk.?.pNext) {
        // interested in finding the first LOADER_INSTANCE_CREATE_INFO member, where function == func
        if (lnk.?.sType != c.VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO)
            continue;

        const info: *c.VkLayerInstanceCreateInfo = @ptrCast(lnk.?);
        if (info.function == func)
            return info;
    }

    return null;
}

