// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const tracy = @import("tracy");

const std = @import("std");
const process = std.process;
const fs = std.fs;
const log = std.log;
const mem = std.mem;
const big = std.math.big;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const EdnReader = parser.EdnReader;
const Edn = parser.Edn;
const TagHandler = parser.TagHandler;
const ErrorTag = parser.ErrorTag;
const TagElement = parser.TagElement;

// overrides std_options. see zig/lib/std/std.zig options_override
pub const std_options = std.Options{
    // Set the log level to info
    .log_level = .info,
    // pub const log_level = .info;

    // Define logFn to override the std implementation
    // pub const logFn = myLogFn;
    // pub const logFn = log.defaultLog;
};

fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    const line = (try reader.readUntilDelimiterOrEof(
        buffer,
        '\n',
    )) orelse return null;
    // trim annoying windows-only carriage return character
    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    } else {
        return line;
    }
}
fn repl_token() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const g_allocator = gpa.allocator();
    // defer {
    //     _ = gpa.detectLeaks();
    //     const deinit_status = gpa.deinit();
    //     if (deinit_status == .leak) expect(false) catch {
    //         @panic("gpa leaked");
    //     };
    // }
    // var logging_allocator = std.heap.LoggingAllocator(.debug, .debug).init(g_allocator);
    // const allocator = logging_allocator.allocator();
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;

    try stdout.print("lexing\n", .{});
    while (true) {
        try stdout.print("reading input:", .{});
        if (try nextLine(stdin, &buffer)) |input| {
            try lexer.lexString(input);
        } else {
            std.debug.print("didn't read anything\n", .{});
            break;
        }
    }
}
fn repl_edn() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch {
            std.debug.print("oops\n", .{});

            // @panic("gpa leaked");
        };
    }
    var logging_allocator = std.heap.LoggingAllocator(.debug, .debug).init(g_allocator);
    const allocator = logging_allocator.allocator();
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;
    try stdout.writeAll("edn is an extensible data notation\n");
    while (true) {
        try stdout.print("reading input:", .{});
        if (try nextLine(stdin, &buffer)) |input| {
            defer {
                if (gpa.detectLeaks()) {
                    std.debug.print("gpa detected leaks with input '{s}'\n", .{input});
                }
            }
            var reader = try EdnReader.init(allocator, input);
            reader.data_readers = std.StringHashMap(parser.TagHandler).init(allocator);
            try reader.data_readers.?.put("inst", edn_to_inst);
            defer reader.deinit();

            var edn = reader.readEdn() catch |err| {
                try stdout.print("got error parsing input {}. Salam\n", .{err});
                continue;
            };
            log.info("address {*} type {s}, value:", .{ &edn, @tagName(edn) });
            const serialize = try parser.Edn.serialize(edn, allocator);
            defer allocator.free(serialize);

            try stdout.print("{s}\n", .{serialize});

            edn.deinit(allocator);
        } else break;
    }
    try stdout.print("finished\n", .{});
}

pub fn main() !void {
    // try repl_token();
    try repl_edn();
    // try benchmark_main();
}
// clojure koans
pub fn benchmark_main() !void {
    // var t = try std.time.Timer.start();
    tracy.setThreadName("edn");
    defer tracy.message("edn thread exit");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    defer {
        _ = gpa.detectLeaks();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("oopsie\n", .{});
        }
    }
    const g_allocator = gpa.allocator();
    var logging_allocator = std.heap.LoggingAllocator(.debug, .debug).init(g_allocator);
    var os_allocator = tracy.TracingAllocator.initNamed("edn_gpa", logging_allocator.allocator());
    const allocator = os_allocator.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    const file_name = if (args.len > 1) args[1] else "resources/64KB.edn";
    // const file_name = "resources/64KB.edn";
    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();

    // var buf_reader = std.io.bufferedReader(file.reader());
    // const reader = buf_reader.reader();
    const reader = file.reader();

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try reader.readAllArrayList(&list, 1000 * 1000 * 1000);

    const input = try list.toOwnedSlice();
    defer allocator.free(input);

    // std.debug.print("input is '{s}'\n", .{input});

    const stdout = std.io.getStdOut().writer();
    var edn_reader = try EdnReader.init(allocator, input);
    // reader.data_readers = std.StringHashMap(parser.TagHandler).init(g_allocator);
    // try reader.data_readers.?.put("inst", edn_to_inst);
    defer edn_reader.deinit();
    // if (EdnReader.readEdn(allocator, &iter)) |edn| {
    var t = try std.time.Timer.start();
    tracy.frameMark();
    {
        var edn = edn_reader.readEdn() catch |err| {
            try stdout.print("got error parsing input {}\n", .{err});
            return err;
        };
        defer edn.deinit(allocator);
        const zone = tracy.initZone(@src(), .{ .name = "edn reader" });
        defer zone.deinit();
        // log.info("address {*} type {s}, value:", .{ edn, @tagName(edn.*) });
        // log.info("edn from log {}\n",.{edn.*});
        // try stdout.print("{}\n", .{edn.*});
        // const serialize = try parser.Edn.serialize(edn, allocator);
        // defer allocator.free(serialize);
        // std.debug.print("Hi mom\n",.{});

        switch (edn) {
            .list, .vector => |v| {
                try stdout.print("edn says there is {}\n", .{v.items.len});
            },
            else => {
                try stdout.print("output is not a vector it is {s}\n", .{@tagName(edn)});
            },
        }
        // try stdout.print("{s}\n", .{serialize});

        // TODO(Salim): learn how manage data you incompetent ******
        // edn.deinit(allocator);
    }

    std.debug.print("edn timer {}\n", .{@as(f64, @floatFromInt(t.read())) / 1000_000});
}
fn edn_to_inst(allocator: mem.Allocator, edn: Edn) parser.ErrorTag!*TagElement {
    switch (edn) {
        .integer => |i| {
            const i_p = try allocator.create(@TypeOf(i));
            i_p.* = i + 10;
            var ele = try allocator.create(TagElement);
            ele.pointer = i_p;
            ele.deinit = inst_deinit;
            ele.serialize = inst_serialize;
            return ele;
        },
        else => {
            return ErrorTag.TypeNotSupported;
        },
    }
}
fn inst_deinit(pointer: *anyopaque, allocator: mem.Allocator) void {
    const i_p: *i64 = @ptrCast(@alignCast(pointer));
    allocator.destroy(i_p);
}
fn inst_serialize(pointer: *anyopaque, allocator: mem.Allocator) parser.SerializeError![]const u8 {
    const i_p: *i64 = @ptrCast(@alignCast(pointer));
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    const writer = buffer.writer();
    writer.print("{d}", .{i_p.*}) catch return parser.SerializeError.InvalidData;
    return buffer.toOwnedSlice();
}
