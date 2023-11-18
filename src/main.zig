// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;

const lexer = @import("lexer.zig");

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
fn repl() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch @panic("leaked");
    }
    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdio = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;
    while (true) {
        std.debug.print("reading input:", .{});
        if (try nextLine(stdio, &buffer)) |input| {
            // if(input.len == 0) break;
            try lexer.lexString(input, allocator);
        } else break;
    }
    std.debug.print("finished\n", .{});
}
// clojure koans
pub fn main() !void {
    try repl();
    
}
