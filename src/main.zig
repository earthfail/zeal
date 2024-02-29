// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const std = @import("std");
const process = std.process;
const fs = std.fs;
const log = std.log;
const mem = std.mem;
const big = std.math.big;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;

// const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const EdnReader = parser.EdnReader;
const Edn = parser.Edn;
const TagHandler = parser.TagHandler;
const TagError = parser.TagError;
const TagElement = parser.TagElement;
// overrides std_options. see zig/lib/std/std.zig options_override
pub const std_options = struct {
    // Set the log level to info
    pub const log_level = .info;

    // Define logFn to override the std implementation
    // pub const logFn = myLogFn;
    pub const logFn = log.defaultLog;
};

fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(
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

fn repl_edn() !void {
    var gpa = std.heap.GeneralPurposeAllocator(
    //.{ .verbose_log = true, .retain_metadata = true }
    .{}){};
    const g_allocator = gpa.allocator();
    defer {
        // _ = gpa.detectLeaks();

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch {
            @panic("gpa leaked");
        };
    }

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
            // const allocator = arena.allocator();
            var reader = EdnReader.init(g_allocator, input);
            reader.data_readers = std.StringHashMap(parser.TagHandler).init(g_allocator);
            try reader.data_readers.?.put("inst", edn_to_inst);
            defer reader.deinit();
            // if (EdnReader.readEdn(allocator, &iter)) |edn| {
            if (reader.readEdn()) |edn| {
                log.info("address {*} type {s}, value:", .{ edn, @tagName(edn.*) });
                // log.info("edn from log {}\n",.{edn.*});
                // try stdout.print("{}\n", .{edn.*});
                const serialize = try parser.Edn.serialize(edn.*, g_allocator);
                defer g_allocator.free(serialize);

                try stdout.print("{s}\n", .{serialize});

                edn.deinit(g_allocator);
            } else |err| {
                try stdout.print("got error parsing input {}. Salam\n", .{err});
                // break;
            }
        } else break;
    }
    try stdout.print("finished\n", .{});
}

// clojure koans
pub fn main() !void {
    var t = try std.time.Timer.start();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    const file_name = if(args.len>1) args[1] else "resources/a.edn";
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
    var edn_reader = EdnReader.init(allocator, input);
    // reader.data_readers = std.StringHashMap(parser.TagHandler).init(g_allocator);
    // try reader.data_readers.?.put("inst", edn_to_inst);
    defer edn_reader.deinit();
    // if (EdnReader.readEdn(allocator, &iter)) |edn| {
    if (edn_reader.readEdn()) |edn| {
        // log.info("address {*} type {s}, value:", .{ edn, @tagName(edn.*) });
        // log.info("edn from log {}\n",.{edn.*});
        // try stdout.print("{}\n", .{edn.*});
        const serialize = try parser.Edn.serialize(edn.*, allocator);
        defer allocator.free(serialize);

        switch(edn.*) {
            .list, .vector => |v| {
                try stdout.print("length is {}\n",.{v.items.len});
                
            },
            else => {
                try stdout.print("output is not a vector\n",.{});
            }
        }
        // try stdout.print("{s}\n", .{serialize});

        edn.deinit(allocator);
    } else |_| {}

    std.debug.print("{}\n",.{@as(f64,@floatFromInt(t.read()))/1000_000});
    
    // else |err| {
    //     // try stdout.print("got error parsing input {}. Salam\n", .{err});
    //     // break;
    // }

    // std.debug.print("{}\n", .{@sizeOf(mem.Allocator)});
    // std.debug.print("{} {} {} {} {}\n", .{ @sizeOf(EdnReader), @sizeOf(Edn), @sizeOf(big.Rational), @sizeOf(lexer.Iterator), @sizeOf(lexer.Token) });
    // try repl_token();
    // try repl_edn();
    // try readEdn("baby");
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const g_allocator = gpa.allocator();
    // defer {
    //     _ = gpa.detectLeaks();

    //     const deinit_status = gpa.deinit();
    //     if (deinit_status == .leak) expect(false) catch @panic("leaked");
    // }
    // var x: i32 = 10;
    // var p: *const i32 = &x;
    // std.debug.print("{*} {*}\n", .{ p, @constCast(p) });
    // std.debug.print("honey {*}\n",.{&g_allocator});
    // var x = try f1(g_allocator);
    // std.debug.print("value {}\n",.{x});
    // g_allocator.destroy(&x);
    // g_allocator2.destroy(x);
    // var a = try readBigInteger(g_allocator, "1234");
    // std.debug.print("{*}\n",.{&a});
    // a.deinit();
}
fn edn_to_inst(allocator: mem.Allocator, edn: Edn) parser.TagError!*TagElement {
    switch (edn) {
        .integer => |i| {
            var i_p = try allocator.create(@TypeOf(i));
            i_p.* = i + 10;
            var ele = try allocator.create(TagElement);
            ele.pointer = @intFromPtr(i_p);
            ele.deinit = inst_deinit;
            ele.serialize = inst_serialize;
            return ele;
        },
        else => {
            return TagError.TypeNotSupported;
        },
    }
}
fn inst_deinit(pointer: usize, allocator: mem.Allocator) void {
    const i_p: *i64 = @ptrFromInt(pointer);
    allocator.destroy(i_p);
}
fn inst_serialize(pointer: usize, allocator: mem.Allocator) parser.SerializeError![]const u8 {
    const i_p: *i64 = @ptrFromInt(pointer);
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    const writer = buffer.writer();
    writer.print("{d}", .{i_p.*}) catch return parser.SerializeError.InvalidData;
    return buffer.toOwnedSlice();
}
