const std = @import("std");
const xml = @import("xml");
const codegen = @import("generate_vk_wrappers/codegen.zig");

/// Reads all properties of an element until we reach its end.
/// If depth = null, then there is no tracking of depth - rather, we ensure that no others tags of the same name begin.
/// Otherwise, it tracks depth of the same element name. Make sure to be careful about partial parsing where depth does not start and end with 0.
fn readInsideElement(xml_reader: *xml.Reader, end_element_name: []const u8, depth: ?*usize) !?xml.Reader.Node {
    const node = try xml_reader.read();

    if (node == .eof) {
        // this element needs to end
        return error.UnexpectedEndOfXml;
    }

    if (node == .element_end and std.mem.eql(u8, xml_reader.elementName(), end_element_name)) {
        if (depth) |d| {
            if (d.* == 0) {
                // this element ended
                return null;
            } else {
                // left nesting
                d.* -= 1;
                return node;
            }
        } else {
            // this element ended
            return null;
        }
    }

    if (node == .element_start and std.mem.eql(u8, xml_reader.elementName(), end_element_name)) {
        if (depth == null) {
            // Recursion is not supported
            return error.XmlRecursion;
        } else {
            depth.?.* += 1;
        }
    }

    return node;
}

/// Similar to `readInsideElement`, and uses it internally.
/// This function is used to find the beginning of one of the desired elements represented in ElementSet.
fn findNextElement(ElementSet: anytype, xml_reader: *xml.Reader, end_element_name: []const u8, depth: ?*usize) !?ElementSet {
    switch (@typeInfo(ElementSet)) {
        .@"enum" => {},
        else => @compileError("ElementSet must be an enum"),
    }

    return while (true) {
        // End of stream and errors are both propagated out of here
        const node = try readInsideElement(xml_reader, end_element_name, depth) orelse break null;

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

fn attributeByName(xml_reader: *xml.Reader, name: []const u8) !?[]const u8 {
    for (0..xml_reader.attributeCount()) |i| {
        const attribute_name = xml_reader.attributeName(i);
        if (std.mem.eql(u8, attribute_name, name)) {
            return try xml_reader.attributeValue(i);
        }
    }
    return null;
}

/// Returns whether the element should be ignored because it's not for the basic "vulkan" api
fn checkApiAttribute(xml_reader: *xml.Reader) !bool {
    if (try attributeByName(xml_reader, "api")) |attribute_value| {
        if (!std.mem.eql(u8, attribute_value, "vulkan")) {
            // Ignore the element
            return false;
        }
    }
    return true;
}

// Creates a function which iterates over attributes defined in kvs_list,
// calling the handlers with a Context pointer parameter and returning any errors along the way.
fn attributeDispatch(Context: type, comptime kvs_list: []const struct { []const u8, *const fn (*Context, []const u8) anyerror!void }) (fn (*Context, *xml.Reader) anyerror!void) {
    const Handler = *const fn (*Context, []const u8) anyerror!void;
    const smap = std.StaticStringMap(Handler).initComptime(kvs_list);
    return struct {
        fn readXml(context: *Context, xml_reader: *xml.Reader) anyerror!void {
            for (0..xml_reader.attributeCount()) |i| {
                const attribute_name = xml_reader.attributeName(i);
                if (smap.get(attribute_name)) |handler| {
                    try handler(context, try xml_reader.attributeValue(i));
                }
            }
        }
    }.readXml;
}

/// Used with attributeDispatch
fn attributeDispatchCheckApiAttribute(_: *anyopaque, attribute_value: []const u8) anyerror!void {
    if (!std.mem.eql(u8, attribute_value, "vulkan")) {
        return error.IgnoreElement;
    }
}

/// Used for:
/// - Command parameters
/// - Struct members
pub const Field = struct {
    type_name: ?[]const u8 = null,
    field_name: ?[]const u8 = null,
    is_optional1: ?bool = null,
    is_optional2: ?bool = null,
    length_annotation: ?[]const u8 = null,

    pub fn isIncomplete(field: Field) bool {
        if (field.type_name == null) return true;
        if (field.field_name == null) return true;

        // all good
        return false;
    }

    pub fn getFieldName(field: Field) []const u8 {
        const field_name = field.field_name orelse @panic("must have field name in getFieldName");
        if (std.mem.eql(u8, field_name, "type")) {
            return "@\"type\"";
        }
        return field_name;
    }

    pub fn format(field: *const Field, writer: *std.Io.Writer) !void {
        try writer.print("{?s}: {?s}", .{ field.field_name, field.type_name });
        if (field.is_optional1) |is_optional1| {
            try writer.print(":opt1={any}", .{is_optional1});
        }
        if (field.is_optional2) |is_optional2| {
            try writer.print(":opt2={any}", .{is_optional2});
        }
        if (field.length_annotation) |length_annotation| {
            try writer.print(":len={s}", .{length_annotation});
        }
    }
};

/// Each <command> XML tag is parsed into this object
pub const Command = struct {
    return_type_name: ?[]const u8 = null,
    name: ?[]const u8 = null,
    /// Defaults to {name}_wrapper. Otherwise, may be set manually. Access using getWrapperName() - a lazy generator.
    wrapper_name: ?[]const u8 = null,
    /// Access using getFunctionType() - a lazy generator.
    function_type: ?[]const u8 = null,
    params: ?[]Field = null,

    pub fn init() Command {
        return .{};
    }

    pub fn format(command: *const Command, writer: *std.Io.Writer) !void {
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

    pub fn isIncomplete(command: Command) bool {
        if (command.name == null) return true;
        if (command.params == null) return true;
        for (command.params.?) |param| {
            if (param.isIncomplete()) {
                return true;
            }
        }

        // all good
        return false;
    }

    const CommandType = enum { Other, Instance, Device };

    pub fn classify(command: Command) CommandType {
        if (command.params) |command_params| {
            if (command_params.len > 0) {
                const first_param = command_params[0];
                if (first_param.type_name) |type_name| {
                    if (std.mem.eql(u8, type_name, "VkInstance")) {
                        return .Instance;
                    }
                    if (std.mem.eql(u8, type_name, "VkDevice")) {
                        return .Device;
                    }
                }
            }
        }
        return .Other;
    }

    pub fn getWrapperName(self: *Command, alloc: std.mem.Allocator) ![]const u8 {
        if (self.wrapper_name) |name| {
            return name;
        }
        const name = self.name orelse return error.UnnamedCommand;
        const generated_name = try std.fmt.allocPrint(alloc, "{s}_wrapper", .{name});
        self.wrapper_name = generated_name;
        return generated_name;
    }

    /// Generates a string like: `*const fn(usize, usize ...) isize`. And caches it in a field.
    pub fn getFunctionType(self: *Command, alloc: std.mem.Allocator) ![]const u8 {
        if (self.function_type) |function_type| {
            return function_type;
        }
        var array_list = std.ArrayList(u8).empty;
        const writer = array_list.writer(alloc);
        try writer.writeAll("*const fn(");
        if (self.params) |command_params| for (0.., command_params) |i, _| {
            if (i != 0) {
                try writer.writeAll(", ");
            }
            try writer.writeAll("usize");
        };
        try writer.writeAll(") callconv(.c) isize");
        const generated_function_type = try array_list.toOwnedSlice(alloc);
        self.function_type = generated_function_type;
        return generated_function_type;
    }
};

pub const StructType = struct {
    name: ?[]const u8 = null,
    members: ?[]Field = null,

    pub fn init() StructType {
        return .{};
    }

    pub fn format(struct_type: *const StructType, writer: *std.Io.Writer) !void {
        try writer.print("StructType  {?s}(", .{struct_type.name});
        if (struct_type.members) |members_slice| {
            var first = true;
            for (members_slice) |member| {
                if (first) {
                    first = false;
                } else {
                    try writer.print(", ", .{});
                }
                try writer.print("{f}", .{member});
            }
        }
        try writer.print(")", .{});
    }

    pub fn isIncomplete(struct_type: StructType) bool {
        if (struct_type.name == null) return true;
        if (struct_type.members == null) return true;
        for (struct_type.members.?) |member| {
            if (member.isIncomplete()) {
                return true;
            }
        }

        // all good
        return false;
    }
};

/// Represents the state of parsing. Every tag that is parsed gets stored into this state object.
const ParseState = struct {
    /// Freeing is not expected, so this is an arena
    arena: std.mem.Allocator,

    commands: std.ArrayListUnmanaged(Command),
    structs: std.ArrayListUnmanaged(StructType),

    pub fn init(arena: std.mem.Allocator) !ParseState {
        return .{ .arena = arena, .commands = try std.ArrayListUnmanaged(Command).initCapacity(arena, 1000), .structs = try std.ArrayListUnmanaged(StructType).initCapacity(arena, 1000) };
    }

    pub fn addCommand(self: *ParseState) !*Command {
        const result = try self.commands.addOne(self.arena);
        result.* = Command.init();
        return result;
    }

    pub fn unaddCommand(self: *ParseState) void {
        _ = self.commands.pop();
    }

    pub fn addStruct(self: *ParseState) !*StructType {
        const result = try self.structs.addOne(self.arena);
        result.* = StructType.init();
        return result;
    }

    pub fn unaddStruct(self: *ParseState) void {
        _ = self.structs.pop();
    }
};

fn parseBool(s: []const u8) ?bool {
    if (s.len == 5) {
        if (std.mem.eql(u8, s, "false")) return false;
    } else if (s.len == 4) {
        if (std.mem.eql(u8, s, "true")) return true;
    }
    return null;
}

fn attributeDispatchFieldOptional(dst: *struct { *Field, *ParseState }, attribute_value: []const u8) !void {
    const dst_field = dst[0];
    if (std.mem.indexOfScalar(u8, attribute_value, ',')) |comma_index| {
        const is_optional1 = parseBool(attribute_value[0..comma_index]);
        const is_optional2 = parseBool(attribute_value[comma_index + 1 ..]);
        if (is_optional1 == null or is_optional2 == null) {
            std.debug.print("Error parsing optional attribute: {s}\n", .{attribute_value});
            return error.ParseError;
        }
        dst_field.is_optional1 = is_optional1;
        dst_field.is_optional2 = is_optional2;
    } else {
        const is_optional1 = parseBool(attribute_value);
        if (is_optional1 == null) {
            std.debug.print("Error parsing optional attribute: {s}\n", .{attribute_value});
            return error.ParseError;
        }
        dst_field.is_optional1 = is_optional1;
    }
}

fn attributeDispatchFieldLen(dst: *struct { *Field, *ParseState }, attribute_value: []const u8) !void {
    const dst_field = dst[0];
    const dst_state = dst[1];
    dst_field.length_annotation = try dst_state.arena.dupe(u8, attribute_value);
}

fn parseField(dst_field: *Field, state: *ParseState, xml_reader: *xml.Reader, tag_name: []const u8) !bool {
    // reinitialize field structure
    dst_field.* = .{};

    const FieldChildTags = enum {
        type,
        name,
    };

    var dispatch_params: struct { *Field, *ParseState } = .{ dst_field, state };
    attributeDispatch(@TypeOf(dispatch_params), &.{ .{ "api", @ptrCast(&attributeDispatchCheckApiAttribute) }, .{ "optional", attributeDispatchFieldOptional }, .{ "len", attributeDispatchFieldLen } })(&dispatch_params, xml_reader) catch |err| switch (err) {
        error.IgnoreElement => {
            // Ignore the element
            std.debug.print("Ignoring field due to attributes\n", .{});
            while (try readInsideElement(xml_reader, tag_name, null) != null) {}
            return false;
        },
        // an actual error
        else => return err,
    };

    while (try findNextElement(FieldChildTags, xml_reader, tag_name, null)) |child_tag| switch (child_tag) {
        .type => {
            dst_field.type_name = try xml_reader.readElementTextAlloc(state.arena);
            std.debug.print("Found field's type {s}\n", .{dst_field.type_name.?});
        },
        .name => {
            dst_field.field_name = try xml_reader.readElementTextAlloc(state.arena);
            std.debug.print("Found field's name {s}\n", .{dst_field.field_name.?});
        },
    };

    return true;
}

fn parseCommand(state: *ParseState, xml_reader: *xml.Reader) !void {
    // Allocate a command object
    const parse_command = try state.addCommand();

    defer {
        // un-add the command if it isn't complete
        if (parse_command.isIncomplete()) {
            state.unaddCommand();
        }
    }

    if (!try checkApiAttribute(xml_reader)) {
        // Ignore the element
        while (try readInsideElement(xml_reader, "command", null) != null) {}
        return;
    }

    const ChildTags = enum {
        proto,
        param,
        implicitexternsyncparams,
    };
    var params = std.ArrayListUnmanaged(Field).empty;
    defer params.deinit(state.arena);
    var next_param = try params.addOne(state.arena);
    while (try findNextElement(ChildTags, xml_reader, "command", null)) |child_node| switch (child_node) {
        .proto => {
            std.debug.print("Found proto\n", .{});
            const ProtoChildTags = enum {
                type,
                name,
            };
            while (try findNextElement(ProtoChildTags, xml_reader, "proto", null)) |proto_child_node| switch (proto_child_node) {
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
            if (try parseField(next_param, state, xml_reader, "param")) {
                next_param = try params.addOne(state.arena);
            }
        },
        .implicitexternsyncparams => {
            // skip contents
            while (try readInsideElement(xml_reader, "implicitexternsyncparams", null) != null) {}
        },
    };
    // unadd the next_param
    _ = params.pop();

    parse_command.params = try params.toOwnedSlice(state.arena);
    std.debug.print("Parsed a command {f}\n", .{parse_command});
}

fn parseStruct(state: *ParseState, xml_reader: *xml.Reader) !void {
    // Allocate a struct object
    const parse_struct = try state.addStruct();

    defer {
        // un-add the struct if it isn't complete
        if (parse_struct.isIncomplete()) {
            state.unaddStruct();
        }
    }

    // get struct's name
    const name_attribute = try attributeByName(xml_reader, "name") orelse return;
    parse_struct.name = try state.arena.dupe(u8, name_attribute);

    const ChildTags = enum {
        member,
        foopleasecompile, // without this, there's an llvm error
    };
    var members = std.ArrayListUnmanaged(Field).empty;
    defer members.deinit(state.arena);
    var depth: usize = 0;
    var next_member = try members.addOne(state.arena);
    while (try findNextElement(ChildTags, xml_reader, "type", &depth)) |child_node| switch (child_node) {
        .member => {
            if (try parseField(next_member, state, xml_reader, "member")) {
                next_member = try members.addOne(state.arena);
            }
        },
        else => {},
    };
    // unadd the next_member
    _ = members.pop();

    parse_struct.members = try members.toOwnedSlice(state.arena);
    std.debug.print("Parsed a struct {f}\n", .{parse_struct});
}

const ElementParser = *const fn (*ParseState, *xml.Reader) anyerror!void;

const TypeParsers = std.StaticStringMap(ElementParser).initComptime(.{
    .{ "struct", parseStruct },
});

const ElementParsers = std.StaticStringMap(ElementParser).initComptime(.{
    .{ "command", parseCommand },
    .{ "type", parseType },
});

fn parseTypeHelper(xml_reader: *xml.Reader) !?ElementParser {
    if (!try checkApiAttribute(xml_reader)) {
        return null;
    }
    const type_category_attr = try attributeByName(xml_reader, "category") orelse return null;
    return TypeParsers.get(type_category_attr);
}

fn parseType(state: *ParseState, xml_reader: *xml.Reader) !void {
    if (try parseTypeHelper(xml_reader)) |element_parser| {
        return element_parser(state, xml_reader);
    } else {
        // skip contents
        var depth: usize = 0;
        while (try readInsideElement(xml_reader, "type", &depth) != null) {}
    }
}

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 3) fatal("wrong number of arguments\n", .{});

    const input_file_path = args[1];
    const input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        fatal("unable to open input '{s}': {s}\n", .{ input_file_path, @errorName(err) });
    };
    defer input_file.close();

    // For usage, see: https://github.com/ianprime0509/zig-xml/blob/c12dbb48606f716773a1ddf7d9b14e07524d1436/examples/reader.zig
    var read_buffer: [4096]u8 = undefined;
    var input_reader = input_file.reader(&read_buffer);
    var xml_streaming_reader: xml.Reader.Streaming = .init(arena, &input_reader.interface, .{});
    defer xml_streaming_reader.deinit();
    const xml_reader = &xml_streaming_reader.interface;

    const output_file_path = args[2];
    const output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
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
                    elementParser(&parse_state, xml_reader) catch |err| fatalXmlError(xml_reader, err);
                }
            },
            else => {},
        }
    }

    var output_buffer: [4096]u8 = undefined;
    var output_file_writer = output_file.writer(&output_buffer);
    var code_writer: codegen.CodeWriter = .{ .writer = &output_file_writer.interface };

    code_writer.line("const std = @import(\"std\");", .{});
    code_writer.line("const vk = @import(\"vk_headers\");", .{});
    code_writer.line("const findInstance = @import(\"so\").findInstance;", .{});
    code_writer.line("const findDevice = @import(\"so\").findDevice;", .{});

    var instance_function_map = try std.ArrayListUnmanaged(codegen.FunctionListEntry).initCapacity(arena, parse_state.commands.items.len);
    var device_function_map = try std.ArrayListUnmanaged(codegen.FunctionListEntry).initCapacity(arena, parse_state.commands.items.len);

    for (parse_state.commands.items) |*command| {
        switch (command.classify()) {
            .Instance => {
                const name = command.name orelse return error.UnnamedCommand;
                const wrapper_name = try command.getWrapperName(arena);
                const function_type = try command.getFunctionType(arena);
                try codegen.generateWrapperFunction(&code_writer, wrapper_name, command);
                instance_function_map.appendAssumeCapacity(.{ .command_name = name, .wrapper_name = wrapper_name, .function_type = function_type });
            },
            .Device => {
                const name = command.name orelse return error.UnnamedCommand;
                const wrapper_name = try command.getWrapperName(arena);
                const function_type = try command.getFunctionType(arena);
                try codegen.generateWrapperFunction(&code_writer, wrapper_name, command);
                device_function_map.appendAssumeCapacity(.{ .command_name = name, .wrapper_name = wrapper_name, .function_type = function_type });
            },
            else => {},
        }
    }
    codegen.generateFunctionList(&code_writer, "InstanceFunctions", instance_function_map.items);
    codegen.generateDispatchTableStruct(&code_writer, "InstanceDispatchTable", instance_function_map.items);
    codegen.generateFunctionList(&code_writer, "DeviceFunctions", device_function_map.items);
    codegen.generateDispatchTableStruct(&code_writer, "DeviceDispatchTable", device_function_map.items);

    // flush output
    try output_file_writer.end();

    // check errors
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
