const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const binux = @import("binux.zig");
const uidmap = @import("uidmap.zig");
const configuration = @import("configuration.zig");

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
    const uid_range_list = try uidmap.getUidmaps(allocator);
    defer uid_range_list.deinit();
    const gid_range_list = try uidmap.getGidmaps(allocator);
    defer gid_range_list.deinit();

    var newuid_range_list = std.ArrayListUnmanaged(uidmap.NewuidRange){};
    var newgid_range_list = std.ArrayListUnmanaged(uidmap.NewuidRange){};

    // Our uid maps to itself - for convenience
    const euid = linux.geteuid();
    try newuid_range_list.append(allocator, .{ .inner_id = euid, .outer_id = euid, .count = 1 });
    // Map uid 0
    if (uid_range_list.items.len >= 1) {
        const outer_id = uid_range_list.items[0].start_id;
        if (outer_id == euid or uid_range_list.items[0].count < 1)
            return error.SubuidError;
        try newuid_range_list.append(allocator, .{ .inner_id = 0, .outer_id = outer_id, .count = 1 });
    } else {
        // we want a mapping for uid 0
        return error.SubuidError;
    }

    // Our gid maps to itself - for convenience
    const egid = linux.getegid();
    try newgid_range_list.append(allocator, .{ .inner_id = egid, .outer_id = egid, .count = 1 });

    // Map gid 0
    if (gid_range_list.items.len >= 1) {
        const outer_id = gid_range_list.items[0].start_id;
        if (outer_id == euid or gid_range_list.items[0].count < 1)
            return error.SubuidError;
        try newgid_range_list.append(allocator, .{ .inner_id = 0, .outer_id = outer_id, .count = 1 });
    } else {
        // we want a mapping for uid 0
        return error.SubuidError;
    }

    return .{ .allocator = allocator, .uid = newuid_range_list, .gid = newgid_range_list };
}

pub fn setupMounts(allocator: std.mem.Allocator) !void {
    // We need mount points to already exist.
    const OVERLAY_LOWER = "/tmp";
    const OVERLAY_MOUNT_AT = "/usr";

    // Unshare mount updates from the parent
    try binux.mount("", "/", null, linux.MS.PRIVATE | linux.MS.REC, 0);

    // Create a new mount which will be /
    try binux.mount(configuration.getBaseImagePath(), OVERLAY_LOWER, null, linux.MS.BIND, 0);
    // Convert it to read only
    try binux.mount(OVERLAY_LOWER, OVERLAY_LOWER, null, linux.MS.BIND | linux.MS.REMOUNT | linux.MS.RDONLY, 0);

    // Create an overlayfs: lowerdir, upperdir, workdir
    const overlay_params = .{ OVERLAY_LOWER, configuration.getOverlayUpper(), configuration.getOverlayWork() };
    const overlay_params_str = try std.fmt.allocPrintZ(allocator, "lowerdir={s},upperdir={s},workdir={s}", overlay_params);
    defer allocator.free(overlay_params_str);

    try binux.mount("overlay", OVERLAY_MOUNT_AT, "overlay", 0, @intFromPtr(@as([*:0]const u8, overlay_params_str)));
    // This is the new root! All hail the new root.
    try binux.chroot(OVERLAY_MOUNT_AT);
    try posix.chdir("/");

    // add procfs and friends
    try binux.mount("porkfs", "/proc", "proc", 0, 0);
}
