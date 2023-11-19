// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const std = @import("std");
const log = std.log;
const mem = std.mem;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;

const lexer = @import("lexer.zig");
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
    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;
    try stdout.writeAll("tokenizing is the first part of parsing\n");
    while (true) {
        try stdout.print("reading input:", .{});
        if (try nextLine(stdin, &buffer)) |input| {
            // if(input.len == 0) break;
            try lexer.lexString(allocator, input);
        } else break;
    }
    try stdout.print("finished\n", .{});
}
fn repl_edn() !void {
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

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;
    try stdout.writeAll("edn is an extensible data notation\n");
    while (true) {
        try stdout.print("reading input:", .{});
        if (try nextLine(stdin, &buffer)) |input| {
            // if(input.len == 0) break;
            var iter = lexer.Iterator.init(allocator,input);
            if (readEdn(allocator, &iter)) |edn| {
                try stdout.print("{}\n", .{edn});
            } else |err|{
                try stdout.print("got error reading input {}. Salam\n",.{err});
                // break;
            }
        } else break;
    }
    try stdout.print("finished\n", .{});
}
// clojure koans
pub fn main() !void {
    // try repl_token();
    try repl_edn();
    // try readEdn("baby");

}
pub fn readEdn(allocator: mem.Allocator, iter: *lexer.Iterator) !Edn {
    // var iter = lexer.Iterator.init(allocator, str);
    if (iter.next2()) |tok| {
        if (tok) |token| {
            switch (token.tag) {
                // .nil => return Edn{ .nil = Edn.nil },
                .symbol => {
                    if (mem.eql(u8, "true", token.literal.?)) {
                        return Edn{ .boolean = true };
                    } else if (mem.eql(u8, "false", token.literal.?)) {
                        return Edn{ .boolean = false };
                    } else if (mem.eql(u8, "nil", token.literal.?)) {
                        return Edn{ .nil = Edn.nil };
                    } else return Edn{ .symbol = token.literal.? };
                },
                .keyword => {
                    return Edn{ .keyword = token.literal.? };
                },
                .string => {
                    return Edn{ .string = token.literal.? };
                },
                .character => {
                    return Edn{ .character = token.literal.? };
                },
                .integer => {
                    const value = try std.fmt.parseInt(i64, token.literal.?, 10);
                    return Edn{.integer = value};
                },
                .float => {
                    const value = try std.fmt.parseFloat(f64, token.literal.?);
                    return Edn{.float = value};
                },
                .@"#{", .@"{", .@"[", .@"(", .@")", .@"]", .@"}" => {
                    // return readEdn(allocator, iter);
                    return error.@"collection delimiter";
                },
                .@"#_" => {
                    _ = try readEdn(allocator, iter);
                    return readEdn(allocator,iter);
                },
                else => {return error.NotFinished;}
            }
        } else {
            log.info("got null", .{});
        }
    } else |err| {
        log.err("got err {}", .{err});
    }
    return error.@"edn is an extensible data format";
}
const EdnReader = struct {
    data_reader: std.StringHashMap(*const fn(allocator: mem.Allocator, edn: *Edn) usize),
};
const Edn = union(enum) {
    nil: Nil,
    boolean: bool,
    // string: [:0]const u8,
    string: []const u8,
    character: []const u8, // TODO: use u21 type

    symbol: []const u8, // TODO: consider using Symbols
    keyword: []const u8, // TODO: consider using Keyword

    integer: i64,
    float: f64,
    list: std.ArrayList(*Edn),
    hashmap: std.AutoArrayHashMap(*Edn, *Edn),

    pub const Character = u21;

    const Nil = enum { nil };
    pub const nil = Nil.nil;

    pub const Symbol = struct {
        namespace: ?[]const u8,
        name: []const u8,

        pub fn format(value: Symbol, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            _ = fmt;
            try writer.writeAll("Symbol ");
            if (value.namespace) |namespace| {
                try writer.writeAll(namespace);
                try writer.writeAll("/");
            }
            try writer.writeAll(value.name);
        }
    };
    pub const Keyword = struct {
        namespace: ?[]const u8,
        name: []const u8,

        pub fn format(value: Keyword, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            _ = fmt;
            try writer.writeAll("Keyword #");
            if (value.namespace) |namespace| {
                try writer.writeAll(namespace);
                try writer.writeAll("/");
            }
            try writer.writeAll(value.name);
        }
    };
    pub fn format(value: Edn, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (value) {
            .nil => try writer.writeAll("nil"),
            .boolean => {
                if (value.boolean) {
                    try writer.writeAll("true");
                } else try writer.writeAll("false");
            },
            .string => {
                try writer.print("\"{s}\"", .{value.string});
            },
            .character => {
                try writer.print("\\{s}", .{value.character});
            },
            else => {},
        }
    }
};
