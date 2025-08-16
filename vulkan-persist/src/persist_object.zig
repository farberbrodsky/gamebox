const std = @import("std");

const PersistObjectType = enum {
    CreateDevice,
};

// This struct represents a Vulkan object that can be persisted. It contains a pointer to the
// underlying object, the object type, and a "creation packet" that contains the information
// needed to recreate the object.
const PersistObject = struct {
    const Self = @This();

    /// Membership of a doubly linked list, ordering objects chronologically
    /// in some order consistent with threading happens-before boundaries.
    list_node: std.DoublyLinkedList.Node,

    /// A PersistObject represents some underlying object at runtime
    underlying_pointer: usize,

    /// Type of the object when created
    type: PersistObjectType,

    /// An optional creation data packet stored in the same allocation
    creation_packet_size: usize = 0,

    pub fn creation_packet(self: *Self) []u8 {
        const base: [*]u8 = @ptrCast(self);
        const offset = comptime @sizeOf(Self);
        return base[offset .. offset + self.creation_packet_size];
    }
};
