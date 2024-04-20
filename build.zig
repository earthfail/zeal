// https://ziglang.org/learn/build-system/
const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const json_step = buildJson(b, target, optimize);


    // ziglyph
    const ziglyph = b.dependency("ziglyph", .{
        .optimize = optimize,
        .target = target,
    });
    
    _ = b.addModule("zeal", .{
        .source_file = .{ .path = "src/edn.zig"},
        .dependencies = &.{
            // zig uses this information to add ziglyph when adding zeal
            .{
                .name = "ziglyph",
                .module = ziglyph.module("ziglyph"),
            },
        },
    });

    //// useful if I want to create a static library
    // const lib = b.addStaticLibrary(.{
    //     // library file name is "lib[name].a"
    //     .name = "zeal-lib",
    //     .root_source_file = .{ .path = "src/edn.zig"},
    //     .target = target,
    //     .optimize = optimize,
    // });
    // lib.addModule("ziglyph",ziglyph.module("ziglyph"));
    // b.installArtifact(lib);
    
    const exe = b.addExecutable(.{
        // executable file name is "[name]"
        .name = "edn-parser",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("ziglyph", ziglyph.module("ziglyph"));

    // exe.addModule("zeal",zeal);
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const files = [_][]const u8{"src/main.zig","src/lexer.zig","src/parser.zig"};
    const test_step = b.step("test", "Run unit tests");
    for(files) |f| {
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = f },
            .target = target,
            .optimize = optimize,
        });
        unit_tests.addModule("ziglyph", ziglyph.module("ziglyph"));

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    const benchmark = b.step("bench", "Run main.zip and main_json.zig");
    const run_json = b.addRunArtifact(json_step);
    run_json.step.dependOn(b.getInstallStep());
    benchmark.dependOn(&run_json.step);
    benchmark.dependOn(&run_cmd.step);
}

fn buildJson(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "json-parser",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main_json.zig" },
    });

    return exe;
}
