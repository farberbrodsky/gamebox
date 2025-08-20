const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const WaitError = error{SignalError};

var g_allow_wait_for_exit = true;

/// This function does not work if you have a sigchld handler
pub fn waitForExit(child_pid: posix.pid_t) WaitError!u8 {
    std.debug.assert(g_allow_wait_for_exit);

    while (true) {
        // this handles EINTR internally
        const waitpid_out = posix.waitpid(@intCast(child_pid), 0);

        if (waitpid_out.pid != child_pid) {
            std.debug.print("waitpid error\n", .{});
            return error.SignalError;
        }

        if (posix.W.IFEXITED(waitpid_out.status)) {
            return posix.W.EXITSTATUS(waitpid_out.status);
        } else if (posix.W.IFSIGNALED(waitpid_out.status)) {
            return error.SignalError;
        }
        // otherwise: keep going
    }
}

/// An Eventfd is a form of inter-process communication that can be used to set a "go" flag to another process.
/// However, note that after a fork the Eventfd should be closed twice: both by the parent and by the child.
/// This is why both "wait" and "deinit" can close the file descriptor.
pub const FlagEventfd = struct {
    /// -1 if already waited for.
    fd: posix.fd_t,

    pub fn init() !FlagEventfd {
        const event_fd = try posix.eventfd(0, 0);
        return FlagEventfd{ .fd = event_fd };
    }

    pub fn deinit(self: *FlagEventfd) void {
        if (self.fd != -1) {
            posix.close(self.fd);
        }
    }

    pub fn wait(self: *FlagEventfd) void {
        std.debug.assert(self.fd != -1);
        var buf: [8]u8 = undefined;
        const read_res = posix.read(self.fd, &buf) catch std.debug.panic("eventfd error", .{});
        std.debug.assert(read_res == 8);
        posix.close(self.fd);
        self.fd = -1;
    }

    pub fn notify(self: *FlagEventfd) void {
        var buf: [8]u8 = undefined;
        (&buf).* = @bitCast(@as(u64, 1));
        const write_res = posix.write(self.fd, &buf) catch std.debug.panic("eventfd error", .{});
        std.debug.assert(write_res == 8);
    }
};

var g_echild_event_fd: ?*FlagEventfd = null;

fn sigchld_handler(_: i32) callconv(.c) void {
    while (true) {
        var wstatus: u32 = undefined;
        const rc: isize = @bitCast(linux.waitpid(-1, &wstatus, posix.W.NOHANG));
        if (rc < 0) {
            // try again
            if (-rc == @intFromEnum(linux.E.INTR))
                continue;
            // done
            if (-rc == @intFromEnum(linux.E.CHILD)) {
                // child can proceed.
                if (g_echild_event_fd) |*efd| {
                    // notify, and don't notify again
                    efd.*.notify();
                    g_echild_event_fd = null;
                }
                break;
            }

            // Other errors shouldn't happen
            std.debug.dumpCurrentStackTrace(null);
            return;
        }

        // all signals were handled
        if (rc == 0)
            break;

        // result is a child that got a signal. continue...
    }
}

/// Use this in pid 1 of the container
pub fn registerChildSignal(echild_event_fd: *FlagEventfd) !void {
    g_allow_wait_for_exit = false;
    g_echild_event_fd = echild_event_fd;
    posix.sigaction(posix.SIG.CHLD, &.{ .handler = .{ .handler = sigchld_handler }, .mask = posix.sigemptyset(), .flags = 0 }, null);
}
