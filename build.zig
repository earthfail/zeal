// https://ziglang.org/learn/build-system/
const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const json_step = buildJson(b, target, optimize);

    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // ziglyph
    const ziglyph = b.dependency("ziglyph", .{
        .optimize = optimize,
        .target = target,
    });

    const module = b.option(bool, "add_module", "make module from edn.zig") orelse false;
    if (module) {
        _ = b.addModule("zeal", .{
            .source_file = .{ .path = "src/edn.zig" },
            .dependencies = &.{
                // zig uses this information to add ziglyph when adding zeal
                .{
                    .name = "ziglyph",
                    .module = ziglyph.module("ziglyph"),
                },
            },
        });
    }
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
        .name = "edn-parser",

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

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const files = [_][]const u8{ "src/main.zig", "src/lexer.zig", "src/parser.zig" };
    const test_step = b.step("test", "Run unit tests");
    for (files) |f| {
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
