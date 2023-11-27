// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const std = @import("std");
const log = std.log;
const mem = std.mem;
const big = std.math.big;
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
            var iter = lexer.Iterator.init(allocator, input) catch |err| blk: {
                try stdout.print("error in tokenizing {}. Salam\n", .{err});
                break :blk try lexer.Iterator.init(allocator, "subhanaAllah");
            };
            if (readEdn(allocator, &iter)) |edn| {
                log.info("type {s}, value:", .{@tagName(edn.*)});
                try stdout.print("{}\n", .{edn.*});
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
                const literal = token.literal.?;
                const value = try allocator.create(Edn);
                errdefer allocator.destroy(value);
                if (literal[literal.len - 1] == 'N') {
                    value.* = .{ .bigInteger = try readBigInteger(allocator, literal[0 .. literal.len - 1]) };
                    return value;
                } else {
                    if (std.fmt.parseInt(i64, literal, 10)) |int| {
                        value.* = .{ .integer = int };
                        return value;
                    } else |_| {
                        value.* = .{ .bigInteger = try readBigInteger(allocator, literal) };
                        return value;
                    }
                }
            },
            .float => {
                const literal = token.literal.?;
                const value = try allocator.create(Edn);
                errdefer allocator.destroy(value);
                if (literal[literal.len - 1] == 'M') {
                    var a = try readBigInteger(allocator, literal[0 .. literal.len - 1]);
                    defer a.deinit();
                    var f = try big.Rational.init(allocator);
                    try f.copyInt(a);
                    value.* = .{ .bigFloat = f };
                    return value;
                } else {
                    if (std.fmt.parseFloat(f64, literal)) |float| {
                        value.* = .{ .float = float };
                        return value;
                    } else |err| {
                        return err;
                        // TODO: decide the limits of exact precision floating numbers
                        // var whole_end: usize = 0;
                        // if (literal[0] == '+' or literal[0] == '-')
                        //     whole_end += 1;
                        // while (whole_end < literal.len) : (whole_end += 1) {
                        //     if (literal[whole_end] == '.' or literal[whole_end] == 'e' or literal[whole_end] == 'E')
                        //         break;
                        // }
                        // var frac_end = whole_end;
                        // while (frac_end < literal.len) : (frac_end += 1) {
                        //     if (literal[frac_end] == 'e' or literal[frac_end] == 'E')
                        //         break;
                        // }
                        // // whole_end <= frac_end <= literal.len is true
                        // const whole_part = try readBigInteger(allocator, literal[0..whole_end]);
                        // const frac_part = if (whole_end + 1 < frac_end)
                        //     try readBigInteger(allocator, literal[whole_end + 1 .. frac_end])
                        // else blk: {
                        //     var frac = try big.int.Managed.init(allocator);
                        //     frac.set(0);
                        //     break :blk frac;
                        // };
                        // const exp_part = if (frac_end == literal.len) blk: {
                        //     var exp = try big.int.Managed.init(allocator);
                        //     exp.set(0);
                        //     break :blk exp;
                        // } else try readBigInteger(allocator, literal[frac_end + 1 ..]);
                        // {
                        //     whole_part.dump();
                        //     frac_part.dump();
                        //     exp_part.dump();
                        // }
                        // const frac_size = frac_end - whole_end - 1;
                        
                    }
                    // const value = try allocator.create(Edn);
                }
            },
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
pub fn readBigInteger(allocator: mem.Allocator, buffer: []const u8) !big.int.Managed {
    var v = try big.int.Managed.init(allocator);
    try v.setString(10, buffer);
    std.debug.print("inside {*}\n", .{&v});
    return v;
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
    bigInteger: std.math.big.int.Managed,
    float: f64,
    bigFloat: std.math.big.Rational,
    list: List,
    vector: Vector,
    hashmap: Hashmap,
    hashset: Hashset,
    tag: Tag,
    pub const Character = u21;
    pub const List = std.ArrayList(*const Edn);
    pub const Vector = std.ArrayList(*const Edn);
    pub const Hashmap = std.AutoArrayHashMap(*const Edn, *const Edn);
    pub const Hashset = std.AutoArrayHashMap(*const Edn, *const Edn);

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
            .symbol => {
                try writer.print("{s}", .{value.symbol});
            },
            .keyword => {
                try writer.print(":{s}", .{value.keyword});
            },
            .integer => {
                try writer.print("{d}", .{value.integer});
            },
            .bigInteger => {
                const big_int = value.bigInteger;
                const alloc = big_int.allocator;
                const case: std.fmt.Case = .lower;
                const string_rep = big_int.toString(alloc, 10, case) catch return;
                defer alloc.free(string_rep);
                try writer.print("{s}N", .{string_rep});
            },
            .float => {
                try writer.print("{d}", .{value.float});
            },
            .bigFloat => {
                const big_float = value.bigFloat;
                const num_alloc = big_float.p.allocator;
                const den_alloc = big_float.q.allocator;
                const case: std.fmt.Case = .lower;
                const num_string = big_float.p.toString(num_alloc, 10, case) catch return;
                const den_string = big_float.q.toString(den_alloc, 10, case) catch {
                    num_alloc.free(num_string);
                    return;
                };
                defer num_alloc.free(num_string);
                defer den_alloc.free(den_string);
                if (mem.eql(u8, "1", den_string)) {
                    try writer.print("{s}M", .{num_string});
                } else unreachable;
            },
            .character => {
                try writer.print("\\{u}", .{value.character});
            },
            .string => {
                try writer.print("\"{s}\"", .{value.string});
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
