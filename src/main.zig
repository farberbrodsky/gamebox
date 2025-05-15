const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const STACK_SIZE = 1024 * 1024;

fn wait_for_exit(child_pid: linux.pid_t) !u8 {
    var wstatus: u32 = undefined;
    while (true) {
        const waitpid_out = linux.waitpid(@intCast(child_pid), &wstatus, 0);
        if (waitpid_out != child_pid) {
            std.debug.print("waitpid error\n", .{});
            linux.exit(1);
        }

        if (linux.W.IFEXITED(wstatus) or linux.W.IFSIGNALED(wstatus))
            break;
    }

    if (linux.W.IFEXITED(wstatus))
        return linux.W.EXITSTATUS(wstatus)
    else
        return error.SignalError;
}

pub fn evil_twin(fd: usize) callconv(.C) u8 {
    var buf: [8]u8 = undefined;

    // wait for newuidmap
    _ = linux.read(@intCast(fd), &buf, 8);

    std.debug.print("I am a child! {d}\n", .{linux.getuid()});
    _ = linux.setuid(0);
    std.debug.print("I am a child yet again! {d}\n", .{linux.getuid()});
    const aaaa_fd = linux.open("/tmp/aaaa", .{ .ACCMODE = .WRONLY, .CREAT = true }, 0o777);
    _ = linux.close(@intCast(aaaa_fd));
    return 3;
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    const stack_ptr = linux.mmap(null, STACK_SIZE, linux.PROT.READ | linux.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .STACK = true }, -1, 0);
    if (stack_ptr == std.math.maxInt(@TypeOf(stack_ptr))) {
        std.debug.print("stack mmap failure", .{});
        return error.OutOfMemory;
    }

    std.debug.print("mmap result {x}\n", .{stack_ptr});

    const stack_top = stack_ptr + STACK_SIZE;
    // clone with a new stack, signal SIGCHLD, and new UTS namespace
    var ptid: i32 = undefined;
    var ctid: i32 = undefined;
    const event_fd = linux.eventfd(0, 0);
    const child_pid: isize = @bitCast(linux.clone(evil_twin, stack_top, linux.CLONE.NEWUSER | linux.SIG.CHLD, event_fd, &ptid, 0, &ctid));
    if (child_pid < 0) {
        std.debug.print("child pid {d}\n", .{child_pid});
        return error.PastenError;
    }

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
