const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub fn mount(special: [*:0]const u8, dir: [*:0]const u8, fstype: ?[*:0]const u8, flags: u32, data: usize) !void {
    const rc: isize = @bitCast(linux.mount(special, dir, fstype, flags, data));
    if (rc < 0) {
        return posix.unexpectedErrno(@enumFromInt(-rc));
    }
}

pub fn chroot(path: [*:0]const u8) !void {
    const rc: isize = @bitCast(linux.chroot(path));
    if (rc < 0) {
        return posix.unexpectedErrno(@enumFromInt(-rc));
    }
}
