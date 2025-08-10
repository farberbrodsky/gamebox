const std = @import("std");
const xml = @import("xml");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 3) fatal("wrong number of arguments", .{});

    const input_file_path = args[1];
    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        fatal("unable to open input '{s}': {s}", .{ input_file_path, @errorName(err) });
    };
    defer input_file.close();

    // For usage, see: https://github.com/ianprime0509/zig-xml/blob/c12dbb48606f716773a1ddf7d9b14e07524d1436/examples/reader.zig
    var xmlDoc = xml.streamingDocument(arena, input_file.reader());
    defer xmlDoc.deinit();
    var xmlReader = xmlDoc.reader(arena, .{});
    defer xmlReader.deinit();

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open output '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    while (true) {
        const node = xmlReader.read() catch |err| switch (err) {
            error.MalformedXml => {
                const loc = xmlReader.errorLocation();
                fatal("{d}:{d}: {s}", .{ loc.line, loc.column, @tagName(xmlReader.errorCode()) });
            },
            else => {
                fatal("Unexpected error in XML reader", .{});
            },
        };

        switch (node) {
            .eof => break,
            .element_start => {
                // hello
            },
            .element_end => {
                // world
            },
            else => {},
        }
    }

    try output_file.writeAll(
        \\pub const Person = struct {
        \\   age: usize = 18,
        \\   name: []const u8 = "foo"        
        \\};
    );
    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
