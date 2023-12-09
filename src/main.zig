// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const std = @import("std");
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
const TagError = parser.TagError;
const TagElement = parser.TagElement;
// overrides std_options. see zig/lib/std/std.zig options_override
pub const std_options = struct {
    // Set the log level to info
    pub const log_level = .info;

    // Define logFn to override the std implementation
    // pub const logFn = myLogFn;
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
fn repl_token() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch @panic("leaked");
    }
    // var arena = std.heap.ArenaAllocator.init(g_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;
    try stdout.writeAll("tokenizing is the first part of parsing\n");
    while (true) {
        try stdout.print("reading input:", .{});
        if (try nextLine(stdin, &buffer)) |input| {
            if (input.len == 0) break;
            try lexer.lexString(g_allocator, input);
            // var reader = lexer.IterReader.init(g_allocator, input);
            // defer reader.deinit();
            // try reader.lexing();
            if (gpa.detectLeaks()) {
                log.err("token iterator leaked input address {*} and '{s}'", .{ input, input });
            }
        } else break;
    }
    try stdout.print("finished\n", .{});
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
            // if(input.len == 0) break;
            // var iter = lexer.Iterator.init(allocator, input) catch |err| blk: {
            //     try stdout.print("error in tokenizing {}. Salam\n", .{err});
            //     break :blk try lexer.Iterator.init(allocator, "subhanaAllah");
            // };
            // var arena = std.heap.ArenaAllocator.init(g_allocator);
            defer {
                // std.debug.print("arena deinit\n", .{});
                // arena.deinit();
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
                try stdout.print("{}\n", .{edn.*});

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
    std.debug.print("{}\n", .{@sizeOf(mem.Allocator)});
    std.debug.print("{} {} {} {} {}\n", .{ @sizeOf(EdnReader), @sizeOf(Edn), @sizeOf(big.Rational), @sizeOf(lexer.Iterator), @sizeOf(lexer.Token) });
    // try repl_token();
    try repl_edn();
    // try readEdn("baby");
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const g_allocator = gpa.allocator();
    // defer {
    //     _ = gpa.detectLeaks();

    //     const deinit_status = gpa.deinit();
    //     if (deinit_status == .leak) expect(false) catch @panic("leaked");
    // }

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
