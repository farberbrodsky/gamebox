const std = @import("std");
const linux = std.os.linux;
const uidmap = @import("uidmap.zig");

const UidRanges = struct {
    allocator: std.mem.Allocator,
    uid: std.ArrayListUnmanaged(uidmap.NewuidRange),
    gid: std.ArrayListUnmanaged(uidmap.NewuidRange),

    pub fn deinit(self: *UidRanges) void {
        self.uid.deinit(self.allocator);
        self.gid.deinit(self.allocator);
    }
};

/// Chooses uid and gid ranges for our new process
pub fn makeUidRanges(allocator: std.mem.Allocator) !UidRanges {
    // Choose uid and gid ranges for new process
    const uid_range_list = try uidmap.getMyUidmaps(allocator, .User);
    defer uid_range_list.deinit();
    const gid_range_list = try uidmap.getMyUidmaps(allocator, .Group);
    defer gid_range_list.deinit();

    var newuid_range_list = std.ArrayListUnmanaged(uidmap.NewuidRange){};
    var newgid_range_list = std.ArrayListUnmanaged(uidmap.NewuidRange){};

    // Our uid maps to itself - for convenience
    const euid = linux.geteuid();
    try newuid_range_list.append(allocator, .{ .inner_id = euid, .outer_id = euid, .count = 1 });
    // Map 0 until min(our uid, allocated count)
    if (uid_range_list.items.len >= 1) {
        const outer_id = uid_range_list.items[0].start_id;
        const count = @min(uid_range_list.items[0].count, euid -% 1);
        if (count != 0) {
            try newuid_range_list.append(allocator, .{ .inner_id = 0, .outer_id = outer_id, .count = count });
        }
    }

    // Our gid maps to itself - for convenience
    const egid = linux.geteuid();
    try newgid_range_list.append(allocator, .{ .inner_id = egid, .outer_id = egid, .count = 1 });
    // Map 0 until min(our gid, allocated count)
    if (gid_range_list.items.len >= 1) {
        const outer_id = gid_range_list.items[0].start_id;
        const count = @min(gid_range_list.items[0].count, egid -% 1);
        if (count != 0) {
            try newgid_range_list.append(allocator, .{ .inner_id = 0, .outer_id = outer_id, .count = count });
        }
    }

    return .{ .allocator = allocator, .uid = newuid_range_list, .gid = newgid_range_list };
}
