// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228

const std = @import("std");
const mem = std.mem;
// const log = std.log;
const unicode = std.unicode;
const ascii = std.ascii;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

// pub const std_options = struct {
//     // Set the log level to info
//     pub const log_level = .warn;

//     // Define logFn to override the std implementation
//     // pub const logFn = myLogFn;
// };
// const lexer_log = std.log.scoped(.lexer);

const ziglyph = @import("ziglyph");
const Grapheme = ziglyph.Grapheme;
const GraphemeIter = Grapheme.GraphemeIterator;
// https://zig.news/dude_the_builder/unicode-basics-in-zig-dj3
// (try std.unicode.Utf8View.init("string")).iterator();
pub fn lexString(g_allocator: mem.Allocator, s: []const u8) !void {
    std.debug.print("s={any}\n", .{s.ptr});
    const stdio = std.io.getStdOut().writer();

    var edn_iter = Iterator.init(g_allocator, s);
    while (edn_iter.next()) |token| {
        defer token.deinit(g_allocator);
        // defer if (token.literal) |c| {
        //     if (token.tag == Tag.character or token.tag == Tag.string or token.tag == Tag.symbol or token.tag == Tag.integer or token.tag == Tag.float)
        //         edn_iter.allocator.free(c);
        // };
        try stdio.print("got '{s}' {}\n", .{ token, token.tag });
    } else {
        try stdio.print("got null\n", .{});
    }
}

