const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

fn wait_for_exit(child_pid: posix.pid_t) error{SignalError}!u8 {
    while (true) {
        // this handles EINTR internally
        const waitpid_out = posix.waitpid(@intCast(child_pid), 0);

        if (waitpid_out.pid != child_pid) {
            std.debug.print("waitpid error\n", .{});
            posix.exit(1);
        }

        if (posix.W.IFEXITED(waitpid_out.status)) {
            return posix.W.EXITSTATUS(waitpid_out.status);
        } else if (posix.W.IFSIGNALED(waitpid_out.status)) {
            return error.SignalError;
        }
        // otherwise: keep going
    }
}

fn do_namespaced_child(fd: i32) noreturn {
    var buf: [8]u8 = undefined;

    // wait for newuidmap
    // no error handling because it's an eventfd
    _ = linux.read(@intCast(fd), &buf, 8);

    std.debug.print("I am a child! {d}\n", .{linux.getuid()});
    _ = linux.setuid(0);
    std.debug.print("I am a child yet again! {d}\n", .{linux.getuid()});
    const aaaa_fd = linux.open("/tmp/aaaa", .{ .ACCMODE = .WRONLY, .CREAT = true }, 0o777);
    posix.close(@intCast(aaaa_fd));
    posix.exit(0);
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    const event_fd = try posix.eventfd(0, 0);

    // clone with the same stack, signal SIGCHLD, and new user namespace
    var ptid: i32 = undefined;
    var ctid: i32 = undefined;
    const child_pid: isize = @bitCast(linux.clone5(linux.CLONE.NEWUSER | linux.SIG.CHLD, 0, &ptid, &ctid, 0));

    if (child_pid == 0) {
        // am child
        do_namespaced_child(event_fd);
    } else if (child_pid < 0) {
        // am erroring out
        std.debug.print("child pid {d}\n", .{child_pid});
        return error.PastenError;
    }

    // am parent
    std.debug.print("child {d}\n", .{child_pid});

    // Call newuidmap
    const fork_pid: isize = @bitCast(linux.fork());
    if (fork_pid == 0) {
        const my_loweruid = 100000;
        const my_count = 128;

        var buffer: [128]u8 = undefined;
        var args_allocator = std.heap.FixedBufferAllocator.init(&buffer);

        const pid_str = std.fmt.allocPrintZ(args_allocator.allocator(), "{d}", .{child_pid}) catch linux.exit(1);
        const loweruid_str = std.fmt.allocPrintZ(args_allocator.allocator(), "{d}", .{my_loweruid}) catch linux.exit(1);
        const count_str = std.fmt.allocPrintZ(args_allocator.allocator(), "{d}", .{my_count}) catch linux.exit(1);

        const arr: [6:null]?[*:0]const u8 = .{ "newuidmap", pid_str, "0", loweruid_str, count_str, null };
        const env: [1:null]?[*:0]const u8 = .{null};

        posix.execvpeZ("newuidmap", &arr, &env) catch linux.exit(1);
        linux.exit(1);
    } else if (fork_pid < 0) {
        return error.ForkError;
    }

    // Wait for it to finish
    const exit_status = try wait_for_exit(@intCast(fork_pid));
    if (exit_status != 0) return error.PastenError;
    // Resume child
    var buf: [8]u8 = undefined;
    (&buf).* = @bitCast(@as(u64, 1));
    const write_res = linux.write(@intCast(event_fd), &buf, buf.len);
    if (write_res != 8) return error.PastenError;
    // done!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
