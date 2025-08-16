const std = @import("std");
const testing = std.testing;
const vk = @import("vk_headers");
const so = @import("so.zig");
const wrappers = @import("vk_wrappers");

const FunctionPair = struct { []const u8, vk.c.PFN_vkVoidFunction };

// Combine auto-generated wrappers with our special functions
fn overrideStaticMap(comptime overrides: []const FunctionPair, comptime base: []const FunctionPair) std.StaticStringMap(vk.c.PFN_vkVoidFunction) {
    var combined = std.mem.zeroes([base.len + overrides.len]FunctionPair);
    var used = std.mem.zeroes([overrides.len]bool);
    for (0.., base) |i, base_pair| {
        const value = for (0.., overrides) |override_i, override_pair| {
            if (std.mem.eql(u8, base_pair[0], override_pair[0])) {
                used[override_i] = true;
                break override_pair[1];
            }
        } else base_pair[1];
        combined[i] = .{ base_pair[0], value };
    }

    var combined_len = base.len;
    for (0.., used) |override_i, is_used| {
        if (!is_used) {
            combined[combined_len] = overrides[override_i];
            combined_len += 1;
        }
    }
    return std.StaticStringMap(vk.c.PFN_vkVoidFunction).initComptime(combined[0..combined_len]);
}

pub const InstanceFunctions = overrideStaticMap(&[_]FunctionPair{
    .{ "vkCreateInstance", @ptrCast(&so.VK_LAYER_GAMEBOX_persist_CreateInstance) },
    .{ "vkCreateDevice", @ptrCast(&so.VK_LAYER_GAMEBOX_persist_CreateDevice) },
    .{ "vkEnumeratePhysicalDevices", @ptrCast(&so.EnumeratePhysicalDevices) },
}, &wrappers.InstanceFunctions);

pub const DeviceFunctions = std.StaticStringMap(vk.c.PFN_vkVoidFunction).initComptime([_]FunctionPair{});
