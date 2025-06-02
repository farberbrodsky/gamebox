const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const binux = @import("../binux.zig");
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

const OLD_ROOT_POINT = ".oldroot";

pub fn setupMounts(allocator: std.mem.Allocator) !void {
    const image_path = configuration.getBaseImagePath();
    const overlay_upper = configuration.getOverlayUpper();
    const overlay_work = configuration.getOverlayWork();

    // Unshare mount updates from the parent
    try binux.mount("", "/", null, linux.MS.PRIVATE | linux.MS.REC, 0);

    // Mount an overlayfs instead of the image.
    // Even if we didn't do this, the new root path has to be a different mount point for pivot_root to work!
    const overlay_params = .{ image_path, overlay_upper, overlay_work };
    const overlay_params_str = try std.fmt.allocPrintZ(allocator, "lowerdir={s},upperdir={s},workdir={s}", overlay_params);
    defer allocator.free(overlay_params_str);
    binux.mount("overlay", image_path, "overlay", 0, @intFromPtr(@as([*:0]const u8, overlay_params_str))) catch |err| switch (err) {
        error.FileNotFound => {
            return error.OverlayFileNotFound;
        },
        else => return error.OverlayError,
    };

    // Enter image_path as the root, and keep the old root under /.oldroot
    try posix.chdirZ(image_path);
    binux.pivot_root(".", OLD_ROOT_POINT) catch |err| switch (err) {
        error.FileNotFound => {
            // try to recover by making the directory
            try posix.mkdirZ(OLD_ROOT_POINT, 0o777);
            try binux.pivot_root(".", OLD_ROOT_POINT);
        },
        else => return err,
    };

    // add procfs and friends
    try binux.mount("porkfs", "/proc", "proc", 0, 0);
    try setupDevFile("null");
    try setupDevFile("zero");

    // detach oldroot
    try binux.umount2(OLD_ROOT_POINT, linux.MNT.DETACH);
}

/// Helper for setupMounts
fn setupDevFile(comptime device_name: [:0]const u8) !void {
    const dst_path = "/dev/" ++ device_name;
    const src_path = "/" ++ OLD_ROOT_POINT ++ dst_path;

    binux.mount(src_path, dst_path, null, linux.MS.BIND, 0) catch |err| switch (err) {
        error.FileNotFound => {
            // try to recover by making the file
            const fd = try posix.openZ(dst_path, .{ .CREAT = true }, 0);
            posix.close(fd);
            try binux.mount(src_path, dst_path, null, linux.MS.BIND, 0);
        },
        else => return err,
    };
}
