/// Most of the definitions come straight from the headers, but we have some additional wrappers to make things nicer.
pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vk_layer.h");
});

pub const Instance = c.VkInstance;
pub const Device = c.VkDevice;

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

