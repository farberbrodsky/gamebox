const std = @import("std");
const linux = std.os.linux;
const c = @cImport({
    @cInclude("string.h");
});

const STACK_SIZE = 1024 * 1024;

pub fn evil_twin(arg: usize) callconv(.C) u8 {
    _ = arg;
    std.debug.print("I am a child!\n", .{});
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
    const child_pid: isize = @bitCast(linux.clone(evil_twin, stack_top, linux.CLONE.NEWUTS | linux.SIG.CHLD, 0, &ptid, 0, &ctid));
    if (child_pid < 0) {
        std.debug.print("child pid {d}\n", .{child_pid});
        const st = c.strerror(@intCast(-child_pid));
        std.debug.print("child str {s}\n", .{st});
        return error.PastenError;
    }

    std.debug.print("child {d}\n", .{child_pid});

    var wstatus: u32 = undefined;
    while (true) {
        const waitpid_out = linux.waitpid(@intCast(child_pid), &wstatus, 0);
        if (waitpid_out != child_pid)
            return error.PastenError;

        if (linux.W.IFEXITED(wstatus) or linux.W.IFSIGNALED(wstatus))
            break;
    }

    std.debug.print("No, I am your father.\n", .{});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