pub const Iterator = struct {
    iter: MyGraphemeIter,
    allocator: mem.Allocator = undefined,
    window: ?Token = undefined,

    const Self = @This();
    const IterError = error{ CharacterNull, InvalidCharacter, StringErr, SymbolErr, CharacterErr, PoundErr, KeywordErr, NotFinished };
    pub fn init(allocator: mem.Allocator, str: []const u8) Iterator {
        var iter = MyGraphemeIter.init(str);
        var self = Iterator{ .allocator = allocator, .iter = iter };
        self.window = self.next2() catch null;
        return self;
    }
    pub fn deinit(self: *Self) void {
        if (self.window) |*window| {
            window.deinit(self.allocator);
        }
    }
    pub fn peek(self: Iterator) ?Token {
        return self.window;
    }
    pub fn next(self: *Iterator) ?Token {
        const next_token = self.next2();
        defer self.window = next_token catch null;
        return self.window;
    }
    pub fn next2(self: *Iterator) !?Token {
        self.ignoreSeparator();
        const c = self.iter.peekSlice();
        if (c == null) {
            return null;
        }
        // std.debug.print("-----------------------------{} --- {}\n", .{ @intFromPtr(c.?.ptr), @intFromPtr(self.iter.bytes.ptr) });
        switch (c.?[0]) {
            inline '{', '[', '(', ')', ']', '}' => |del| {
                _ = self.iter.nextSlice();
                return Token{ .tag = @field(Tag, &[_]u8{del}), .literal = c.? };
            },
            '#' => {
                _ = self.iter.nextSlice();
                const c2 = self.iter.peekSlice();
                // defer _ = self.iter.next(); // REPLACE after implementing tagged elements
                if (c2 == null)
                    return IterError.PoundErr;
                switch (c2.?[0]) {
                    '{' => {
                        _ = self.iter.nextSlice();
                        return Token{ .tag = Tag.@"#{", .literal = null };
                    },
                    '_' => {
                        _ = self.iter.nextSlice();
                        return Token{ .tag = Tag.@"#_", .literal = null };
                    },
                    else => {
                        const tag = self.readSymbol() catch return IterError.PoundErr;
                        return Token{ .tag = Tag.tag, .literal = tag };
                    },
                }
            },
            '\\' => {
                _ = self.iter.nextSlice();
                const character = try self.readCharacterValue();
                errdefer self.allocator.free(character);
                const size = character.len;
                //std.debug.print("aaaa debug c '{s}' {0any} {d}\n", .{ character, size });

                if (size == 0)
                    return IterError.CharacterNull;
                const names = [_][]const u8{ "space", "tab", "newline", "return" };
                const chars = [_]u8{ ' ', '\t', '\n', '\r' };
                inline for (names, chars) |name, char| {
                    if (mem.eql(u8, character, name)) {
                        defer self.allocator.free(character); // unnecessary defer but used for consistency
                        const literal = try self.allocator.alloc(u8, 1);
                        literal[0] = char;
                        return Token{ .tag = Tag.character, .literal = literal };
                    }
                }
                if (character[0] == 'u') {
                    if (character.len != 1 + 4)
                        return IterError.InvalidCharacter;
                    for (character[1..]) |d| {
                        if (!ascii.isHex(d))
                            return IterError.InvalidCharacter;
                    } else {
                        const code_point = try std.fmt.parseInt(u21, character[1..], 16);
                        if (!unicode.utf8ValidCodepoint(code_point))
                            return IterError.InvalidCharacter;
                        const len = try unicode.utf8CodepointSequenceLength(code_point);
                        var out = try self.allocator.alloc(u8, len);
                        if (unicode.utf8Encode(code_point, out)) |count| {
                            if (count != len)
                                return IterError.InvalidCharacter;
                        } else |err| return err;

                        self.allocator.free(character);
                        return Token{ .tag = Tag.character, .literal = out };
                    }
                }
                var iter_char = MyGraphemeIter.init(character);
                _ = iter_char.nextSlice();
                if (iter_char.nextSlice()) |c2| {
                    if (!isSeparator(c2) and !isDelimiter(c2))
                        return IterError.InvalidCharacter;
                }
                return Token{ .tag = Tag.character, .literal = character };
            },
            ':' => {
                _ = self.iter.nextSlice();
                const keyword = self.readSymbol() catch return IterError.KeywordErr;
                return Token{ .tag = Tag.keyword, .literal = keyword };
            },
            '\"' => {
                _ = self.iter.nextSlice();
                const string = try self.readString();
                // std.debug.print("aaaa debug string '{s}' {0any}\n", .{ string});
                return Token{ .tag = Tag.string, .literal = string };
            },
            else => {
                var is_digit: bool = digit: {
                    var iter = self.iter; // copy iterator
                    const s = iter.nextSlice();
                    // std.debug.print("{any}\n",.{s});
                    assert(s != null); // guaranteed by switch first if statement
                    const c1 = firstCodePoint(s.?);
                    if (ziglyph.isAsciiDigit(c1))
                        break :digit true;
                    if ('+' == c1 or '-' == c1) {
                        if (iter.nextSlice()) |c2| {
                            // if (ziglyph.isAsciiDigit(try unicode.utf8Decode(c2)))
                            if (ziglyph.isAsciiDigit(firstCodePoint(c2)))
                                break :digit true;
                        }
                    }
                    break :digit false;
                };
                if (is_digit) {
                    // std.debug.print("c= '{s}' {0any}\n", .{c.?});
                    return try self.readNumber();
                } else {
                    // std.debug.print("c= '{s}' {0any}\n", .{c.?});
                    const symbol = try self.readSymbol();
                    // std.debug.print("sssssss '{s}'\n", .{symbol});
                    return Token{ .tag = Tag.symbol, .literal = symbol };
                }
            },
        }

        return null;
    }
    pub fn ignoreSeparator(self: *Iterator) void {
        while (self.iter.peekSlice()) |c| : (_ = self.iter.nextSlice()) {
            if (isSeparator(c)) {
                continue;
            } else if (mem.eql(u8, c, ";")) {
                while (self.iter.nextSlice()) |comment| {
                    if (mem.eql(u8, comment, "\n"))
                        break;
                }
            } else break;
            // std.debug.print("________________________________________________ignoring seperator '{0s}' {any}\n", .{c});
        }
    }
    pub fn readNumber(self: *Iterator) !Token {
        var output = ArrayList(u8).init(self.allocator);
        errdefer output.deinit();
        // if (self.iter.peekSlice()) |prefix| {
        //     const c1 = firstCodePoint(prefix);
        //     if ('-' == c1) {
        //         _ = self.iter.nextSlice();
        //         try output.appendSlice(prefix);
        //     }
        //     if ('+' == c1) {
        //         _ = self.iter.nextSlice();
        //     }
        // } else unreachable; // guaranteed by predicates in switch statement
        // decided to replace code above with slightly less optimal code to improve clarity
        try self.readSign(&output);
        if (self.iter.nextSlice()) |digit| {
            const c1 = firstCodePoint(digit);
            if ('0' == c1) {
                if (self.iter.peekSlice()) |digit2| {
                    const c2 = firstCodePoint(digit2);
                    if (ziglyph.isAsciiDigit(c2))
                        return error.zeroPrefixNum;
                }
            }
            try output.appendSlice(digit);
        }
        // read int
        try self.readDigits(&output);
        // I will ignore exact precision for floating point number and arbitrary precision for integers
        if (self.iter.peekSlice()) |differentiator| {
            const c = firstCodePoint(differentiator);
            switch (c) {
                'N' => {
                    try output.appendSlice(self.iter.nextSlice().?);
                    if (self.iter.peekSlice() == null or isSeparator(self.iter.peekSlice().?)) {
                        return .{ .literal = try output.toOwnedSlice(), .tag = Tag.integer };
                    } else return error.InvalidNumber;
                },
                'M' => {
                    try output.appendSlice(self.iter.nextSlice().?);
                    if (self.iter.peekSlice() == null or isSeparator(self.iter.peekSlice().?)) {
                        return .{ .literal = try output.toOwnedSlice(), .tag = Tag.float };
                    } else return error.InvalidNumber;
                },
                else => {
                    if (isSeparator(differentiator) or isDelimiter(differentiator))
                        return .{ .tag = Tag.integer, .literal = try output.toOwnedSlice() };
                    var fract = false;
                    var exp = false;
                    if ('.' == c) { // fraction part
                        _ = self.iter.nextSlice();
                        try output.appendSlice(differentiator);
                        try self.readDigits(&output);
                        fract = true;
                    }
                    if (self.iter.peekSlice() == null) {
                        return .{ .literal = try output.toOwnedSlice(), .tag = Tag.float };
                    }
                    const c2 = firstCodePoint(self.iter.peekSlice().?);
                    if ('e' == c2 or 'E' == c2) {
                        try output.appendSlice(self.iter.nextSlice().?);
                        if (self.iter.peekSlice()) |d| {
                            const d1 = firstCodePoint(d);
                            if (ziglyph.isAsciiDigit(d1) or '-' == d1 or '+' == d1) {
                                try self.readSign(&output);
                                try self.readDigits(&output);
                                exp = true;
                            } else return error.InvalidNumber;
                        }
                    }
                    if (fract or exp) {
                        if (self.iter.peekSlice() == null or isSeparator(self.iter.peekSlice().?) or isDelimiter(self.iter.peekSlice().?)) {
                            return .{ .literal = try output.toOwnedSlice(), .tag = Tag.float };
                        } else return error.InvalidNumber;
                    } else return error.FloatErr;
                },
            }
        } else return .{ .literal = try output.toOwnedSlice(), .tag = Tag.integer };
    }

    pub fn readCharacterValue(self: *Iterator) ![]const u8 {
        var bytes_arr = std.ArrayList(u8).init(self.allocator);
        if (self.iter.nextSlice()) |c| {
            try bytes_arr.appendSlice(c);
        } else return error.NoFirstCharacter;

        while (self.iter.peekSlice()) |c| {
            if (!isSeparator(c) and !isDelimiter(c)) {
                try bytes_arr.appendSlice(c);
                _ = self.iter.nextSlice();
            } else break;
        }
        return try bytes_arr.toOwnedSlice();
        // // std.debug.print("wwwwwww '{s}' {0any}\n",.{self.iter.peekSlice().?});
        // var original_i: usize = undefined;
        // if (self.iter.window) |w| {
        //     original_i = w.offset;
        // } else return "gogogogog";

        // var end_ix = original_i;
        // defer std.debug.print("oi={} ei={}\n", .{ original_i, end_ix });

        // std.debug.print("------------reading '{s}' {0any}\n",.{self.iter.nextSlice().?});
        // // consume first character
        // end_ix += if(self.iter.nextSlice()) |s| s.len else 0;
        // while (self.iter.peekSlice()) |c| {
        //     std.debug.print("------------reading '{s}' {0any}\n",.{c});
        //     if (!isSeparator(c) and !isDelimiter(c))
        //         end_ix += c.len
        //     else
        //         break;
        //     // advance iterator
        //     _ = self.iter.next();
        //     // self.iter.i += c.len;
        // } else return self.iter.bytes[original_i..];
        // return self.iter.bytes[original_i .. end_ix + 1];
    }
    pub fn readString(self: *Iterator) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        while (self.iter.nextSlice()) |c| {
            if (mem.eql(u8, c, "\""))
                break;
            if (mem.eql(u8, c, "\\")) {
                if (self.iter.nextSlice()) |quoted| {
                    if (mem.eql(u8, quoted, "t")) {
                        try output.append('\t');
                    } else if (mem.eql(u8, quoted, "r")) {
                        try output.append('\r');
                    } else if (mem.eql(u8, quoted, "n")) {
                        try output.append('\n');
                    } else if (mem.eql(u8, quoted, "\\")) {
                        try output.append('\\');
                    } else if (mem.eql(u8, quoted, "\"")) {
                        try output.append('\"');
                    } else return IterError.StringErr;
                    continue;
                } else return IterError.StringErr;
            }
            try output.appendSlice(c);
        } else return IterError.StringErr;
        return try output.toOwnedSlice();
    }
    /// I could also read whole symbol then validate it. Maybe I will try it in another function.
    /// But the iterface for parsing it cumbersome so I erred on the side of caution
    /// or I could copy the iterator to simplified validation. In later commits WTWOG (with the will of God)
    pub fn readSymbol(self: *Iterator) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        var encountered_slash = false;
        var empty_prefix = false;
        errdefer output.deinit();

        if (self.iter.nextSlice()) |first| {
            assert(!isSeparator(first)); // guaranteed by the next2 function

            // const firstu21 = try unicode.utf8Decode(first);
            const firstu21 = firstCodePoint(first);
            if (ziglyph.isNumber(firstu21))
                return IterError.SymbolErr;
            if (!ziglyph.isAlphaNum(firstu21) and !isSymbolSpecialCharacter(firstu21) and !('/' == firstu21))
                return IterError.SymbolErr;
            // return error.e1;
            if ('/' == firstu21) {
                empty_prefix = true;
                encountered_slash = true;
            }
            try output.appendSlice(first);
            if (mem.eql(u8, first, ".") or mem.eql(u8, first, "-") or mem.eql(u8, first, "+")) {
                if (self.iter.peekSlice()) |second| {
                    // if (ziglyph.isNumber(try unicode.utf8Decode(second)))
                    if (ziglyph.isNumber(firstCodePoint(second)))
                        return IterError.SymbolErr;
                } else return try output.toOwnedSlice();
            }
        } else unreachable; // guaranteed by the next2 function

        // check empty prefix and not empty name
        if (self.iter.peekSlice()) |c| {
            if (!isSeparator(c)) {
                if (empty_prefix and encountered_slash)
                    return error.SymbolEmptyPrefix;
            }
        }
        while (self.iter.peekSlice()) |c| {
            // std.debug.print("getting c='{s}'\n", .{c});
            // const cu21 = try unicode.utf8Decode(c);
            const cu21 = firstCodePoint(c);
            // std.debug.print("c in u21 is '{d}'\n", .{cu21});
            if (ziglyph.isAlphaNum(cu21) or isSymbolSpecialCharacter(cu21) or isKeywordTagDelimiter(cu21)) {
                _ = self.iter.nextSlice(); // consume c
                try output.appendSlice(c);
                continue;
            } else if ('/' == cu21) {
                if (encountered_slash)
                    return IterError.SymbolErr;
                encountered_slash = true;

                _ = self.iter.nextSlice(); // consume /
                try output.appendSlice(c); // "/" == c
                // check first character of name
                if (self.iter.nextSlice()) |first| {
                    if (isSeparator(first))
                        return IterError.SymbolErr; // name should not be empty
                    // const firstu21 = try unicode.utf8Decode(first);
                    const firstu21 = firstCodePoint(first);
                    if (ziglyph.isNumber(firstu21))
                        return IterError.SymbolErr;
                    if (!ziglyph.isAlphaNum(firstu21) and !isSymbolSpecialCharacter(firstu21))
                        return IterError.SymbolErr;

                    try output.appendSlice(first);
                    if (mem.eql(u8, first, ".") or mem.eql(u8, first, "-") or mem.eql(u8, first, "+")) {
                        if (self.iter.peekSlice()) |second| {
                            // if (ziglyph.isNumber(try unicode.utf8Decode(second)))
                            if (ziglyph.isNumber(firstCodePoint(second)))
                                return IterError.SymbolErr;
                        } else {
                            assert(!empty_prefix); // guarantees that it is a valid symbol
                            return try output.toOwnedSlice();
                        }
                    }
                } else return error.SymbolEmptyName; // name should not be empty

            } else {
                // here c is not # or :
                if (isSeparator(c) or isDelimiter(c)) {
                    break;
                } else return IterError.SymbolErr;
            }
        }

        return try output.toOwnedSlice();
    }

    /// check the special character that a symbol can contain other than the alphanumberic
    fn isSymbolSpecialCharacter(c: u21) bool {
        const c_ascii = @as(u8, @intCast(c));
        return switch (c_ascii) {
            '.', '*', '+', '!', '-', '_', '?', '$', '%', '&', '=', '<', '>' => true,
            else => false,
        };
    }
    fn isKeywordTagDelimiter(c: u21) bool {
        const c_ascii = @as(u8, @intCast(c));
        return c_ascii == ':' or c_ascii == '#';
    }
    fn isDelimiter(c: []const u8) bool {
        return mem.eql(u8, c, "{") or
            mem.eql(u8, c, "}") or
            mem.eql(u8, c, "[") or
            mem.eql(u8, c, "]") or
            mem.eql(u8, c, "(") or
            mem.eql(u8, c, ")") or
            mem.eql(u8, c, "#") or
            mem.eql(u8, c, "\\") or
            mem.eql(u8, c, "\"");
    }
    fn isSeparator(c: []const u8) bool {
        if (c.len != 1)
            return false;
        const ascii_c = c[0];
        // .{32, 9, 10, 13, control_code.vt, control_code.ff}
        // 10 0x0a \n, 13 0x0d \r
        return ascii.isASCII(ascii_c) and (ascii.isWhitespace(ascii_c) or ascii_c == ',');
    }
    pub fn firstCodePoint(c: []const u8) u21 {
        var fis = std.io.fixedBufferStream(c);
        const reader = fis.reader();
        const code_point = ziglyph.readCodePoint(reader) catch unreachable;
        return code_point.?;
    }
    pub fn readSign(self: *Iterator, output: *ArrayList(u8)) !void {
        if (self.iter.peekSlice()) |prefix| {
            const c1 = firstCodePoint(prefix);
            if ('-' == c1) {
                _ = self.iter.nextSlice();
                try output.appendSlice(prefix);
            }
            if ('+' == c1) {
                _ = self.iter.nextSlice();
            }
        }
    }
    pub fn readDigits(self: *Iterator, output: *ArrayList(u8)) !void {
        while (self.iter.peekSlice()) |digit| {
            const code_point = firstCodePoint(digit);
            if (ziglyph.isAsciiDigit(code_point)) {
                _ = self.iter.nextSlice();
                try output.appendSlice(digit);
            } else break;
        } else {
            return;
        }
    }
};
/// implement peek for Grapheme.GraphemeIterator
/// iterator has two main functions nextSlice,peekSlice with the following properties:
/// const c1 = self.peek();
/// const c2 = self.next();
/// std.mem.eql(u8,c1,c2)
/// and self.peek is idempotent
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
fn debugMyGraphemeIter(s: []const u8) void {
    var grapheme_iter = MyGraphemeIter.init(s);
    while (grapheme_iter.peekSlice()) |token| {
        const c = grapheme_iter.nextSlice();
        std.debug.print("p='{s}' c='{s}'\n", .{ token, c orelse "END OF FILE" });
    } else {
        std.debug.print("reached end\n", .{});
    }
}

