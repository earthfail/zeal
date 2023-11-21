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
            var iter = try lexer.Iterator.init(allocator, input);
            if (readEdn(allocator, &iter)) |edn| {
                try stdout.print("{}\n", .{edn.*});
            } else |err| {
                try stdout.print("got error reading input {}. Salam\n", .{err});
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
pub fn readEdn(allocator: mem.Allocator, iter: *lexer.Iterator) !*const Edn {
    // var iter = lexer.Iterator.init(allocator, str);
    if (iter.next()) |token| {
        log.info("token is {}", .{token});
        switch (token.tag) {
            // .nil => return Edn{ .nil = Edn.nil },
            .symbol => {
                if (mem.eql(u8, "true", token.literal.?)) {
                    return &Edn.true;
                } else if (mem.eql(u8, "false", token.literal.?)) {
                    return &Edn.false;
                } else if (mem.eql(u8, "nil", token.literal.?)) {
                    return &Edn.nil;
                } else {
                    const value = try allocator.create(Edn);
                    value.* = .{ .symbol = token.literal.? };
                    return value;
                }
            },
            .keyword => {
                const value = try allocator.create(Edn);
                // const keyword = try allocator.create(Keyword);
                // keyword.name = token.literal.?;
                // value.* = .{ .keyword = .{ .name = token.literal.? } };
                value.* = .{ .keyword = token.literal.? };
                return value;
            },
            .string => {
                const value = try allocator.create(Edn);
                value.* = .{ .string = token.literal.? };
                return value;
            },
            .character => {
                const c = lexer.Iterator.firstCodePoint(token.literal.?);
                const value = try allocator.create(Edn);
                value.* = .{ .character = c };
                return value;
            },
            .integer => {
                const int = try std.fmt.parseInt(i64, token.literal.?, 10);
                const value = try allocator.create(Edn);
                value.* = .{ .integer = int };
                return value;
            },
            .float => {
                const float = try std.fmt.parseFloat(f64, token.literal.?);
                const value = try allocator.create(Edn);
                value.* = .{ .float = float };
                return value;
            },
            // .@"#{", .@"{", .@"[", .@"(", .@")", .@"]", .@"}" => {
            .@"(" => {
                const value = try allocator.create(Edn);
                value.* = .{ .list = std.ArrayList(*const Edn).init(allocator) };
                errdefer allocator.destroy(value);
                errdefer value.list.deinit();

                while (iter.peek()) |token2| {
                    switch (token2.tag) {
                        .@"}", .@"]" => return error.ParenMismatch,
                        .@")" => {
                            _ = iter.next();
                            log.info("value len is {}", .{value.list.items.len});
                            return value;
                        },
                        else => {
                            const item = try readEdn(allocator, iter);
                            try value.list.append(item);
                        },
                    }
                }
                return error.@"collection delimiter";
            },
            .@"[" => {
                const value = try allocator.create(Edn);
                value.* = .{ .vector = std.ArrayList(*const Edn).init(allocator) };
                errdefer allocator.destroy(value);
                errdefer value.vector.deinit();

                while (iter.peek()) |token2| {
                    switch (token2.tag) {
                        .@"}", .@")" => return error.ParenMismatch,
                        .@"]" => {
                            _ = iter.next();
                            return value;
                        },
                        else => {
                            const item = try readEdn(allocator, iter);
                            try value.vector.append(item);
                        },
                    }
                }
                return error.@"collection delimiter";
            },
            .@"#{" => {
                const value = try allocator.create(Edn);
                value.* = .{ .hashset = std.AutoArrayHashMap(*const Edn, *const Edn).init(allocator) };
                errdefer allocator.destroy(value);
                errdefer value.list.deinit();

                while (iter.peek()) |token2| {
                    switch (token2.tag) {
                        .@")", .@"]" => return error.ParenMismatch,
                        .@"}" => {
                            _ = iter.next();
                            log.info("value len is {}", .{value.hashset.count()});
                            return value;
                        },
                        else => {
                            const item = try readEdn(allocator, iter);
                            try value.hashset.put(item, item);
                        },
                    }
                }
                return error.@"collection delimiter";
            },
            .@"{" => {
                const value = try allocator.create(Edn);
                value.* = .{ .hashmap = std.AutoArrayHashMap(*const Edn, *const Edn).init(allocator) };
                errdefer allocator.destroy(value);
                errdefer value.hashmap.deinit();

                while (iter.peek()) |token2| {
                    switch (token2.tag) {
                        .@")", .@"]" => return error.ParenMismatch,
                        .@"}" => {
                            _ = iter.next();
                            log.info("hashmap len is {}", .{value.hashmap.count()});
                            return value;
                        },
                        else => {
                            const key = try readEdn(allocator, iter);
                            // const val = try readEdn(allocator, iter);
                            if (iter.peek()) |token3| {
                                switch (token3.tag) {
                                    .@")", .@"]" => return error.ParenMismatch2,
                                    .@"}" => return error.OddNumberHashMap,
                                    else => {
                                        const val = try readEdn(allocator, iter);
                                        try value.hashmap.put(key, val);
                                    },
                                }
                            } else return error.OddNumberHashMap2;
                        },
                    }
                }
                return error.@"collection delimiter";
            },
            .@"#_" => {
                const t = try readEdn(allocator, iter);
                allocator.destroy(t);
                return readEdn(allocator, iter);
            },
            .tag => {
                // var value = allocator.create(Edn);
                return error.NotFinished;
            },
            else => {
                return error.@"edn still didn't implement type";
            },
        }
    } else {
        log.warn("got null", .{});
    }

    return error.@"edn is an extensible data format";
}
const EdnReader = struct {
    buffer: []const u8,
    iter: lexer.Iterator,
    arena: std.heap.ArenaAllocator,
    data_reader: std.StringHashMap(*const fn (allocator: mem.Allocator, edn: *Edn) usize) = undefined,

    /// allocator is used to make arena allocator.
    pub fn init(allocator: mem.Allocator, buffer: []const u8) EdnReader {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var iter = lexer.Iterator.init(arena.allocator(), buffer);
        return .{ .buffer = buffer, .iter = iter, .arena = arena };
    }
    pub fn deinit(self: *EdnReader) !void {
        self.arena.deinit();
    }
};
// I decided to keep keyword and symbol simple and we can compute each part (prefix,name) on demand.
const Edn = union(enum) {
    nil: Nil,
    boolean: bool,
    // string: [:0]const u8,
    string: []const u8,
    character: u21,

    symbol: []const u8,
    keyword: Keyword,

    integer: i64,
    float: f64,
    list: std.ArrayList(*const Edn),
    vector: std.ArrayList(*const Edn),
    hashmap: std.AutoArrayHashMap(*const Edn, *const Edn),
    hashset: std.AutoArrayHashMap(*const Edn, *const Edn),
    tag: Tag,
    pub const Character = u21;

    const Nil = enum { nil };
    pub const nil = Edn{ .nil = Nil.nil };
    pub const @"true" = Edn{ .boolean = true };
    pub const @"false" = Edn{ .boolean = false };

    pub fn format(value: Edn, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
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
                try writer.print("\\{u}", .{value.character});
            },
            .symbol => {
                try writer.print("{s}", .{value.symbol});
            },
            .keyword => {
                try writer.print(":{s}", .{value.keyword});
            },
            .list => {
                try writer.writeAll("( ");
                for (value.list.items) |item| {
                    try format(item.*, fmt, options, writer);
                    try writer.writeAll(" ");
                }
                try writer.writeAll(" )");
            },
            .vector => {
                try writer.writeAll("[");
                for (value.vector.items) |item| {
                    try format(item.*, fmt, options, writer);
                    try writer.writeAll(" ");
                }
                try writer.writeAll("]");
            },
            .hashmap => {
                try writer.writeAll("{");
                var iterator = value.hashmap.iterator();
                while (iterator.next()) |entry| {
                    try format(entry.key_ptr.*.*, fmt, options, writer);
                    try writer.writeAll(" ");
                    try format(entry.value_ptr.*.*, fmt, options, writer);
                    try writer.writeAll(", ");
                }
                try writer.writeAll("}");
            },
            .hashset => {
                try writer.writeAll("#{");
                var iterator = value.hashset.iterator();
                while (iterator.next()) |entry| {
                    try format(entry.key_ptr.*.*, fmt, options, writer);
                    try writer.writeAll(" ");
                    try format(entry.value_ptr.*.*, fmt, options, writer);
                    try writer.writeAll(", ");
                }
                try writer.writeAll("}");
            },
            else => {},
        }
    }
};
pub const Tag = struct {
    tag: []const u8,
    element: union { edn: *Edn, pointer: usize },
};

pub const Symbol = []const u8;
// pub const Symbol = struct {
//     name: []const u8,

//     pub fn format(value: Symbol, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
//         _ = options;
//         _ = fmt;
//         try writer.writeAll("Symbol ");
//         if (value.namespace) |namespace| {
//             try writer.writeAll(namespace);
//             try writer.writeAll("/");
//         }
//         try writer.writeAll(value.name);
//     }
// };

// using struct just to implement format.
pub const Keyword = []const u8;
// pub const Keyword = struct {
//     name: []const u8,

//     pub fn format(value: Keyword, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
//         _ = options;
//         _ = fmt;
//         try writer.writeAll("Keyword #");
//         if (value.namespace) |namespace| {
//             try writer.writeAll(namespace);
//             try writer.writeAll("/");
//         }
//         try writer.writeAll(value.name);
//     }
// };
