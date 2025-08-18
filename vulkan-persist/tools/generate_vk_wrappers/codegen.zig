pub const CodeWriter = @import("CodeWriter.zig");
pub const FunctionListEntry = @import("function_list_gen.zig").FunctionListEntry;
pub const generateFunctionList = @import("function_list_gen.zig").generateFunctionList;
pub const generateDispatchTableStruct = @import("function_list_gen.zig").generateDispatchTableStruct;
pub const generateWrapperFunction = @import("wrapper_function_gen.zig").generateWrapperFunction;
