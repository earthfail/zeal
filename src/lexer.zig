// https://discord.com/channels/605571803288698900/1173940455872933978/1173941982448603228
// https://discord.com/channels/605571803288698900/1230856067836284969
// value < math.minInt(T) or value > math.maxInt(T)
// or
// std.math.cast(u8, x) orelse @panic("nope")
const std = @import("std");
const mem = std.mem;

const unicode = std.unicode;
const Utf8Iterator = unicode.Utf8Iterator;
const ascii = std.ascii;
const math = std.math;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

/// debugging function to print what the lexer reads
pub const LexError = error{ initError, nullError };
pub fn lexString(s: []const u8) LexError!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch {
            @panic("gpa leaked");
        };
    }
    // std.debug.print("s={any}, {s}, {any}\n", .{ s.ptr, s, s });
    const stdio = std.io.getStdOut().writer();

    var edn_iter = Iterator.init(g_allocator, s) catch {
        std.debug.print("iterator failed sorry!\n", .{});
        return LexError.initError;
    };
    while (edn_iter.nextError()) |t| {
        if (t) |token| {
            stdio.print("got '{s}' {}\n", .{ token, token.tag }) catch {
                std.debug.print("error writing token\n", .{});
                return;
            };
        } else {
            stdio.print("got null \n", .{}) catch return;
            break;
        }
    } else |err| {
        stdio.print("got error {}\n", .{err}) catch {
            std.debug.print("error writing error XXXXXD\n", .{});
            return LexError.nullError;
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

        var iterator = try Iterator.init(in);
        var tok = iterator.next();
        while (tok) |token| : (tok = iterator.next()) {
            try fbsw.print("{s} ", .{token});
        }
        testing.expect(mem.eql(u8, fbs.getWritten(), exp)) catch {
            std.debug.print("****************************************************************output didn't mean the expectations\n", .{});
            std.debug.print("output: {s}\n", .{fbs.getWritten()});
            std.debug.print("expect: {s}\n", .{exp});
        };
    }
}
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

        var iterator = try Iterator.init(s);
        var tok = iterator.next();
        while (tok) |token| : (tok = iterator.next()) {
            try fbsw.print("{s} ", .{token});
        }
        testing.expect(mem.eql(u8, fbs.getWritten(), expected_buffer)) catch {
            std.debug.print("****************************************************************output didn't meat the expectations\n", .{});
            std.debug.print("output: {s}\n", .{fbs.getWritten()});
            std.debug.print("expect: {s}\n", .{expected_buffer});
        };
    }
}

