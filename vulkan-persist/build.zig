const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build dependencies
    const xml = b.dependency("xml", .{
        .target = target,
        .optimize = optimize,
    });

    // Code generation tools
    const tool = b.addExecutable(.{
        .name = "generate_vk_wrappers",
        .root_source_file = b.path("tools/generate_vk_wrappers.zig"),
        .target = b.graph.host,
    });
    tool.root_module.addImport("xml", xml.module("xml"));

    const tool_step = b.addRunArtifact(tool);
    tool_step.addFileArg(b.path("Vulkan-Headers/registry/vk.xml"));
    const tool_output = tool_step.addOutputFileArg("vk_wrappers.zig");

    // Code generation debugging
    const build_the_generator_cmd = b.step("build-generator", "Build vulkan wrappers generator");
    build_the_generator_cmd.dependOn(&b.addInstallArtifact(tool, .{}).step);

    const so_mod = b.createModule(.{
        .root_source_file = b.path("src/so.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vkheaders_mod = b.createModule(.{
        .root_source_file = b.path("src/vkheaders.zig"),
    });

    const vkwrappers_mod = b.createModule(.{
        .root_source_file = tool_output,
    });

    vkwrappers_mod.addImport("vk_headers", vkheaders_mod);
    // TODO: This should NOT be necessary in the long term.
    vkwrappers_mod.addImport("so", so_mod);
    so_mod.addImport("vk_headers", vkheaders_mod);
    so_mod.addImport("vk_wrappers", vkwrappers_mod);

    const example_mod = b.createModule(.{
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ?
    example_mod.addImport("vulkan_persist_lib", so_mod);

    // Build the layer library
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "vulkan_persist",
        .root_module = so_mod,
    });
    lib.linkLibC();
    lib.addIncludePath(b.path("Vulkan-Headers/include"));
    b.installArtifact(lib);

    // Build the example, which is something we can run
    const example_exe = b.addExecutable(.{
        .name = "vulkan_persist_example",
        .root_module = example_mod,
    });
    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = so_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = example_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
