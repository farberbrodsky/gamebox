const State = @This();
const std = @import("std");
const vk = @import("vkheaders.zig");

header: struct {
    /// This state is relevant only if the instance matches
    instance: vk.Instance = null,

    /// There is a next pointer if you need to look at the next state object. It is a lock-free (for readers) singly linked list.
    /// We are assuming that the common case is only a single Vulkan instance.
    next: std.atomic.Value(?*State) = std.atomic.Value(?*State).init(null),
} = .{},

/// The following fields are taken from the instance
instance_info: struct {
    /// The allocator in here was used to allocate this state object, too! Except for the first one, which is optimized.
    allocator: *const vk.Allocator = undefined,

    /// This is the vkGetInstanceProcAddr implementation of the following layer
    pfnGetInstanceProcAddr: vk.c.PFN_vkGetInstanceProcAddr = undefined,
} = .{},

/// Finds the State object for a given instance, given a pointer to the first State object.
pub fn find(first: *State, instance: vk.Instance) ?*State {
    var link: ?*State = first;
    return while (link) |state| : (link = state.header.next.load(.acquire)) {
        if (state.header.instance == instance)
            break state;
    } else null;
}

/// Creates a new State object, either from this one (assumed to be the first) or by using its allocator
/// May fail to allocate, and then return null.
pub fn append(first: *State, instance: vk.Instance, instance_info: @TypeOf(first.instance_info), lock: *std.Thread.Mutex) ?*State {
    // writes happen under a lock
    lock.lock();
    defer lock.unlock();

    // Using the instance's allocator for the instance's State object
    const alloc = instance_info.allocator.allocator();

    // Either take the first entry, or create a new one
    const new_state = if (first.header.instance == null)
        first
    else
        alloc.create(State) catch return null;

    // Put data into this entry
    new_state.header.instance = instance;
    new_state.instance_info = instance_info;

    // Store into the linked list, unless it's the first entry
    if (new_state != first) {
        var link = first;

        // Advance until the end of the list
        while (true) {
            const next = link.header.next.load(.unordered);
            if (next) |l| {
                link = l;
            } else {
                break;
            }
        }

        link.header.next.store(new_state, .release);
    }

    return new_state;
}
