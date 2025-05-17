const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const uidmap = @import("uidmap.zig");
const procutil = @import("procutil.zig");

fn do_namespaced_child(fd: i32) !void {
    var buf: [8]u8 = undefined;

    // wait for newuidmap
    // no error handling because it's an eventfd
    _ = linux.read(@intCast(fd), &buf, 8);

    std.debug.print("I am a child! {d}\n", .{linux.getuid()});
    try posix.setuid(0);
    std.debug.print("I am a child yet again! {d}\n", .{linux.getuid()});
    const argv = [_:null]?[*:0]const u8{ "/bin/sh", null };
    const envp = [_:null]?[*:0]const u8{null};
    return posix.execvpeZ("/bin/sh", &argv, &envp);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // Choose uid and gid ranges for new process
    const uid_range_list = try uidmap.getMyUidmaps(allocator, .User);
    defer uid_range_list.deinit();
    const gid_range_list = try uidmap.getMyUidmaps(allocator, .Group);
    defer gid_range_list.deinit();

    var newuid_range_list = std.ArrayList(uidmap.NewuidRange).init(allocator);
    defer newuid_range_list.deinit();
    var newgid_range_list = std.ArrayList(uidmap.NewuidRange).init(allocator);
    defer newgid_range_list.deinit();

    // Our uid maps to itself - for convenience
    const euid = linux.geteuid();
    try newuid_range_list.append(.{ .inner_id = euid, .outer_id = euid, .count = 1 });
    // Map 0 until min(our uid, allocated count)
    if (uid_range_list.items.len == 1) {
        const outer_id = uid_range_list.items[0].start_id;
        const count = @min(uid_range_list.items[0].count, euid -% 1);
        try newuid_range_list.append(.{ .inner_id = 0, .outer_id = outer_id, .count = count });
    }

    // Our gid maps to itself - for convenience
    const egid = linux.geteuid();
    try newgid_range_list.append(.{ .inner_id = egid, .outer_id = egid, .count = 1 });

    // Create file descriptor to notify child when uid mapping is complete
    const event_fd = try posix.eventfd(0, 0);

    // clone with the same stack, signal SIGCHLD, and new user namespace
    var ptid: i32 = undefined;
    var ctid: i32 = undefined;
    const child_pid: isize = @bitCast(linux.clone5(linux.CLONE.NEWUSER | linux.SIG.CHLD, 0, &ptid, &ctid, 0));

    if (child_pid == 0) {
        // am child
        do_namespaced_child(event_fd) catch |err| {
            std.debug.print("{}", .{err});
        };
        // shouldn't have returned!!
        linux.exit(1);
        unreachable;
    } else if (child_pid < 0) {
        // am erroring out
        std.debug.print("child pid {d}\n", .{child_pid});
        return error.PastenError;
    }

    // am parent
    std.debug.print("child {d}\n", .{child_pid});

    // Call newuidmap
    try uidmap.forkingApplyUidmaps(allocator, @intCast(child_pid), newuid_range_list.items, .User);
    try uidmap.forkingApplyUidmaps(allocator, @intCast(child_pid), newgid_range_list.items, .Group);

    // Resume child
    var buf: [8]u8 = undefined;
    (&buf).* = @bitCast(@as(u64, 1));
    const write_res = linux.write(@intCast(event_fd), &buf, buf.len);
    if (write_res != 8) return error.LinuxError;
    // done!
    // linux.exit(0);
    linux.exit(try procutil.wait_for_exit(@intCast(child_pid)));
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test {
    std.testing.refAllDecls(@This());
}
