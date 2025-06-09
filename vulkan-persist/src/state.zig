const State = @This();
const std = @import("std");
const vk = @import("vkheaders.zig");

header: struct {
    /// This state is relevant only if the instance matches
    /// The real instance can't be null, but null can be used as a placeholder value if the first instance was destroyed.
    instance: vk.Instance = null,

    /// There is a next pointer if you need to look at the next state object. It is a lock-free (for readers) singly linked list.
    /// We are assuming that the common case is only a single Vulkan instance, but otherwise you need to traverse a linked list.
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
    std.debug.assert(instance != null);
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
    // NOTE: If next is already non-null for the first entry, keep it that way!
    //       And if it's a new entry, then next is already set to null.
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

pub fn destroy(first: *State, instance: vk.Instance, lock: *std.Thread.Mutex) void {
    // writes happen under a lock
    lock.lock();
    defer lock.unlock();

    if (first.header.instance == instance) {
        // The only solution is to assign null to instance. We can't free the object.
        first.header.instance = null;
        return;
    } else {
        // Find the state object before the one we are removing
        var link: ?*State = first;
        var next: ?*State = undefined;
        while (link) {
            next = link.header.next.load(.unordered);
            if (next.header.instance == instance)
                break;
            link = next;
        }

        if (link == null) {
            // instance should be known to us
            std.debug.panic("Instance being destroyed does not appear in any records\n", .{});
            return;
        } else |prev| {
            // Unlink the destroyed entry
            const destroyed = next.?;
            prev.header.next = destroyed.header.next;
            // Destroy it with its own allocator
            const alloc = destroyed.instance_info.allocator.allocator();
            alloc.destroy(destroyed);
        }
    }
}
