const std = @import("std");
const xml = @import("xml");

fn readInsideElement(xmlReader: *xml.Reader, elementName: []const u8) !?xml.Reader.Node {
    const node = try xmlReader.read();

    if (node == .eof) {
        // this element needs to end
        return error.UnexpectedEndOfXml;
    }

    if (node == .element_end and std.mem.eql(u8, xmlReader.elementName(), elementName)) {
        // this element ended
        return null;
    }

    if (node == .element_start and std.mem.eql(u8, xmlReader.elementName(), elementName)) {
        // Recursion is not supported
        return error.XmlRecursion;
    }

    return node;
}

fn parseCommand(alloc: std.mem.Allocator, xmlReader: *xml.Reader) !void {
    _ = .{alloc};
    std.debug.print("Parsing a command\n", .{});

    for (0..xmlReader.attributeCount()) |i| {
        const attribute_name = xmlReader.attributeNameNs(i);
        std.debug.print("attrib '{s}'\n", .{attribute_name.local});
    }

    while (try readInsideElement(xmlReader, "command")) |childNode| {
        switch (childNode) {
            .eof => {
                fatal("Unexpected EOF\n", .{});
            },
            else => {},
        }
    }
}

const ElementParsers = std.StaticStringMap(*const fn (std.mem.Allocator, *xml.Reader) anyerror!void).initComptime(.{
    .{ "command", parseCommand },
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 3) fatal("wrong number of arguments\n", .{});

    const input_file_path = args[1];
    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        fatal("unable to open input '{s}': {s}\n", .{ input_file_path, @errorName(err) });
    };
    defer input_file.close();

    // For usage, see: https://github.com/ianprime0509/zig-xml/blob/c12dbb48606f716773a1ddf7d9b14e07524d1436/examples/reader.zig
    var xmlDoc = xml.streamingDocument(arena, input_file.reader());
    defer xmlDoc.deinit();
    var xmlReader = xmlDoc.reader(arena, .{});
    defer xmlReader.deinit();

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open output '{s}': {s}\n", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    while (true) {
        const node = xmlReader.read() catch |err| fatalXmlError(xmlReader, err);

        switch (node) {
            .eof => break,
            .element_start => {
                const elementName = xmlReader.elementName();
                if (ElementParsers.get(elementName)) |elementParser| {
                    elementParser(arena, &xmlReader.reader) catch |err| fatalXmlError(xmlReader, err);
                }
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

fn fatalXmlError(xmlReader: anytype, err: anyerror) noreturn {
    switch (err) {
        error.MalformedXml => {
            const loc = xmlReader.errorLocation();
            fatal("{d}:{d}: {s}", .{ loc.line, loc.column, @tagName(xmlReader.errorCode()) });
        },
        error.UnexpectedEndOfXml => {
            fatal("Unexpected end of XML", .{});
        },
        error.XmlRecursion => {
            fatal("Unexpected XML recursion", .{});
        },
        else => {
            fatal("Unexpected error in XML reader", .{});
        },
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
