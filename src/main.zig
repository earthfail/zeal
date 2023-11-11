const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const ascii = std.ascii;
const expect = std.testing.expect;
const testing = std.testing;
const ArrayList = std.ArrayList;
// https://zig.news/dude_the_builder/unicode-basics-in-zig-dj3
// (try std.unicode.Utf8View.init("stirng")).iterator();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch @panic("leaked");
    }
    _ = allocator;
    {
        var utf8 = (try std.unicode.Utf8View.init("سليم خطيب")).iterator();
        while (utf8.nextCodepointSlice()) |codepoint| {
            std.debug.print("got codepoint {any} {0s}\n", .{codepoint});
        }
    }
    var utf8 = (try std.unicode.Utf8View.init("[")).iterator();
    var utf82 = Iterator{ .iter = utf8 };
    const token = utf82.next2();

    std.debug.print("{0?s} '{0?any}'\n", .{token});

    // const list = [_]u8{' ','\t','\n','\r',','};
    // for(list,0..) |v,i|{
    //     std.debug.print("i={} v={1d} v='{1u}'\n",.{i,v});
    //     if(!ascii.isWhitespace(v)){
    //         // std.debug.print("fuckfuckfuckfuck\n",.{});
    //         return error.notWhiteSpace;
    //     }
    // }

    // var it: Iterator = Iterator{ .buffer = "\\tab" };
    // const s = it.next();
    // std.debug.print("{?s} and i={d}\n", .{ s, it.index });

    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}

const Iterator = struct {
    buffer: []const u8 = undefined,
    index: usize = 0,
    iter: unicode.Utf8Iterator,
    //allocator: std.mem.Allocator,
    const Self = @This();

    pub fn next2(self: *Iterator) ?Token {
        self.ignoreSeparator();

        const c = self.iter.nextCodepoint();
        if (c == null) {
            return null;
        }
        switch (c.?) {
            inline '{', '[', '(', ')', ']', '}' => |del| {
                return Token{ .tag = @field(Tag, &[_]u8{del}), .literal = &[1]Character{del} };
            },
            '#' => {
                const c2 = self.peek2();
                if (c == null)
                    return null;
                switch (c2.?) {
                    '{' => {
                        _ = self.iter.nextCodepoint();
                        return Token{ .tag = Tag.@"#{", .literal = null };
                    },
                    '_' => {
                        _ = self.iter.nextCodepoint();
                        return Token{ .tag = Tag.@"#_", .literal = null };
                    },
                    else => {
                        // TODO: implement tagged elements
                        return null;
                    },
                }
            },
            '\\' => {
                const c2 = self.iter.nextCodepoint();
                if(c2 == null)
                    return null;
                // if(self.peek2() == null)
            },
            else => return null,
        }

        return null;
    }
    pub fn ignoreSeparator(self: *Iterator) void {
        var c = self.peek2();
        while (c != null and isSeparator(c.?)) : (c = self.iter.nextCodepoint()) {}
    }
    pub fn isSeparator(c: Character) bool {
        const ascii_c = @as(u8, @intCast(c));
        // .{32, 9, 10, 13, control_code.vt, control_code.ff}
        return ascii.isASCII(ascii_c) and (ascii.isWhitespace(ascii_c) or ascii_c == ',');
    }
    pub fn reset2(self: *Iterator) void {
        self.iter.i = 0;
    }
    pub fn peek2(self: *Iterator) ?Character {
        const i = self.iter.i;
        const c = self.iter.nextCodepoint();
        self.iter.i = i;
        return c;
    }
    pub fn next(self: *Self) ?[]const u8 {
        if (self.index >= self.buffer.len) return null;
        const c = self.buffer[self.index];
        const index = self.index;
        return switch (c) {
            '{', '[', '(', ')', ']', '}' => blk: {
                self.index += 1;
                break :blk self.buffer[index .. index + 1];
            },
            '\\' => self.consume_character(),

            else => blk: {
                self.index += 1;
                break :blk null;
            },
        };
    }
    pub fn peek(self: *Self) ?[]const u8 {
        _ = self;
        return null;
    }

    pub fn reset(self: *Self) void {
        self.index = 0;
    }
    // ---------------- PRIVATE PROCEDURES ----------------
    pub fn peek_ch(self: Self) ?u8 {
        const index = self.index;
        if (index < self.buffer.len - 1)
            return self.buffer[index + 1]
        else {
            return null;
        }
    }
    pub fn consume_character(self: *Self) ?[]const u8 {
        const index = self.index;
        var i = index;

        if (self.buffer[i] != '\\') {
            return null;
        } else {
            i += 1;
        }
        while (i < self.buffer.len and !ascii.isWhitespace(self.buffer[i])) : (i += 1) {}
        const character = self.buffer[index + 1 .. i];
        defer self.index = i;

        if (character.len == 0) {
            return null;
        } else if (character.len == 1) {
            return character;
        } else if (character[0] == 'u' and character.len == 5) {
            return "[UNICODE]";
        } else {
            if (mem.eql(u8, character, "newline")) {
                return "\n";
            } else if (mem.eql(u8, character, "return")) {
                return "\r";
            } else if (mem.eql(u8, character, "space")) {
                return " ";
            } else if (mem.eql(u8, character, "tab")) {
                return "\t";
            } else return "UNSUPPORTED CHARACTER";
        }
    }
};
const Tag = enum {
    @"{",
    @"}",
    @"(",
    @")",
    @"[",
    @"]",
    @"#{",
    @"#_",
    // tag, // TODO: IMPLEMENT TAGGED ELEMENTS
    nil,
    boolean,
    string,
    character,
    symbol,
    keyword,
    integer,
    float,
};
const Token = struct {
    tag: Tag,
    literal: ?[]const Character = null,

    pub fn format(value: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (value.tag) {
            .@"{" => try writer.writeAll("{"),
            .@"}" => try writer.writeAll("}"),
            .@"(" => try writer.writeAll("("),
            .@")" => try writer.writeAll(")"),
            .@"[" => try writer.writeAll("["),
            .@"]" => try writer.writeAll("]"),
            .@"#{" => try writer.writeAll("#{"),
            .@"#_" => try writer.writeAll("#_"),
            .nil => try writer.writeAll("nil"),
            .boolean => {
                try writer.writeAll("boolean");
                try writer.writeAll("null bool");
            },
            .string => {
                try writer.writeAll("string");
                try writer.writeAll("null string");
            },
            .character => {
                try writer.writeAll("character bitch");
                try writer.writeAll("null character");
            },
            .symbol => {
                try writer.writeAll("symbol");
                try writer.writeAll("null symbol");
            },
            .keyword => {
                try writer.writeAll("keyword");
                try writer.writeAll("null keyword");
            },
            .integer => {
                try writer.writeAll("int");
                try writer.writeAll("null integer");
            },
            .float => {
                try writer.writeAll("float");
                try writer.writeAll("null float");
            },
            // else => return error.CompilerisShitting,
        }
        return;
    }
};
const Character = u21;
const Edn = union(enum) {
    nil: null,
    boolean: bool,
    string: [:0]const u8,
    character: Character,

    symbol: Symbol,
    keyword: Keyword,

    integer: i64,
    float: f64,

    list: std.ArrayList(Edn),
    hashmap: std.AutoArrayHashMap(Edn, Edn),

    const Symbol = struct {
        namespace: ?[:0]const u8,
        name: [:0]const u8,
    };
    const Keyword = struct {
        namespace: ?[:0]const u8,
        name: [:0]const u8,
    };
};

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
