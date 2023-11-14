// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const ascii = std.ascii;
const expect = std.testing.expect;
const testing = std.testing;
const ArrayList = std.ArrayList;

const Grapheme = @import("ziglyph").Grapheme;
const GraphemeIter = Grapheme.GraphemeIterator;
// https://zig.news/dude_the_builder/unicode-basics-in-zig-dj3
// (try std.unicode.Utf8View.init("stirng")).iterator();

pub fn main() !void {
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
    _ = allocator;
    // {
    //     var utf8 = (try std.unicode.Utf8View.init("😄سليم خطيب")).iterator();
    //     while (utf8.nextCodepointSlice()) |codepoint| {
    //         std.debug.print("got codepoint {any} {0s}\n", .{codepoint});
    //     }
    // }
    // \£ \😄 \u00a3
    // {
    //     var utf8 = (try std.unicode.Utf8View.init("salim")).iterator();
    //     std.debug.print("sss = {any} {0s}\n",.{utf8.nextCodepointSlice().?});
    //     // while (utf8.nextCodepointSlice()) |codepoint| {
    //     //     std.debug.print("got codepoint {any} {0s}\n", .{codepoint});
    //     // }
    // }
    // std.debug.print("\u{0065}\u{0301}", .{});
    // \newline\return \t

    const stdio = std.io.getStdOut().writer();
    // const chutf8 = try std.fmt.parseInt(u21, "00a3", 16);
    // var out = [_]u8{0} ** 3;
    // try stdio.print("d= {}\n", .{try unicode.utf8Encode(chutf8, &out)});
    // try stdio.print("{0any} '{0s}'\n", .{out});
    const s =
        \\ [{(,)},] \é
        \\#_#{,,,  ,
        \\\space,\tab
        \\\u00A3\£
    ;

    {
        std.debug.print("s= {any}\n", .{s.*});
        var grapheme_iter = MyGraphemeIter.init(s);
        var edn_iter = Iterator{ .iter2 = grapheme_iter, .allocator = g_allocator };

        var tok = edn_iter.next2();
        while (tok) |toke| : (tok = edn_iter.next2()) {
            if (toke) |token| {
                defer if (token.literal) |c| {
                    if (token.tag == Tag.character)
                        edn_iter.allocator.free(c);
                };
                try stdio.print("got '{s}' {0any}\n", .{token});
                // defer {if(token.literal) |l| allocator.free(l);}
            } else {
                try stdio.print("got null\n", .{});
                break;
            }
        } else |err| {
            std.debug.print("got err {}\n", .{err});
        }
    }
}
const Iterator = struct {
    buffer: []const u8 = undefined,
    iter2: MyGraphemeIter,
    allocator: std.mem.Allocator = undefined,

    index: usize = 0,
    iter: unicode.Utf8Iterator = undefined,

    const Self = @This();
    const IterError = error{ TaggedNotImplemented, CharacterNull, CharacterShit, PoundError, NotFinished };

    pub fn next2(self: *Iterator) !?Token {
        // std.debug.print("                first char '{s}' {0any}\n", .{self.iter2.peekSlice() orelse "START"});
        // defer std.debug.print("                last char '{s}' {0any}\n", .{self.iter2.peekSlice() orelse "EOF"});

        self.ignoreSeparator();
        const c = self.iter2.nextSlice();
        if (c == null) {
            return null;
        }
        switch (c.?[0]) {
            inline '{', '[', '(', ')', ']', '}' => |del| {
                return Token{ .tag = @field(Tag, &[_]u8{del}), .literal = c.? };
            },
            '#' => {
                const c2 = self.iter2.nextSlice();
                // defer _ = self.iter2.next(); // REPLACE after implementing tagged elements
                if (c2 == null)
                    return IterError.PoundError;
                switch (c2.?[0]) {
                    '{' => {
                        return Token{ .tag = Tag.@"#{", .literal = null };
                    },
                    '_' => {
                        return Token{ .tag = Tag.@"#_", .literal = null };
                    },
                    else => {
                        // TODO: implement tagged elements
                        return IterError.TaggedNotImplemented;
                    },
                }
            },
            '\\' => {
                const character = try self.readCharacterValue();
                errdefer self.allocator.free(character);
                const size = character.len;
                //std.debug.print("aaaa debug c '{s}' {0any} {d}\n", .{ character, size });

                if (size == 0)
                    return IterError.CharacterNull;

                if (std.mem.eql(u8, character, "space")) {
                    defer self.allocator.free(character); // unnecessary defer but used for consistency
                    const literal = try self.allocator.alloc(u8, 1);
                    literal[0] = ' ';
                    return Token{ .tag = Tag.character, .literal = literal };
                }
                if (std.mem.eql(u8, character, "tab")) {
                    defer self.allocator.free(character);
                    const literal = try self.allocator.alloc(u8, 1);
                    literal[0] = '\t';
                    return Token{ .tag = Tag.character, .literal = literal };
                }
                if (std.mem.eql(u8, character, "newline")) {
                    defer self.allocator.free(character);
                    const literal = try self.allocator.alloc(u8, 1);
                    literal[0] = '\n';
                    return Token{ .tag = Tag.character, .literal = literal };
                }
                if (std.mem.eql(u8, character, "return")) {
                    defer self.allocator.free(character);
                    const literal = try self.allocator.alloc(u8, 1);
                    literal[0] = '\r';
                    return Token{ .tag = Tag.character, .literal = literal };
                }
                if (character[0] == 'u' and character.len == 1 + 4) {
                    defer self.allocator.free(character);
                    for (character[1..]) |d| {
                        if (!ascii.isHex(d))
                            return IterError.CharacterShit;
                    } else {
                        const code_point = try std.fmt.parseInt(u21, character[1..], 16);
                        if (!unicode.utf8ValidCodepoint(code_point))
                            return IterError.CharacterShit;
                        const len = try unicode.utf8CodepointSequenceLength(code_point);
                        var out = try self.allocator.alloc(u8, len);
                        if (unicode.utf8Encode(code_point, out)) |count| {
                            if (count != len)
                                return IterError.CharacterShit;
                        } else |err| return err;
                        return Token{ .tag = Tag.character, .literal = out };
                    }
                }

                return Token{ .tag = Tag.character, .literal = character };
            },
            else => {
                std.debug.print("c= '{s}' {0any}\n", .{c.?});
                return IterError.NotFinished;
            },
        }

        return null;
    }
    pub fn ignoreSeparator(self: *Iterator) void {
        while (self.iter2.peekSlice()) |c| : (_ = self.iter2.nextSlice()) {
            if (!isSeparator(c))
                return;
            std.debug.print("ignoring seperator '{0s}' {any}\n", .{c});
        }
    }

    pub fn readCharacterValue(self: *Iterator) ![]const u8 {
        var bytes_arr = std.ArrayList(u8).init(self.allocator);
        if (self.iter2.nextSlice()) |c| {
            try bytes_arr.appendSlice(c);
        } else return error.NoFirstCharacter;

        while (self.iter2.peekSlice()) |c| {
            if (!isSeparator(c) and !isDelimiter(c)) {
                try bytes_arr.appendSlice(c);
                _ = self.iter2.nextSlice();
            } else break;
        }
        return try bytes_arr.toOwnedSlice();
        // // std.debug.print("wwwwwww '{s}' {0any}\n",.{self.iter2.peekSlice().?});
        // var original_i: usize = undefined;
        // if (self.iter2.window) |w| {
        //     original_i = w.offset;
        // } else return "gogogogog";

        // var end_ix = original_i;
        // defer std.debug.print("oi={} ei={}\n", .{ original_i, end_ix });

        // std.debug.print("------------reading '{s}' {0any}\n",.{self.iter2.nextSlice().?});
        // // consume first character
        // end_ix += if(self.iter2.nextSlice()) |s| s.len else 0;
        // while (self.iter2.peekSlice()) |c| {
        //     std.debug.print("------------reading '{s}' {0any}\n",.{c});
        //     if (!isSeparator(c) and !isDelimiter(c))
        //         end_ix += c.len
        //     else
        //         break;
        //     // advance iterator
        //     _ = self.iter2.next();
        //     // self.iter2.i += c.len;
        // } else return self.iter2.bytes[original_i..];
        // return self.iter2.bytes[original_i .. end_ix + 1];
    }
    pub fn isDelimiter(c: []const u8) bool {
        return std.mem.eql(u8, c, "{") or
            std.mem.eql(u8, c, "}") or
            std.mem.eql(u8, c, "[") or
            std.mem.eql(u8, c, "]") or
            std.mem.eql(u8, c, "(") or
            std.mem.eql(u8, c, ")") or
            std.mem.eql(u8, c, "#") or
            std.mem.eql(u8, c, "\\") or
            std.mem.eql(u8, c, "\"");
    }
    pub fn isSeparator(c: []const u8) bool {
        if (c.len != 1)
            return false;
        const ascii_c = c[0];
        // .{32, 9, 10, 13, control_code.vt, control_code.ff}
        // 10 0x0a \n, 13 0x0d \r
        return ascii.isASCII(ascii_c) and (ascii.isWhitespace(ascii_c) or ascii_c == ',');
    }

    /// return zero length if there is nothing to peek at
    pub fn peek2(self: *Iterator) ?[]const u8 {
        return self.iter2.peekSlice();
    }
    pub fn consumeDigit(self: *Iterator) bool {
        const c = self.iter.peek(1);
        if (c) |d| {
            if (ascii.isDigit(d)) {
                _ = self.iter.nextCodepoint();
                return true;
            } else return false;
        } else return false;
    }
    // --------------------- OLD IMPLEMENTATION -----------------------

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
/// implement peek for Grapheme.GraphemeIterator
/// iterator has two main functions nextSlice,peekSlice with the following property:
/// const c1 = self.peek();
/// const c2 = self.next();
/// std.mem.eql(u8,c1,c2)
const MyGraphemeIter = struct {
    // buffer: [2]?Grapheme = [_]?Grapheme{null,null}, // first is the current Grapheme
    window: ?Grapheme = null,
    iter: Grapheme.GraphemeIterator,
    bytes: []const u8,
    // assume valid utf8 str
    pub fn init(str: []const u8) MyGraphemeIter {
        var iter = GraphemeIter.init(str);
        var self = MyGraphemeIter{ .iter = iter, .bytes = str };
        self.window = self.iter.next();
        return self;
    }
    pub fn peek(self: MyGraphemeIter) ?Grapheme {
        return self.window;
    }
    pub fn peekSlice(self: MyGraphemeIter) ?[]const u8 {
        if (self.window) |window| {
            return Grapheme.slice(window, self.bytes);
        } else return null;
    }
    pub fn next(self: *MyGraphemeIter) ?Grapheme {
        var next_g = self.iter.next();
        
        defer self.window = next_g;
        return self.peek();
    }
    pub fn nextSlice(self: *MyGraphemeIter) ?[]const u8 {
        var next_g = self.iter.next();
        defer self.window = next_g;
        return self.peekSlice();
    }
};
pub fn debugMyGraphemeIter(s: []const u8) void {
    var grapheme_iter = MyGraphemeIter.init(s);
    while (grapheme_iter.peekSlice()) |token| {
        const c = grapheme_iter.nextSlice();
        std.debug.print("p='{s}' c='{s}'\n", .{ token, c orelse "END OF FILE" });
    } else {
        std.debug.print("reached end\n", .{});
    }
}

const Token = struct {
    tag: Tag,
    literal: ?[]const u8 = null,

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
                try writer.writeAll("character '");
                if (value.literal) |c| {
                    if (c.len == 1) {
                        switch (c[0]) {
                            '\t' => try writer.writeAll("\\tab"),
                            '\n' => try writer.writeAll("\\newline"),
                            '\r' => try writer.writeAll("\\return"),
                            ' ' => try writer.writeAll("\\space"),
                            else => {},
                        }
                    } else {
                        try writer.writeAll("\\");
                        try writer.writeAll(c);
                    }
                } else try writer.writeAll("null");
                try writer.writeAll("'");
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
