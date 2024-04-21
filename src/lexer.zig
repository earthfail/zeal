// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228
// https://discord.com/channels/605571803288698900/1230856067836284969
// value < math.minInt(T) or value > math.maxInt(T)
// or
// std.math.cast(u8, x) orelse @panic("nope")
const std = @import("std");
const mem = std.mem;

const unicode = std.unicode;
const ascii = std.ascii;
const math = std.math;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

const ziglyph = @import("ziglyph");
const Grapheme = ziglyph.Grapheme;
const GraphemeIter = Grapheme.GraphemeIterator;
// https://zig.news/dude_the_builder/unicode-basics-in-zig-dj3
// (try std.unicode.Utf8View.init("string")).iterator();
pub fn lexString(allocator: mem.Allocator, s: []const u8) !void {
    std.debug.print("s={any}, {s}, {any}\n", .{ s.ptr, s, s });
    const stdio = std.io.getStdOut().writer();

    var edn_iter = Iterator.init(allocator, s) catch {
        std.debug.print("iterator failed sorry!\n", .{});
        return;
    };
    while (edn_iter.next()) |token| {
        defer token.deinit(allocator);
        stdio.print("got '{s}' {}\n", .{ token, token.tag }) catch {
            std.debug.print("error writing token\n", .{});
            return;
        };
    } else {
        stdio.print("got null\n", .{}) catch {
            std.debug.print("error writing null\n", .{});
            return;
        };
    }
}

