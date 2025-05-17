const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const WaitError = error{SignalError};

pub fn wait_for_exit(child_pid: posix.pid_t) WaitError!u8 {
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
