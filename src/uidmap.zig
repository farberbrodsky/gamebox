const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const expect = std.testing.expect;
const procutil = @import("procutil.zig");

pub const SubuidRange = struct {
    start_id: posix.uid_t,
    count: posix.uid_t,
};

pub const NewuidRange = struct {
    inner_id: posix.uid_t,
    outer_id: posix.uid_t,
    count: posix.uid_t,
};

pub const UserOrGroup = enum { User, Group };

/// Internal parsing method for parsing subuid ranges in the format {name/uid}:start_id:count.
fn parseIdmapsFile(allocator: std.mem.Allocator, reader: anytype, my_uid: u32, my_name: []const u8) !std.ArrayList(SubuidRange) {
    // Result object
    var result = std.ArrayList(SubuidRange).init(allocator);
    errdefer result.deinit();

    // Format my_uid to be able to match it
    var uid_buffer: [32]u8 = undefined;
    const uid_str = std.fmt.bufPrintZ(&uid_buffer, "{d}", .{my_uid}) catch unreachable;

    const column_buffer = try allocator.alloc(u8, @max(uid_buffer.len, my_name.len) + 1);
    defer allocator.free(column_buffer);

    line_loop: while (true) {
        const user_name_or_id = reader.readUntilDelimiter(column_buffer, ':') catch |err| switch (err) {
            error.StreamTooLong => "", // if too long, use an empty value
            error.EndOfStream => break :line_loop,
            else => return err,
        };

        if (!std.mem.eql(u8, user_name_or_id, my_name) and !std.mem.eql(u8, user_name_or_id, uid_str)) {
            // line is irrelevant
            try reader.skipUntilDelimiterOrEof('\n');
            continue :line_loop;
        }

        // parse the rest of it
        const subuser_id_buffer = try reader.readUntilDelimiter(column_buffer, ':');
        const subuser_id = try std.fmt.parseInt(posix.uid_t, subuser_id_buffer, 10);
        const subuser_count_buffer = try reader.readUntilDelimiterOrEof(column_buffer, '\n') orelse "";
        const subuser_count = try std.fmt.parseInt(posix.uid_t, subuser_count_buffer, 10);

        try result.append(.{ .start_id = subuser_id, .count = subuser_count });
    }

    // return successful result
    return result;
}

/// Parses either /etc/subuid or /etc/subgid, looking for entries relevant to the running user's UID and name.
fn getIdmapsFromFile(allocator: std.mem.Allocator, path: [*:0]const u8) !std.ArrayList(SubuidRange) {
    // Get my euid, and name from /etc/passwd
    const my_uid = linux.geteuid();
    const my_pw = std.c.getpwuid(my_uid) orelse return error.UserError;
    const my_name: [*:0]const u8 = my_pw.pw_name orelse return error.UserError;

    const file = try std.fs.cwd().openFileZ(path, .{});
    defer file.close();
    var buf = std.io.bufferedReader(file.reader());
    var r = buf.reader();

    // Parse based on the reader, uid and name.
    return parseIdmapsFile(allocator, &r, my_uid, std.mem.span(my_name));
}

pub fn getUidmaps(allocator: std.mem.Allocator) !std.ArrayList(SubuidRange) {
    return getIdmapsFromFile(allocator, "/etc/subuid");
}

pub fn getGidmaps(allocator: std.mem.Allocator) !std.ArrayList(SubuidRange) {
    return getIdmapsFromFile(allocator, "/etc/subgid");
}

const PreparedCommand = struct {
    arena: std.heap.ArenaAllocator,
    exec: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
};

const NULL_ENVP = [_:null]?[*:0]const u8{null};

/// Calls either newuidmap or newgidmap
fn prepareApplyUidmaps(parent_allocator: std.mem.Allocator, pid: posix.pid_t, ranges: []const NewuidRange, user_or_group: UserOrGroup) std.mem.Allocator.Error!PreparedCommand {
    const exec = switch (user_or_group) {
        .User => "newuidmap",
        .Group => "newgidmap",
    };

    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    // allocate argv array under the arena
    // argv is: exec_name, pid, [inner_id outer_id count]*, null
    const argv = try allocator.alloc(?[*:0]const u8, 3 + 3 * ranges.len);

    argv[0] = exec;
    argv[1] = try std.fmt.allocPrintZ(allocator, "{d}", .{pid});
    for (0.., ranges) |i, range| {
        argv[2 + 3 * i + 0] = try std.fmt.allocPrintZ(allocator, "{d}", .{range.inner_id});
        argv[2 + 3 * i + 1] = try std.fmt.allocPrintZ(allocator, "{d}", .{range.outer_id});
        argv[2 + 3 * i + 2] = try std.fmt.allocPrintZ(allocator, "{d}", .{range.count});
    }
    argv[2 + 3 * ranges.len] = null;

    return .{ .arena = arena, .exec = exec, .argv = @ptrCast(argv), .envp = &NULL_ENVP };
}

pub fn forkingApplyUidmaps(parent_allocator: std.mem.Allocator, pid: posix.pid_t, ranges: []const NewuidRange, user_or_group: UserOrGroup) !void {
    const prepare = try prepareApplyUidmaps(parent_allocator, pid, ranges, user_or_group);

    const fork_pid = try posix.fork();
    if (fork_pid == 0) {
        // am child. execve, quick, in and out...
        _ = posix.execvpeZ(prepare.exec, prepare.argv, prepare.envp) catch null;
        linux.exit(1);
        unreachable;
    }
    prepare.arena.deinit();
    const exit_code = try procutil.waitForExit(fork_pid);
    if (exit_code != 0) {
        return error.UidmapError;
    }
}

test "parse uidmap test" {
    const buffer = "user:100000:65536\nuserust:123:456\nabc:900:1\n1000:1007:1\nuser:3141:592";
    var stream = std.io.fixedBufferStream(buffer);
    var reader = stream.reader();
    const out_list = try parseIdmapsFile(std.testing.allocator, &reader, 1000, "user");
    try expect(out_list.items.len == 3);
    try std.testing.expectEqual(out_list.items[0], SubuidRange{ .start_id = 100000, .count = 65536 });
    try std.testing.expectEqual(out_list.items[1], SubuidRange{ .start_id = 1007, .count = 1 });
    try std.testing.expectEqual(out_list.items[2], SubuidRange{ .start_id = 3141, .count = 592 });
    out_list.deinit();
}

test "apply uidmap test" {
    const ranges = [_]NewuidRange{ .{ .inner_id = 1, .outer_id = 2, .count = 3 }, .{ .inner_id = 4, .outer_id = 5, .count = 6 } };
    const prepared_command = try prepareApplyUidmaps(std.testing.allocator, 1000, &ranges, .User);
    defer prepared_command.arena.deinit();

    // compare exec name
    try expect(std.mem.eql(u8, std.mem.span(prepared_command.exec), "newuidmap"));

    // concatenate argv to a single string, to be able to check it
    var argv_fmt_list = std.ArrayList(u8).init(std.testing.allocator);
    defer argv_fmt_list.deinit();
    var argv_writer = argv_fmt_list.writer();

    for (std.mem.span(prepared_command.argv)) |arg| {
        try argv_writer.writeAll(std.mem.span(arg orelse ""));
        try argv_writer.writeByte(' ');
    }

    try expect(std.mem.eql(u8, argv_fmt_list.items, "newuidmap 1000 1 2 3 4 5 6 "));
}
