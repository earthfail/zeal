const std = @import("std");
const expect = std.testing.expect;
const process = std.process;
const fs = std.fs;

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
const Iterator = @import("lexer.zig").Iterator;
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
    // try repl_token();
    return benchmark_lexer();
}

fn benchmark_lexer() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
    var iterator = try Iterator.init(input);
    var t = try std.time.Timer.start();

    var counter: usize = 0;
    while(iterator.next()) |_| {
        counter += 1;
    } else {
        if(iterator.iter.i<input.len) {
            try stdout.print("got next null. state is {any} character {} {c} {c}\n",
                             .{iterator.window,iterator.iter.i,
                               input[iterator.iter.i],
                               iterator.iter.bytes[iterator.iter.i]});
        }
    }
    std.debug.print("got {} in {}\n",.{counter,@as(f64,@floatFromInt(t.read())) / 1000_000});
}
