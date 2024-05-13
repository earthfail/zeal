const std = @import("std");
const expect = std.testing.expect;

// const lexer = @import("lexer.zig");

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
const LexError = @import("lexer.zig").LexError;
const lexString = @import("lexer.zig").lexString;
fn repl_token() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;

    try stdout.print("lexing\n", .{});
    // var lexer = try std.DynLib.open("zig-out/lib/" ++ "liblexer.so");
    // const lexString = lexer.lookup(*const fn([:0]const u8) LexError!void,"lexString") orelse return error.NoLexer;
    while (true) {
        try stdout.print("reading input:", .{});
        if (try nextLine(stdin, &buffer)) |input| {
            try lexString(input);
        } else {
            std.debug.print("didn't read anything\n", .{});
            break;
        }
    }
}
pub fn main() !void {
    try repl_token();
}
