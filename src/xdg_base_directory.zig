const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

var ruid: linux.uid_t = undefined;
var euid: linux.uid_t = undefined;
var rgid: linux.uid_t = undefined;
var egid: linux.uid_t = undefined;

/// Allocated variables are ALL required to exist in the end!
/// However, I would like to support deallocation in case of failure, and the yet-uninitialized state is represented by null.
var g = struct {
    pw_name: ?[]const u8 = null,
    pw_dir: ?[]const u8 = null,
    home_dir: ?[]const u8 = null,
    xdg_config_home: ?[]const u8 = null,
}{};

fn getMyUid() void {
    ruid = linux.getuid();
    euid = linux.geteuid();
    rgid = linux.getgid();
    egid = linux.getegid();
}

/// Must be called after getMyUid()
fn getMyPasswdEntry(allocator: std.mem.Allocator) !void {
    const passwd = std.c.getpwuid(ruid);
    if (passwd == null or passwd.?.pw_name == null or passwd.?.pw_dir == null) {
        return error.PasswdError;
    }

    // create copy of passwd.pw_name
    const unowned_pw_name = std.mem.span(passwd.?.pw_name.?);
    g.pw_name = try allocator.dupe(u8, unowned_pw_name);

    // create copy of passwd.pw_dir
    const unowned_pw_dir = std.mem.span(passwd.?.pw_dir.?);
    g.pw_dir = try allocator.dupe(u8, unowned_pw_dir);
}

/// Must be called after getMyPasswdEntry()
fn getHome(allocator: std.mem.Allocator) !void {
    const env_home = posix.getenv("HOME");
    if (env_home != null) {
        g.home_dir = try allocator.dupe(u8, env_home.?);
    } else {
        g.home_dir = try allocator.dupe(u8, g.pw_dir.?);
    }
}

/// Must be called after getHome()
fn getXdgConfigHome(allocator: std.mem.Allocator) !void {
    const env_xdg_config_home = posix.getenv("XDG_CONFIG_HOME");
    if (env_xdg_config_home != null) {
        g.xdg_config_home = try allocator.dupe(u8, env_xdg_config_home.?);
    } else {
        g.xdg_config_home = try std.fs.path.join(allocator, &[_][]const u8{g.home_dir.?, ".config"});
    }
}

pub fn init(allocator: std.mem.Allocator) !void {
    errdefer deinit(allocator);
    getMyUid();
    try getMyPasswdEntry(allocator);
    try getHome(allocator);
    try getXdgConfigHome(allocator);
}

/// Frees all non-null slices under g
pub fn deinit(allocator: std.mem.Allocator) void {
    inline for (std.meta.fields(@TypeOf(g))) |field| {
        if (@field(g, field.name)) |allocation| {
            allocator.free(allocation);
        }
    }
}

/// Generates an enum type based that chooses one of the fields of another type
fn StructFieldsType(comptime source_type: type) type {
    const fields = std.meta.fields(source_type);
    var enum_fields: [fields.len]std.builtin.Type.EnumField = undefined;

    inline for (0.., fields) |i, field| {
        enum_fields[i] = .{ .name = field.name, .value = i };
    }
    return @Type(.{
        .Enum = .{
            .tag_type = i32,
            .fields = &enum_fields,
            .decls = &[_]std.builtin.Type.Declaration {},
            .is_exhaustive = true,
        }
    });
}

/// Lifetime is the same as this system's.
pub fn get(comptime param: StructFieldsType(@TypeOf(g))) []const u8 {
    return @field(g, @tagName(param)).?;
}
