const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const xdg_base_directory = @import("xdg_base_directory.zig");

pub const NewuidRange = struct {
    inner_id: posix.uid_t,
    outer_id: posix.uid_t,
    count: posix.uid_t,
};

const Config = struct {
    base_image: [:0]const u8,
    overlay_upper: [:0]const u8,
    overlay_work: [:0]const u8,
    uid_mappings: []NewuidRange,
    gid_mappings: []NewuidRange,
};

var parsed_configuration: std.json.Parsed(Config) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    try xdg_base_directory.init(allocator);
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ xdg_base_directory.get(.xdg_config_home), "gamebox/config.json" });
    const config_dir = std.fs.path.dirname(config_path) orelse return error.PathError;

    try std.fs.Dir.makePath(std.fs.cwd(), config_dir);

    var file = try std.fs.createFileAbsolute(config_path, .{ .read = true, .truncate = false });
    const file_size = try file.getEndPos();
    if (file_size == 0) {
        // Create a new config
        // TODO: what should the default config be?
        std.debug.print("Please create a new config yourself. Loser.\n", .{});
        std.debug.print("Example command: unshare --user --map-users=0:100000:1 --map-users=1000:1000:1 --setuid 0 --map-groups=0:100000:1 --map-groups=1000:1000:1 --setgid 0.\n", .{});
        std.debug.print("Then, tar -xvf to your alpine image or whatever.\n", .{});
        return error.LoserError;
    } else {
        var read_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(&read_buffer);
        var token_reader = std.json.Reader.init(allocator, &file_reader.interface);
        parsed_configuration = try std.json.parseFromTokenSource(Config, allocator, &token_reader, .{});
    }
}

pub fn deinit(allocator: std.mem.Allocator) void {
    parsed_configuration.deinit();
    xdg_base_directory.deinit(allocator);
}

pub fn getBaseImagePath() [:0]const u8 {
    return parsed_configuration.value.base_image;
}

pub fn getOverlayUpper() [:0]const u8 {
    return parsed_configuration.value.overlay_upper;
}

pub fn getOverlayWork() [:0]const u8 {
    return parsed_configuration.value.overlay_work;
}

pub fn getUidMappings() []const NewuidRange {
    return parsed_configuration.value.uid_mappings;
}

pub fn getGidMappings() []const NewuidRange {
    return parsed_configuration.value.gid_mappings;
}
