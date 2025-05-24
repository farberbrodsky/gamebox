const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const uidmap = @import("setup/uidmap.zig");
const procutil = @import("procutil.zig");
const ns = @import("setup/namespace_helpers.zig");
const xdg_base_directory = @import("setup/xdg_base_directory.zig");
const configuration = @import("setup/configuration.zig");

fn do_namespaced_child(allocator: std.mem.Allocator, uidmap_ready: *procutil.FlagEventfd) !void {
    // wait for newuidmap
    uidmap_ready.wait();

    // become root among the foxes
    try posix.seteuid(0);
    try posix.setuid(0);
    try posix.setegid(0);
    try posix.setgid(0);

    // create mounts
    try ns.setupMounts(allocator);

    // register sigchld handler
    // We would like to know when all of the children have died.
    var echild_event = try procutil.FlagEventfd.init();
    defer echild_event.deinit();
    try procutil.registerChildSignal(&echild_event);

    const fork_pid = try posix.fork();
    if (fork_pid == 0) {
        // Execute /bin/sh
        const argv = [_:null]?[*:0]const u8{ "/bin/sh", null };
        const envp = [_:null]?[*:0]const u8{ "PATH=/bin", null };
        posix.execveZ("/bin/sh", &argv, &envp) catch linux.exit(1);
        // should not have returned!
        linux.exit(1);
    }

    // wait for all children to exit
    echild_event.wait();
    std.debug.print("The children all died successfuly\n", .{});
    linux.exit(0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Load configuration
    try configuration.init(allocator);
    defer configuration.deinit(allocator);

    // Create file descriptor to notify child when uid mapping is complete
    var uidmap_ready = try procutil.FlagEventfd.init();
    defer uidmap_ready.deinit();

    // clone with the same stack, signal SIGCHLD, and new user namespace
    var ptid: i32 = undefined;
    var ctid: i32 = undefined;
    const child_pid: isize = @bitCast(linux.clone5(linux.CLONE.NEWUSER | linux.CLONE.NEWNS | linux.CLONE.NEWPID | linux.SIG.CHLD, 0, &ptid, &ctid, 0));

    if (child_pid == 0) {
        // am child
        do_namespaced_child(allocator, &uidmap_ready) catch |err| {
            std.debug.print("{}", .{err});
        };
        // shouldn't have returned!!
        linux.exit(1);
    } else if (child_pid < 0) {
        // am erroring out
        std.debug.print("child pid {d}\n", .{child_pid});
        return error.ForkError;
    }

    // am parent
    std.debug.print("child {d}\n", .{child_pid});

    // Call newuidmap
    try uidmap.forkingApplyUidmaps(allocator, @intCast(child_pid), configuration.getUidMappings(), .User);
    try uidmap.forkingApplyUidmaps(allocator, @intCast(child_pid), configuration.getGidMappings(), .Group);

    // Resume child
    uidmap_ready.notify();
    // done!
    linux.exit(try procutil.waitForExit(@intCast(child_pid)));
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
