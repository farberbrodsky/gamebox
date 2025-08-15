const std = @import("std");
const xml = @import("xml");
const codegen = @import("generate_vk_wrappers/codegen.zig");

/// Reads all properties of an element until we reach its end.
/// There is no tracking of depth - rather, we ensure that no others tags of the same name begin.
fn readInsideElement(xml_reader: *xml.Reader, end_element_name: []const u8) !?xml.Reader.Node {
    const node = try xml_reader.read();

    if (node == .eof) {
        // this element needs to end
        return error.UnexpectedEndOfXml;
    }

    if (node == .element_end and std.mem.eql(u8, xml_reader.elementName(), end_element_name)) {
        // this element ended
        return null;
    }

    if (node == .element_start and std.mem.eql(u8, xml_reader.elementName(), end_element_name)) {
        // Recursion is not supported
        return error.XmlRecursion;
    }

    return node;
}

/// Similar to `readInsideElement`, and uses it internally.
/// This function is used to find the beginning of one of the desired elements represented in ElementSet.
fn findNextElement(ElementSet: anytype, xml_reader: *xml.Reader, end_element_name: []const u8) !?ElementSet {
    switch (@typeInfo(ElementSet)) {
        .@"enum" => {},
        else => @compileError("ElementSet must be an enum"),
    }

    return while (true) {
        // End of stream and errors are both propagated out of here
        const node = try readInsideElement(xml_reader, end_element_name) orelse break null;

        // Is the desired element starting?
        if (node == .element_start) {
            const maybe_enum_value: ?ElementSet = std.meta.stringToEnum(ElementSet, xml_reader.elementName());

            if (maybe_enum_value) |enum_value| {
                // This is the only success case
                break enum_value;
            }
        }
    };
}

/// Used for:
/// - Command parameters
/// - Struct members
pub const Field = struct {
    type_name: ?[]const u8 = null,
    is_optional1: bool = false,
    is_optional2: bool = false,
    length_annotation: ?[]const u8 = null,
};

/// Each <command> XML tag is parsed into this object
pub const Command = struct {
    return_type_name: ?[]const u8 = null,
    name: ?[]const u8 = null,
    params: ?[]Field = null,

    pub fn init() Command {
        return .{};
    }

    pub fn format(command: Command, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Command     {?s} {?s}(", .{ command.return_type_name, command.name });
        if (command.params) |params_slice| {
            var first = true;
            for (params_slice) |param| {
                if (first) {
                    first = false;
                } else {
                    try writer.print(", ", .{});
                }
                try writer.print("{?s}", .{param.type_name});
            }
        }
        try writer.print(")", .{});
    }
};

/// Represents the state of parsing. Every tag that is parsed gets stored into this state object.
const ParseState = struct {
    /// Freeing is not expected, so this is an arena
    arena: std.mem.Allocator,

    commands: std.ArrayListUnmanaged(Command),

    pub fn init(arena: std.mem.Allocator) !ParseState {
        return .{ .arena = arena, .commands = try std.ArrayListUnmanaged(Command).initCapacity(arena, 1000) };
    }

    pub fn addCommand(self: *ParseState) !*Command {
        const result = try self.commands.addOne(self.arena);
        result.* = Command.init();
        return result;
    }

    pub fn unaddCommand(self: *ParseState) void {
        _ = self.commands.pop();
    }
};

fn parseCommand(state: *ParseState, xml_reader: *xml.Reader) !void {
    // Allocate a command object
    var parse_command = try state.addCommand();

    defer {
        // un-add the command if it isn't complete
        if (parse_command.name == null) {
            state.unaddCommand();
        }
    }

    for (0..xml_reader.attributeCount()) |i| {
        const attribute_name = xml_reader.attributeName(i);
        if (std.mem.eql(u8, attribute_name, "api")) {
            const attribute_value = try xml_reader.attributeValue(i);
            if (!std.mem.eql(u8, attribute_value, "vulkan")) {
                // Ignore the element
                while (try readInsideElement(xml_reader, "command") != null) {}
                return;
            }
        }
    }

    const ChildTags = enum {
        proto,
        param,
    };
    var params = std.ArrayList(Field).init(state.arena);
    defer params.deinit();
    while (try findNextElement(ChildTags, xml_reader, "command")) |child_node| switch (child_node) {
        .proto => {
            std.debug.print("Found proto\n", .{});
            const ProtoChildTags = enum {
                type,
                name,
            };
            while (try findNextElement(ProtoChildTags, xml_reader, "proto")) |proto_child_node| switch (proto_child_node) {
                .type => {
                    std.debug.print("Found proto's type\n", .{});
                    parse_command.return_type_name = try xml_reader.readElementTextAlloc(state.arena);
                },
                .name => {
                    parse_command.name = try xml_reader.readElementTextAlloc(state.arena);
                },
            };
        },
        .param => {
            std.debug.print("Found param\n", .{});
            const ParamChildTags = enum {
                type,
                name,
            };
            var param = Field{};
            while (try findNextElement(ParamChildTags, xml_reader, "param")) |param_child_node| switch (param_child_node) {
                .type => {
                    std.debug.print("Found param's type\n", .{});
                    param.type_name = try xml_reader.readElementTextAlloc(state.arena);
                },
                .name => {},
            };
            try params.append(param);
        },
    };

    parse_command.params = try params.toOwnedSlice();
    std.debug.print("Parsed a command {}\n", .{parse_command});
}

const ElementParsers = std.StaticStringMap(*const fn (*ParseState, *xml.Reader) anyerror!void).initComptime(.{
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
    var xml_doc = xml.streamingDocument(arena, input_file.reader());
    defer xml_doc.deinit();
    var xml_reader = xml_doc.reader(arena, .{});
    defer xml_reader.deinit();

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open output '{s}': {s}\n", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    var parse_state = try ParseState.init(arena);

    while (true) {
        const node = xml_reader.read() catch |err| fatalXmlError(xml_reader, err);

        switch (node) {
            .eof => break,
            .element_start => {
                const element_name = xml_reader.elementName();
                if (ElementParsers.get(element_name)) |elementParser| {
                    elementParser(&parse_state, &xml_reader.reader) catch |err| fatalXmlError(xml_reader, err);
                }
            },
            else => {},
        }
    }

    var code_writer: codegen.CodeWriter = .{ .writer = output_file.writer().any() };

    code_writer.line("const std = @import(\"std\");", .{});
    code_writer.line("const vk = @import(\"vk_headers\");", .{});

    const command_function_map = try arena.alloc(struct { []const u8, []const u8 }, parse_state.commands.items.len);
    for (0.., parse_state.commands.items) |i, command| {
        const name = command.name orelse return error.UnnamedCommand;
        const wrapper_name = try std.fmt.allocPrint(arena, "{s}_wrapper", .{name});
        command_function_map[i] = .{ name, wrapper_name };
    }
    codegen.generateFunctionMap(&code_writer, "InstanceFunctions", command_function_map);

    for (parse_state.commands.items, command_function_map) |command, command_names| {
        const wrapper_name = command_names[1];
        codegen.generateWrapperFunction(&code_writer, wrapper_name, &command);
    }

    if (code_writer.err) |e| return e;
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
