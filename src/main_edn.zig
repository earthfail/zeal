const std = @import("std");
const config = @import("config");
const process = std.process;
const fs = std.fs;

const parser = @import("parser.zig");
const EdnReader = parser.EdnReader;
const Edn = parser.Edn;
const TagHandler = parser.TagHandler;
const ErrorTag = parser.ErrorTag;
const TagElement = parser.TagElement;

// overrides std_options. see zig/lib/std/std.zig options_override
pub const std_options = std.Options{
    .log_level = .info,
};
pub fn main() !void {
    return benchmark_main();
}
pub fn benchmark_main() !void {
    const tracy = if (config.tracy_enable) @import("tracy") else null;

    if (config.tracy_enable != false) {
        tracy.setThreadName("edn");
        defer tracy.message("edn thread exit");
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.detectLeaks();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("oopsie\n", .{});
        }
    }
    const g_allocator = gpa.allocator();
    var logging_allocator = std.heap.LoggingAllocator(.debug, .debug).init(g_allocator);
    const allocator = alloc: {
        if (config.tracy_enable != false) {
            var os_allocator = tracy.TracingAllocator.initNamed("edn_gpa", logging_allocator.allocator());
            break :alloc os_allocator.allocator();
        } else {
            break :alloc logging_allocator.allocator();
        }
    };
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    const file_name = if (args.len > 1) args[1] else "resources/64KB.edn";
    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();

    const reader = file.reader();

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try reader.readAllArrayList(&list, 1000 * 1000 * 1000);

    const input = try list.toOwnedSlice();
    defer allocator.free(input);

    const stdout = std.io.getStdOut().writer();
    var edn_reader = try EdnReader.init(allocator, input);
    defer edn_reader.deinit();
    var t = try std.time.Timer.start();
    if (config.tracy_enable != false) {
        tracy.frameMark();
    }
    {
        var edn = edn_reader.readEdn() catch |err| {
            try stdout.print("got error parsing input {}\n", .{err});
            return err;
        };
        defer edn.deinit(allocator);
        if (config.tracy_enable != false) {
            const zone = tracy.initZone(@src(), .{ .name = "edn reader" });
            defer zone.deinit();
        }
        switch (edn) {
            .list, .vector => |v| {
                try stdout.print("edn says there is {}\n", .{v.items.len});
            },
            else => {
                try stdout.print("output is not a vector it is {s}\n", .{@tagName(edn)});
            },
        }
    }

    std.debug.print("edn timer {}\n", .{@as(f64, @floatFromInt(t.read())) / 1000_000});
}