/// iterator has two main functions next,peek with the following properties:
/// const c1 = self.peek();
/// const c2 = self.next();
/// std.mem.eql(u8,c1,c2)
/// and self.peek is idempotent
pub const Iterator = struct {
    iter: unicode.Utf8Iterator,
    // TODO: remove allocator dependence
    allocator: mem.Allocator,
    window: ?Token = undefined,

    // \<names[i]> is equivalent to \<chars[i]>
    const names = [_][]const u8{ "space", "tab", "newline", "return" };
    const chars = [_][]const u8{ " ", "\t", "\n", "\r" };

    const Self = @This();
    const IterError = error{ CharacterNull, InvalidCharacter, StringErr, SymbolErr, CharacterErr, PoundErr, KeywordErr, NotFinished };

    // TODO: remove allocator dependence
    pub fn init(allocator: mem.Allocator, str: []const u8) error{InvalidUtf8}!Iterator {
        var view = try unicode.Utf8View.init(str);
        var self = Iterator{ .iter = view.iterator(), .allocator = allocator };
        self.window = self.next2() catch null;
        return self;
    }
    pub fn deinit(self: *Iterator) void {
        _ = self;
        // self.allocator.destroy(self.window);
    }
    pub fn peek(self: Iterator) ?Token {
        return self.window;
    }
    pub fn next(self: *Iterator) ?Token {
        return self.nextError() catch null;
    }
    pub fn nextError(self: *Iterator) !?Token {
        const next_token = try self.next2();
        defer self.window = next_token;
        return self.window;
    }
    pub fn next2(self: *Iterator) !?Token {
        // ignore spaces and comments
        while (self.ignoreSeparator() or self.ignoreComment()) {}

        const c = self.iter.peek(1);

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
                        const tag = self.readSymbolPartialTest() catch return IterError.PoundErr;
                        // tags consists of "#" followed by an aphabetic character
                        if (!ascii.isAlphabetic(tag[0])) {
                            return IterError.PoundErr;
                        }
                        return Token{ .tag = Tag.tag, .literal = tag };
                    },
                }
            },
            '\\' => {
                _ = self.iter.nextCodepointSlice();
                const character = try self.readCharacterValue();

                const size = character.len;

                if (size == 0)
                    return IterError.CharacterNull;

                inline for (names, chars) |name, char| {
                    if (mem.eql(u8, character, name)) {
                        // defer self.allocator.free(character); // unnecessary defer but used for consistency
                        // const literal = try self.allocator.alloc(u8, 1);
                        // literal[0] = char;
                        return Token{ .tag = Tag.character, .literal = char };
                    }
                }
                if (character[0] == 'u') {
                    if (character.len != 1 + 4)
                        return IterError.InvalidCharacter;
                    for (character[1..]) |d| {
                        if (!ascii.isHex(d))
                            return IterError.InvalidCharacter;
                    } else {
                        // return uXXXX to parse in parser.zig
                        return Token{ .tag = Tag.character, .literal = character };
                    }
                }
                // DON'T COMMIT: REMOVE this section
                // const first_char_len = unicode.utf8ByteSequenceLength(character[0]) catch unreachable;
                // const second_char_len = unicode.utf8ByteSequenceLength(character[first_char_len]);
                // if (second_char_len) |second_char| {
                //     const c2 = character[first_char_len .. first_char_len + second_char];
                //     if (!isSeparator(c2) and !isDelimiter(c2))
                //         return IterError.InvalidCharacter;
                // } else |_| {}
                return Token{ .tag = Tag.character, .literal = character };
            },
            ':' => {
                _ = self.iter.nextCodepointSlice();
                const keyword = self.readSymbolPartialTest() catch return IterError.KeywordErr;
                // keywords cannot begin with "::"
                if (keyword[0] == ':') {
                    return IterError.KeywordErr;
                }
                return Token{ .tag = Tag.keyword, .literal = keyword };
            },
            // ';' => {
            //     // TODO: test performance of replacing this block with ignoreComment
            //     // _ = self.ignoreComment();
            //     _ = self.iter.nextCodepointSlice();
            //     while (self.iter.nextCodepointSlice()) |c2| {
            //         if (mem.eql(u8, c2, "\n"))
            //             break;
            //     }
            //     return self.next2();
            // },
            '\"' => {
                const string = try self.readString();
                return Token{ .tag = Tag.string, .literal = string };
            },
            else => {
                const is_digit: bool = digit: {
                    var iter = self.iter; // copy iterator
                    const s = iter.nextCodepointSlice();
                    assert(s != null); // guaranteed by switch first if statement
                    const c1 = firstCodePoint(s.?);
                    if (isDigit(c1))
                        break :digit true;
                    if ('+' == c1 or '-' == c1) {
                        if (iter.nextCodepointSlice()) |c2| {
                            if (isDigit(firstCodePoint(c2)))
                                break :digit true;
                        }
                    }
                    break :digit false;
                };
                if (is_digit) {
                    return try self.readNumber();
                } else {
                    const symbol = try self.readSymbolPartialTest();
                    if (isKeywordTagDelimiter(symbol[0])) {
                        return IterError.SymbolErr;
                    }
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
                    if (isDigit(c2))
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
                            if (isDigit(d1) or '-' == d1 or '+' == d1) {
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
        const start_i = self.iter.i;
        _ = self.iter.nextCodepointSlice() orelse return error.NoFirstCharacter;

        var end_i = self.iter.i;
        while (self.iter.nextCodepointSlice()) |c| : (end_i = self.iter.i) {
            if (isSeparator(c) or isDelimiter(c)) {
                self.iter.i = end_i;
                break;
            }
        }
        return self.iter.bytes[start_i..end_i];
    }

    pub fn readString(self: *Iterator) ![]const u8 {
        const original_i = self.iter.i;
        if (self.iter.nextCodepointSlice()) |c| {
            if (!mem.eql(u8, c, "\"")) {
                return IterError.StringErr;
            }
        } else {
            return IterError.StringErr;
        }
        while (self.iter.nextCodepointSlice()) |c| {
            if (mem.eql(u8, c, "\""))
                break;
            if (mem.eql(u8, c, "\\")) {
                // there must be a character after \
                _ = self.iter.nextCodepointSlice() orelse return IterError.StringErr;
            }
        } else return IterError.StringErr;
        const end_i = self.iter.i;

        return self.iter.bytes[original_i..end_i];
    }
    // read symbol from iterator and test for correctness but does not test if first character is a tag or keyword delimiter
    pub fn readSymbolPartialTest(self: *Iterator) ![]const u8 {
        const original_i = self.iter.i;
        var end_i = original_i;
        while (self.iter.nextCodepointSlice()) |c| : (end_i = self.iter.i) {
            if (isSeparator(c) or isCommentStart(c) or isDelimiter(c)) {
                self.iter.i = end_i;
                break;
            }
        }
        const symbol = self.iter.bytes[original_i..end_i];
        if (symbol.len == 0) {
            return IterError.SymbolErr;
        }
        // symbols also don't start with ':' or '#', those are reserved for keywords and tags
        // TODO: move keyword tag check outwards
        //  or isKeywordTagDelimiter(symbol[0])
        if (!isValidFirstCharacter(symbol)) {
            return IterError.SymbolErr;
        }
        {
            // search for '/' and check if either both prefix and name are empty or not empty
            var encountered_slash = false;
            for (symbol, 0..) |char, i| {
                if (char == '/') {
                    // symbol can only contain at most one slash
                    if (encountered_slash) {
                        return IterError.SymbolErr;
                    }
                    encountered_slash = true;
                    // found slash at the start but `name` is not empty or slash is at the end
                    if (i == 0) {
                        if (symbol.len != 1) {
                            return IterError.SymbolErr;
                        }
                    } else if (i == symbol.len - 1) {
                        return IterError.SymbolErr;
                    } else if (!isValidFirstCharacter(symbol[i + 1 ..])) {
                        // character after slash should also follow first character restrinction
                        return IterError.SymbolErr;
                    }
                }
            }
        }
        // TODO: continue all tests
        return symbol;
    }

    /// I could also read whole symbol then validate it. Maybe I will try it in another function.
    /// But the iterface for parsing it cumbersome so I erred on the side of caution
    /// or I could copy the iterator to simplified validation. In later commits WTWOG (with the will of God)
    pub fn readSymbol_old(self: *Iterator) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        var encountered_slash = false;
        var empty_prefix = false;
        errdefer output.deinit();

        if (self.iter.nextCodepointSlice()) |first| {
            if (isSeparator(first)) {
                return IterError.SymbolErr;
            }
            const firstu21 = unicode.utf8Decode(first) catch unreachable;
            if (isDigit(firstu21))
                return IterError.SymbolErr;
            if (!isAlphaNum(firstu21) and !isSymbolSpecialCharacter(firstu21) and !('/' == firstu21))
                return IterError.SymbolErr;
            if ('/' == firstu21) {
                empty_prefix = true;
                encountered_slash = true;
            }
            try output.appendSlice(first);
            if (mem.eql(u8, first, ".") or mem.eql(u8, first, "-") or mem.eql(u8, first, "+")) {
                const second = self.iter.peek(1);
                if (second.len == 0) {
                    if (isDigit(unicode.utf8Decode(second) catch unreachable))
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
            if (isAlphaNum(cu21) or isSymbolSpecialCharacter(cu21) or isKeywordTagDelimiter(cu21)) {
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
                    if (isDigit(firstu21))
                        return IterError.SymbolErr;
                    if (!isAlphaNum(firstu21) and !isSymbolSpecialCharacter(firstu21))
                        return IterError.SymbolErr;

                    try output.appendSlice(first);
                    if (mem.eql(u8, first, ".") or mem.eql(u8, first, "-") or mem.eql(u8, first, "+")) {
                        const second = self.iter.peek(1);
                        if (second.len != 0) {
                            if (isDigit(unicode.utf8Decode(second) catch unreachable))
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

    fn isValidFirstCharacter(symbol: []const u8) bool {
        assert(symbol.len != 0);
        // symbols only start with alphanumberic characters
        if (ascii.isDigit(symbol[0])) {
            return false;
        }
        // if (!ascii.isAlphanumeric(symbol[0]) and !isSymbolSpecialCharacter(symbol[0])) {
        //     return false;
        // }
        if ((symbol[0] == '.' or symbol[0] == '-' or symbol[0] == '+') and symbol.len != 1) {
            const second = symbol[1];
            if (ascii.isDigit(second)) {
                return false;
            }
        }
        return true;
    }
    /// check the special character that a symbol can contain other than the alphanumberic
    fn isSymbolSpecialCharacter(c: u21) bool {
        return switch (c) {
            '.', '*', '+', '!', '-', '_', '?', '$', '%', '&', '=', '<', '>' => true,
            else => false,
        };
    }
    fn isDigit(c: u21) bool {
        const c_ascii = math.cast(u8, c) orelse return false;
        return ascii.isDigit(c_ascii);
    }
    fn isAlphaNum(c: u21) bool {
        const c_ascii = math.cast(u8, c) orelse return false;
        return ascii.isAlphanumeric(c_ascii);
    }
    fn isKeywordTagDelimiter(c: u21) bool {
        return c == ':' or c == '#';
    }
    fn isDelimiter(c: []const u8) bool {
        if (c.len != 1) {
            return false;
        }
        return switch (c[0]) {
            '{', '}', '[', ']', '(', ')', '#', '\\', '\"' => true,
            else => false,
        };
    }
    fn isCommentStart(c: []const u8) bool {
        if (c.len == 0)
            return false;
        return c[0] == ';';
    }
    fn isSeparator(c: []const u8) bool {
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
            if (isDigit(code_point)) {
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

pub const Token = struct {
    tag: Tag,
    literal: ?[]const u8 = null,

    pub fn deinit(self: Token, allocator: mem.Allocator) void {
        _ = self;
        _ = allocator;
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