pub const Token = struct {
    tag: Tag,
    literal: ?[]const u8 = null,
    pub fn deinit(self: *const Token, allocator: mem.Allocator) void {
        if (self.literal) |c| {
            switch (self.tag) {
                .character, .string, .symbol, .integer, .float, .keyword, .tag => {
                    allocator.free(c);
                },
                else => {},
            }
        }
    }
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
            // .nil => try writer.writeAll("nil"),
            // .boolean => {
            //     if (value.literal) |b| {
            //         try writer.writeAll(b);
            //     } else try writer.writeAll("null bool");
            // },
            .string => {
                if (value.literal) |s| {
                    try writer.writeAll("\"");
                    try writer.writeAll(s);
                    try writer.writeAll("\"");
                } else try writer.writeAll("null string");
            },
            .character => {
                // try writer.writeAll("character '");
                if (value.literal) |c| {
                    if (c.len == 1) {
                        switch (c[0]) {
                            '\t' => try writer.writeAll("\\tab"),
                            '\n' => try writer.writeAll("\\newline"),
                            '\r' => try writer.writeAll("\\return"),
                            ' ' => try writer.writeAll("\\space"),
                            else => {
                                try writer.writeAll("\\");
                                try writer.writeAll(c);
                            },
                        }
                    } else {
                        try writer.writeAll("\\");
                        try writer.writeAll(c);
                    }
                } else try writer.writeAll("null character");
                // try writer.writeAll("'");
            },
            .symbol => {
                // try writer.writeAll("symbol");
                if (value.literal) |sym| {
                    // try writer.writeAll("'");
                    try writer.writeAll(sym);
                } else try writer.writeAll("null symbol");
            },
            .keyword => {
                // try writer.writeAll("keyword");
                if (value.literal) |key| {
                    try writer.writeAll(":");
                    try writer.writeAll(key);
                } else try writer.writeAll("null keyword");
            },
            .tag => {
                // try writer.writeAll("tag");
                if (value.literal) |t| {
                    try writer.writeAll("#");
                    try writer.writeAll(t);
                } else try writer.writeAll("null tag");
            },
            .integer => {
                // try writer.writeAll("int");
                if (value.literal) |i| {
                    try writer.print("{s}", .{i});
                } else try writer.writeAll("null integer");
            },
            .float => {
                // try writer.writeAll("float");
                if (value.literal) |i| {
                    try writer.print("{s}", .{i});
                } else try writer.writeAll("null float");
            },
        }
        return;
    }
};
pub const Tag = enum {
    @"{",
    @"}",
    @"(",
    @")",
    @"[",
    @"]",
    @"#{",
    @"#_",
    tag,
    // nil,
    // boolean,
    string,
    character,
    symbol,
    keyword,
    integer,
    float,
};

