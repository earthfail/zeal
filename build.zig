// https://ziglang.org/learn/build-system/
const std = @import("std");
// TODO: change name from zeal to end_parser
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const json_step = buildJson(b, target, optimize);

    // TODO(Salim): Remove ziglyph
    // ziglyph
    const ziglyph = b.dependency("ziglyph", .{
        .optimize = optimize,
        .target = target,
    });

    const module = b.option(bool, "add_module", "make module from edn.zig") orelse false;
    if (module) {
        _ = b.addModule("zeal", .{
            .root_source_file = .{ .path = "src/edn.zig" },
            // .dependencies = &.{
            //     // zig uses this information to add ziglyph when adding zeal
            //     .{
            //         .name = "ziglyph",
            //         .module = ziglyph.module("ziglyph"),
            //     },
            // },
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
    exe.root_module.addImport("ziglyph", ziglyph.module("ziglyph"));

    {
        const tracy_enable = b.option(bool, "tracy-enable", "Enable Profiling") orelse false;
        const tracy = b.dependency("tracy-zig", .{
            .target = target,
            .optimize = optimize,
            .tracy_enable = tracy_enable,
        });
        json_step.root_module.addImport("tracy", tracy.module("tracy"));
        json_step.linkLibrary(tracy.artifact("tracy"));
        json_step.linkLibCpp();

        exe.root_module.addImport("tracy", tracy.module("tracy"));
        exe.linkLibrary(tracy.artifact("tracy"));
        exe.linkLibCpp();
    }
    // exe.addModule("zeal",zeal);
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
        unit_tests.root_module.addImport("ziglyph", ziglyph.module("ziglyph"));

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    // const benchmark = b.step("bench", "Run main.zip and main_json.zig");
    const benchmark = b.step("json", "Run main_json.zig");
    const run_json = b.addRunArtifact(json_step);
    run_json.step.dependOn(b.getInstallStep());
    benchmark.dependOn(&run_json.step);
    // benchmark.dependOn(&run_cmd.step);
}

fn buildJson(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "json-parser",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main_json.zig" },
    });

    return exe;
}