pub const Iterator = struct {
    iter: unicode.Utf8Iterator,
    allocator: mem.Allocator = undefined,
    window: ?Token = undefined,

    const Self = @This();
    const IterError = error{ CharacterNull, InvalidCharacter, StringErr, SymbolErr, CharacterErr, PoundErr, KeywordErr, NotFinished };

    pub fn init(allocator: mem.Allocator, str: []const u8) error{InvalidUtf8}!Iterator {
        var view = try unicode.Utf8View.init(str);
        var self = Iterator{ .allocator = allocator, .iter = view.iterator() };
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
        // ignore spaces and comments
        while (self.ignoreSeparator() or self.ignoreComment()) {}

        const c = self.iter.peek(1);
        // std.debug.print("c is {s}\n", .{c});

        if (c.len == 0) {
            return null;
        }
        switch (c[0]) {
            inline '{', '[', '(', ')', ']', '}' => |delimiter| {
                _ = self.iter.nextCodepointSlice();
                return Token{ .tag = @field(Tag, &[_]u8{delimiter}), .literal = c };
            },
            '#' => {
                _ = self.iter.nextCodepointSlice();
                const c2 = self.iter.peek(1);
                if (c2.len == 0)
                    return IterError.PoundErr;
                switch (c2[0]) {
                    '{' => {
                        _ = self.iter.nextCodepointSlice();
                        return Token{ .tag = Tag.@"#{", .literal = null };
                    },
                    '_' => {
                        _ = self.iter.nextCodepointSlice();
                        return Token{ .tag = Tag.@"#_", .literal = null };
                    },
                    else => {
                        const tag = self.readSymbol() catch return IterError.PoundErr;
                        return Token{ .tag = Tag.tag, .literal = tag };
                    },
                }
            },
            '\\' => {
                _ = self.iter.nextCodepointSlice();
                const character = try self.readCharacterValue();
                errdefer self.allocator.free(character);
                const size = character.len;

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
                const first_char_len = unicode.utf8ByteSequenceLength(character[0]) catch unreachable;
                const second_char_len = unicode.utf8ByteSequenceLength(character[first_char_len]);
                if (second_char_len) |second_char| {
                    const c2 = character[first_char_len .. first_char_len + second_char];
                    if (!isSeparator(c2) and !isDelimiter(c2))
                        return IterError.InvalidCharacter;
                } else |_| {}
                return Token{ .tag = Tag.character, .literal = character };
            },
            ':' => {
                _ = self.iter.nextCodepointSlice();
                const keyword = self.readSymbol() catch return IterError.KeywordErr;
                return Token{ .tag = Tag.keyword, .literal = keyword };
            },
            ';' => {
                // TODO: test performance of replacing this block with ignoreComment
                // _ = self.ignoreComment();
                _ = self.iter.nextCodepointSlice();
                while (self.iter.nextCodepointSlice()) |c2| {
                    if (mem.eql(u8, c2, "\n"))
                        break;
                }
                return self.next2();
            },
            '\"' => {
                _ = self.iter.nextCodepointSlice();
                const string = try self.readString();
                return Token{ .tag = Tag.string, .literal = string };
            },
            else => {
                var is_digit: bool = digit: {
                    var iter = self.iter; // copy iterator
                    const s = iter.nextCodepointSlice();
                    assert(s != null); // guaranteed by switch first if statement
                    const c1 = firstCodePoint(s.?);
                    if (ziglyph.isAsciiDigit(c1))
                        break :digit true;
                    if ('+' == c1 or '-' == c1) {
                        if (iter.nextCodepointSlice()) |c2| {
                            if (ziglyph.isAsciiDigit(firstCodePoint(c2)))
                                break :digit true;
                        }
                    }
                    break :digit false;
                };
                if (is_digit) {
                    return try self.readNumber();
                } else {
                    const symbol = try self.readSymbol();
                    return Token{ .tag = Tag.symbol, .literal = symbol };
                }
            },
        }

        return null;
    }
    // read separators until reaching a non-whitespace and not ',' character. Returns true if read something, false otherwise.
    pub fn ignoreSeparator(self: *Iterator) bool {
        var original_i = self.iter.i;
        if (self.iter.nextCodepointSlice()) |c| {
            if (!isSeparator(c)) {
                self.iter.i = original_i;
                return false;
            }
        } else {
            return false;
        }
        original_i = self.iter.i;
        while (self.iter.nextCodepointSlice()) |c| : (original_i = self.iter.i) {
            if (!isSeparator(c)) {
                self.iter.i = original_i;
                break;
            }
        }
        return true;
        // if(false) {
        //     var read = false;
        //     var original_i = self.iter.i;
        //     while (self.iter.nextCodepointSlice()) |c| : (original_i = self.iter.i) {
        //         if (isSeparator(c)) {
        //             read = true;
        //             continue;
        //         } else {
        //             self.iter.i = original_i;
        //             return read;
        //         }
        //     } else {
        //         self.iter.i = original_i;
        //         return read;
        //     }
        // }
        // while (self.iter.peek(1)) |c| : (_ = self.iter.nextSlice()) {
        //     if (isSeparator(c)) {
        //         continue;
        //     } else if (mem.eql(u8, c, ";")) {
        //         while (self.iter.nextSlice()) |comment| {
        //             if (mem.eql(u8, comment, "\n"))
        //                 break;
        //         }
        //     } else break;
        // }
    }
    /// read comment from iterator, return true of encountered comment, false otherwise
    pub fn ignoreComment(self: *Iterator) bool {
        const original_i = self.iter.i;
        if (self.iter.nextCodepoint()) |c| {
            if (c != ';') {
                self.iter.i = original_i;
                return false;
            }
            while (self.iter.nextCodepointSlice()) |comment| {
                if (comment[0] == '\n')
                    break;
            }
            return true;
        }
        self.iter.i = original_i;
        return false;
    }

    pub fn readNumber(self: *Iterator) !Token {
        var output = ArrayList(u8).init(self.allocator);
        errdefer output.deinit();
        try self.readSign(&output);
        if (self.iter.nextCodepointSlice()) |digit| {
            const c1 = firstCodePoint(digit);
            if ('0' == c1) {
                const digit2 = self.iter.peek(1);
                if (digit2.len != 0) {
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
        const differentiator = self.iter.peek(1);
        if (differentiator.len != 0) {
            const c = firstCodePoint(differentiator);
            switch (c) {
                'N' => {
                    try output.appendSlice(self.iter.nextCodepointSlice().?);
                    if (self.iter.peek(1).len == 0 or isSeparator(self.iter.peek(1))) {
                        return .{ .literal = try output.toOwnedSlice(), .tag = Tag.integer };
                    } else return error.InvalidNumber;
                },
                'M' => {
                    try output.appendSlice(self.iter.nextCodepointSlice().?);
                    if (self.iter.peek(1).len == 0 or isSeparator(self.iter.peek(1))) {
                        return .{ .literal = try output.toOwnedSlice(), .tag = Tag.float };
                    } else return error.InvalidNumber;
                },
                else => {
                    if (isSeparator(differentiator) or isDelimiter(differentiator))
                        return .{ .tag = Tag.integer, .literal = try output.toOwnedSlice() };
                    var fract = false;
                    var exp = false;
                    if ('.' == c) { // fraction part
                        _ = self.iter.nextCodepointSlice();
                        try output.appendSlice(differentiator);
                        try self.readDigits(&output);
                        fract = true;
                    }
                    if (self.iter.peek(1).len == 0) {
                        return .{ .literal = try output.toOwnedSlice(), .tag = Tag.float };
                    }
                    const c2 = firstCodePoint(self.iter.peek(1));
                    if ('e' == c2 or 'E' == c2) {
                        try output.appendSlice(self.iter.nextCodepointSlice().?);
                        const d = self.iter.peek(1);
                        if (d.len != 0) {
                            const d1 = firstCodePoint(d);
                            if (ziglyph.isAsciiDigit(d1) or '-' == d1 or '+' == d1) {
                                try self.readSign(&output);
                                try self.readDigits(&output);
                                exp = true;
                            } else return error.InvalidNumber;
                        }
                    }
                    if (fract or exp) {
                        if (self.iter.peek(1).len == 0 or isSeparator(self.iter.peek(1)) or isDelimiter(self.iter.peek(1))) {
                            return .{ .literal = try output.toOwnedSlice(), .tag = Tag.float };
                        } else return error.InvalidNumber;
                    } else return error.FloatErr;
                },
            }
        } else return .{ .literal = try output.toOwnedSlice(), .tag = Tag.integer };
    }
    // character value is the string after \ in the format \3 \u123
    pub fn readCharacterValue(self: *Iterator) ![]const u8 {
        var bytes_arr = std.ArrayList(u8).init(self.allocator);
        if (self.iter.nextCodepointSlice()) |c| {
            try bytes_arr.appendSlice(c);
        } else return error.NoFirstCharacter;

        var original_i = self.iter.i;
        while (self.iter.nextCodepointSlice()) |c| : (original_i = self.iter.i) {
            if (!isSeparator(c) and !isDelimiter(c)) {
                try bytes_arr.appendSlice(c);
            } else {
                self.iter.i = original_i;
                break;
            }
        }
        return try bytes_arr.toOwnedSlice();
    }

    pub fn readString(self: *Iterator) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        while (self.iter.nextCodepointSlice()) |c| {
            if (mem.eql(u8, c, "\""))
                break;
            if (mem.eql(u8, c, "\\")) {
                if (self.iter.nextCodepointSlice()) |quoted| {
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

        if (self.iter.nextCodepointSlice()) |first| {
            if (isSeparator(first)) {
                return IterError.SymbolErr;
            }
            const firstu21 = unicode.utf8Decode(first) catch unreachable;
            if (ziglyph.isNumber(firstu21))
                return IterError.SymbolErr;
            if (!ziglyph.isAlphaNum(firstu21) and !isSymbolSpecialCharacter(firstu21) and !('/' == firstu21))
                return IterError.SymbolErr;
            if ('/' == firstu21) {
                empty_prefix = true;
                encountered_slash = true;
            }
            try output.appendSlice(first);
            if (mem.eql(u8, first, ".") or mem.eql(u8, first, "-") or mem.eql(u8, first, "+")) {
                const second = self.iter.peek(1);
                if (second.len == 0) {
                    if (ziglyph.isNumber(unicode.utf8Decode(second) catch unreachable))
                        return IterError.SymbolErr;
                } else return try output.toOwnedSlice();
            }
        } else unreachable; // guaranteed by the next2 function

        // check empty prefix and not empty name
        {
            const c = self.iter.peek(1);
            if (c.len != 0) {
                if (!isSeparator(c)) {
                    if (empty_prefix and encountered_slash)
                        return error.SymbolEmptyPrefix;
                }
            }
        }
        var original_i = self.iter.i;
        errdefer self.iter.i = original_i;

        while (self.iter.nextCodepointSlice()) |c| : (original_i = self.iter.i) {
            const cu21 = unicode.utf8Decode(c) catch unreachable;
            if (ziglyph.isAlphaNum(cu21) or isSymbolSpecialCharacter(cu21) or isKeywordTagDelimiter(cu21)) {
                // _ = self.iter.nextCodepointSlice(); // consume c
                try output.appendSlice(c);
                continue;
            } else if ('/' == cu21) {
                if (encountered_slash)
                    return IterError.SymbolErr;
                encountered_slash = true;

                // _ = self.iter.nextCodepointSlice(); // consume /
                try output.appendSlice(c); // "/" == c
                // check first character of name
                if (self.iter.nextCodepointSlice()) |first| {
                    if (isSeparator(first))
                        return IterError.SymbolErr; // name should not be empty

                    const firstu21 = unicode.utf8Decode(first) catch unreachable;
                    if (ziglyph.isNumber(firstu21))
                        return IterError.SymbolErr;
                    if (!ziglyph.isAlphaNum(firstu21) and !isSymbolSpecialCharacter(firstu21))
                        return IterError.SymbolErr;

                    try output.appendSlice(first);
                    if (mem.eql(u8, first, ".") or mem.eql(u8, first, "-") or mem.eql(u8, first, "+")) {
                        const second = self.iter.peek(1);
                        if (second.len != 0) {
                            if (ziglyph.isNumber(unicode.utf8Decode(second) catch unreachable))
                                return IterError.SymbolErr;
                        } else {
                            assert(!empty_prefix); // guarantees that it is a valid symbol
                            return try output.toOwnedSlice();
                        }
                    }
                } else return error.SymbolEmptyName; // name should not be empty
            } else {
                // here c is not # or :
                if (isSeparator(c) or isDelimiter(c) or isCommentStart(c)) {
                    self.iter.i = original_i;
                    break;
                } else return IterError.SymbolErr;
            }
        }
        return try output.toOwnedSlice();
    }

    /// check the special character that a symbol can contain other than the alphanumberic
    fn isSymbolSpecialCharacter(c: u21) bool {
        // TODO: test correctness without casting
        const c_ascii = math.cast(u8, c) orelse return false;
        return switch (c_ascii) {
            '.', '*', '+', '!', '-', '_', '?', '$', '%', '&', '=', '<', '>' => true,
            else => false,
        };
    }
    fn isKeywordTagDelimiter(c: u21) bool {
        // TODO: test correctness without casting
        const c_ascii = math.cast(u8, c) orelse return false;
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
    fn isCommentStart(c: []const u8) bool {
        if (c.len == 0)
            return false;
        return c[0] == ';';
    }
    fn isSeparator(c: []const u8) bool {
        // if (c.len != 1)
        //     return false;
        // const ascii_c = c[0];
        // .{32, 9, 10, 13, control_code.vt, control_code.ff}
        // 10 0x0a \n, 13 0x0d \r
        // return ascii.isASCII(ascii_c) and (ascii.isWhitespace(ascii_c) or ascii_c == ',');
        if (c.len == 0)
            return false;
        const c0: u8 = c[0];
        return ascii.isWhitespace(c0) or c0 == ',';
    }
    pub fn firstCodePoint(c: []const u8) u21 {
        // var fis = std.io.fixedBufferStream(c);
        // const reader = fis.reader();
        // const code_point = ziglyph.readCodePoint(reader) catch unreachable;
        // return code_point.?;
        return unicode.utf8Decode(c) catch unreachable;
    }
    pub fn readSign(self: *Iterator, output: *ArrayList(u8)) !void {
        const original_i = self.iter.i;
        if (self.iter.nextCodepointSlice()) |prefix| {
            if ('-' == prefix[0]) {
                try output.appendSlice(prefix);
            }
            if ('+' == prefix[0]) {} else {
                self.iter.i = original_i;
            }
        }
    }
    pub fn readDigits(self: *Iterator, output: *ArrayList(u8)) !void {
        var original_i = self.iter.i;
        while (self.iter.nextCodepointSlice()) |digit| : (original_i = self.iter.i) {
            const code_point = firstCodePoint(digit);
            if (ziglyph.isAsciiDigit(code_point)) {
                try output.appendSlice(digit);
            } else {
                self.iter.i = original_i;
                break;
            }
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
            .string => {
                if (value.literal) |s| {
                    try writer.writeAll("\"");
                    try writer.writeAll(s);
                    try writer.writeAll("\"");
                } else try writer.writeAll("null string");
            },
            .character => {
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
            },
            .symbol => {
                if (value.literal) |sym| {
                    try writer.writeAll(sym);
                } else try writer.writeAll("null symbol");
            },
            .keyword => {
                if (value.literal) |key| {
                    try writer.writeAll(":");
                    try writer.writeAll(key);
                } else try writer.writeAll("null keyword");
            },
            .tag => {
                if (value.literal) |t| {
                    try writer.writeAll("#");
                    try writer.writeAll(t);
                } else try writer.writeAll("null tag");
            },
            .integer => {
                if (value.literal) |i| {
                    try writer.print("{s}", .{i});
                } else try writer.writeAll("null integer");
            },
            .float => {
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
        while (tok) |token| : (tok = iterator.next()) {
            defer if (token.literal) |c| {
                if (token.tag == Tag.character or token.tag == Tag.string or token.tag == Tag.symbol or token.tag == Tag.tag)
                    iterator.allocator.free(c);
            };
            try fbsw.print("{s} ", .{token});
        }
        testing.expect(mem.eql(u8, fbs.getWritten(), expected_buffer)) catch {
            std.debug.print("****************************************************************output didn't meat the expectations\n", .{});
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
        while (tok) |token| : (tok = iterator.next()) {
            defer if (token.literal) |c| {
                if (token.tag == Tag.character or token.tag == Tag.string or token.tag == Tag.symbol or token.tag == Tag.tag)
                    iterator.allocator.free(c);
            };
            try fbsw.print("{s} ", .{token});
        }
        testing.expect(mem.eql(u8, fbs.getWritten(), exp)) catch {
            std.debug.print("****************************************************************output didn't mean the expectations\n", .{});
            std.debug.print("output: {s}\n", .{fbs.getWritten()});
            std.debug.print("expect: {s}\n", .{exp});
        };
    }
}