test "test characters and strings" {
    const s_arr = [_][]const u8{
        \\ [{(,)},] \é
        \\#_#{,,,  ,
        \\\space,\tab
        \\\u00A3\£
        ,
        \\  "salim"
        \\,"£ \\\t\\ money 😄"
        \\"","okay\nnow" "finé"
        \\"history\r\nis written by the\n just"
        ,
    };
    const expected_arr = [_][]const u8{
        "[ { ( ) } ] \\é #_ #{ \\space \\tab \\£ \\£ ",
        "\"salim\" \"£ \\\t\\ money 😄\" \"\" \"okay\nnow\" \"finé\" \"history\r\nis written by the\n just\" ",
    };
    for (s_arr, expected_arr) |s, expected_buffer| {
        var buffer: [255]u8 = undefined;

        var fbs = std.io.fixedBufferStream(&buffer);
        var fbsw = fbs.writer();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        var iterator = try Iterator.init(arena.allocator(), s);
        var tok = iterator.next();
        while (tok) |toke| : (tok = iterator.next()) {
            if (toke) |token| {
                defer if (token.literal) |c| {
                    if (token.tag == Tag.character or token.tag == Tag.string or token.tag == Tag.symbol or token.tag == Tag.tag)
                        iterator.allocator.free(c);
                };
                try fbsw.print("{s} ", .{token});
                // defer {if(token.literal) |l| allocator.free(l);}
            } else {
                // try fbsw.print("got null\n", .{});
                break;
            }
        } else |err| {
            try fbsw.print("err {}\n", .{err});
        }

        testing.expect(mem.eql(u8, fbs.getWritten(), expected_buffer)) catch {
            std.debug.print("****************************************************************output didn't mean the expectations\n", .{});
            std.debug.print("output: {s}\n", .{fbs.getWritten()});
            std.debug.print("expect: {s}\n", .{expected_buffer});
        };
    }
}
test "test symbols" {
    const inputs = [_][]const u8{
        "é",
        \\a/khatib / finé
        ,
        \\salim
        ,
    };
    const expectations = [_][]const u8{
        "é ",
        \\a/khatib / finé 
        ,
        \\salim 
        ,
    };
    for (inputs, expectations) |in, exp| {
        var buffer: [255]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        var fbsw = fbs.writer();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        var iterator = try Iterator.init(arena.allocator(), in);
        var tok = iterator.next();
        while (tok) |toke| : (tok = iterator.next()) {
            if (toke) |token| {
                defer if (token.literal) |c| {
                    if (token.tag == Tag.character or token.tag == Tag.string or token.tag == Tag.symbol or token.tag == Tag.tag)
                        iterator.allocator.free(c);
                };
                try fbsw.print("{s} ", .{token});
            } else break;
        } else |err| {
            try fbsw.print("err {}\n", .{err});
        }
        testing.expect(mem.eql(u8, fbs.getWritten(), exp)) catch {
            std.debug.print("****************************************************************output didn't mean the expectations\n", .{});
            std.debug.print("output: {s}\n", .{fbs.getWritten()});
            std.debug.print("expect: {s}\n", .{exp});
        };
    }
}
// fn foo(x: i32) i32 {
//         std.debug.print("fakdsjflajdflkasjdflajdflk\n",.{});
//         return x+1;
//     }
// test "testing debug" {
//     try testing.expect(foo(1) == 1+1);
// }
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

// const chutf8 = try std.fmt.parseInt(u21, "00a3", 16);
// var out = [_]u8{0} ** 3;
// try stdio.print("d= {}\n", .{try unicode.utf8Encode(chutf8, &out)});
// try stdio.print("{0any} '{0s}'\n", .{out});
