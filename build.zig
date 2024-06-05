// https://ziglang.org/learn/build-system/
const std = @import("std");
// TODO: change name from zeal to end_parser
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.option(bool, "add_module", "make module from edn.zig") orelse false;
    if (module) {
        _ = b.addModule("zeal", .{
            .root_source_file = .{ .path = "src/edn.zig" },
        });
    }
    // const gen_flat = b.option(bool,"generate-flat","generate resources/64KB.txt with the same data more compactly") orelse false;

    {
        const gen = b.addExecutable(.{
            .name = "gen",
            .target = b.host,
            .root_source_file = b.path("src/flat_data.zig"),
        });
        const run_gen = b.addRunArtifact(gen);
        run_gen.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_gen.addArgs(args);
        }
        const gen_step = b.step("gen", "generate flat data file with each record on a separate line");
        gen_step.dependOn(&run_gen.step);
    }
    const json_step = buildJson(b, target, optimize);
    const edn_step = buildEdn(b, target, optimize);
    const exe = b.addExecutable(.{
        .name = "repl",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const steps = [_]*std.Build.Step.Compile{ json_step, edn_step, exe };

    const options = b.addOptions();
    {
        const tracy_enable = b.option(bool, "tracy-enable", "Enable Profiling") orelse false;
        options.addOption(bool, "tracy_enable", tracy_enable);

        const tracy = b.dependency("tracy-zig", .{
            .target = target,
            .optimize = optimize,
            .tracy_enable = tracy_enable,
        });

        if (tracy_enable) {
            for (steps) |step| {
                step.root_module.addImport("tracy", tracy.module("tracy"));
                step.linkLibrary(tracy.artifact("tracy"));
                step.linkLibCpp();
            }
        }
    }
    for (steps) |step| {
        step.root_module.addOptions("config", options);
        b.installArtifact(step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const json_cmd = b.addRunArtifact(json_step);
    json_cmd.step.dependOn(b.getInstallStep());

    const benchmark_json = b.step("json", "Run main_json.zig");
    benchmark_json.dependOn(&json_cmd.step);

    const benchmark = b.step("bench", "Run main.zip and main_json.zig");
    benchmark.dependOn(&json_cmd.step);
    benchmark.dependOn(&run_cmd.step);

    const files = [_][]const u8{ "src/lexer.zig", "src/parser.zig" };
    const test_step = b.step("test", "Run unit tests");
    for (files) |f| {
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = f },
            .target = target,
            .optimize = optimize,
        });
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
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
fn buildEdn(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "edn-parser",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main_edn.zig" },
    });

    return exe;
}
