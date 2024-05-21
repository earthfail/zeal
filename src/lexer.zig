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

// TODO(Salim): Rename Types to match std.json convention

/// debugging function to print what the lexer reads
pub const LexError = error{ initError, nullError };
pub fn lexString(s: []const u8) LexError!void {
    const stdio = std.io.getStdOut().writer();

    var edn_iter = Iterator.init(s) catch {
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
// TODO(Salim): add tests for number, keywords, characters, strings, symbols, tags
//              and combinations thereof

test "test symbols isolated" {
    const Input = struct {
        string: []const u8,
        expectation: Token,
    };
    const inputs = [_]Input{
        .{ .string = "é", .expectation = Token{ .literal = "é", .tag = .symbol } },
        .{ .string = "a/khatib", .expectation = Token{ .literal = "a/khatib", .tag = .symbol } },
        .{ .string = "/", .expectation = Token{ .literal = "/", .tag = .symbol } },
        .{ .string = "finé", .expectation = Token{ .literal = "finé", .tag = .symbol } },
        .{ .string = 
        \\salim
        , .expectation = Token{ .literal = "salim", .tag = .symbol } },
    };

    for (inputs) |input| {
        var iterator = try Iterator.init(input.string);
        if (iterator.nextError()) |t| {
            if (t) |token| {
                testing.expectEqual(token, input.expectation) catch |err| {
                    std.debug.print("   different output when reading \"{s}\"\n", .{input.string});
                    std.debug.print("   got {any}\n", .{token});
                    return err;
                };
                try testing.expect(iterator.next() == null);
            } else {
                std.debug.print("    got null token while reading \"{s}\"\n", .{input.string});
                try testing.expect(false);
            }
        } else |err| {
            std.debug.print("    failed scanning {} while reading \"{s}\"\n", .{ err, input.string });
            return err;
        }
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
test "integers and floats isolated" {
    // test if iterator determines the tag correctly for each number tag
    {
        const Input = struct {
            string: []const u8,
            tag: Tag,
        };
        const successful_arr = [_]Input{
            .{ .string = "123", .tag = .integer },
            .{ .string = "0", .tag = .integer },
            .{ .string = "+11111111111111111111111111111111111111111", .tag = .integer },
            .{ .string = "123109328N", .tag = .integer },
            .{ .string = "0.1", .tag = .float },
            .{ .string = "1230819.e10", .tag = .float },
            .{ .string = "123000819.", .tag = .float },
            .{ .string = "-1209384239408M", .tag = .float },
            .{ .string = "+213098.21039812039e10", .tag = .float },
        };
        for (successful_arr) |input| {
            var iterator = try Iterator.init(input.string);
            if (iterator.nextError()) |t| {
                if (t) |token| {
                    try testing.expectEqualStrings(input.string, token.literal.?);
                    try testing.expectEqual(input.tag, token.tag);

                    try testing.expect(iterator.next() == null);
                } else {
                    std.debug.print("    got null token while reading \"{s}\"\n", .{input.string});
                    try testing.expect(false);
                }
            } else |err| {
                std.debug.print("    failed scanning {} while reading \"{s}\"\n", .{ err, input.string });
                return err;
            }
        }
    }
    {
        const Input = struct {
            string: []const u8,
            result: Iterator.IterError,
        };
        const failiure_arr = [_]Input{
            .{ .string = "-0123", .result = error.ZeroPrefixNum },
            .{ .string = "12312Z", .result = error.NumberErr },
            .{ .string = "1020.123e+A", .result = error.InvalidNumber },
        };
        for (failiure_arr) |input| {
            var iterator = try Iterator.init(input.string);

            if (iterator.nextError()) |t| {
                if (t) |token| {
                    std.debug.print("    expected error found {any}\n", .{token});
                    try testing.expect(false);
                } else {
                    std.debug.print("    got null while reading {s}\n", .{input.string});
                    try testing.expect(false);
                }
            } else |err| {
                testing.expectEqual(err, input.result) catch |e| {
                    std.debug.print("error mismatch while reading {s}\n", .{input.string});
                    return e;
                };
            }
        }
    }
}
/// iterator has two main functions next,peek with the following properties:
/// const c1 = self.peek();
/// const c2 = self.next();
/// std.mem.eql(u8,c1,c2)
/// and self.peek is idempotent
pub const Iterator = struct {
    iter: unicode.Utf8Iterator,
    window: IterError!?Token = undefined,

    // \<names[i]> is equivalent to \<chars[i]>
    const names = [_][]const u8{ "space", "tab", "newline", "return" };
    const chars = [_][]const u8{ " ", "\t", "\n", "\r" };

    const Self = @This();
    // TODO(Salim): check if the description below is correct
    /// errors with the suffix Err like NumberErr are error the occur because text around the token. errors with the prefix Invalid occur if there is a problem with the token itself.
    const IterError = error{ CharacterNull, InvalidCharacter, NoFirstCharacter, StringErr, InvalidString, SymbolErr, CharacterErr, PoundErr, KeywordErr, ZeroPrefixNum, NumberErr, InvalidNumber };

    /// Creates Iterator that consumes str and returns Tokens.
    /// the lifetime of str should be more than Iterator.
    pub fn init(str: []const u8) error{InvalidUtf8}!Iterator {
        var view = try unicode.Utf8View.init(str);
        var self = Iterator{ .iter = view.iterator() };
        self.window = self.next2();
        return self;
    }
    pub fn peek(self: Iterator) ?Token {
        return self.window catch null;
    }
    /// main procedure to get next token. Benefit over nextError is that it has same signature as peek and is independent of the token ahead i.e it will not throw error if the token after next if invalid. Disadvantage is that All errors are turned into null
    pub fn next(self: *Iterator) ?Token {
        return self.nextError() catch null;
    }
    /// scans iterator and returns next token in the stream. If there is an error, returns that error.
    /// Note: self.iter will be not be the same as before the call. Could be useful to skip invalid token.
    pub fn nextError(self: *Iterator) IterError!?Token {
        const next_token = self.next2();
        defer self.window = next_token;
        return self.window;
    }
    /// Helper procedure used to define next and nextError. Made public for more control
    pub fn next2(self: *Iterator) IterError!?Token {
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
                        // Note(Salim): could return character but then the parser needs to
                        // add another condition. One positive side of returning character instead of char is that
                        // life time of Token.literal will be the same no matter the tag because now only character
                        // types have a different lifetime (that of Iterator.chars)
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
            '\"' => {
                const string = try self.readString();
                return Token{ .tag = Tag.string, .literal = string };
            },
            else => {
                const is_digit: bool = digit: {
                    const s = self.iter.peek(2);
                    // Note(Salim): integers can be prefixed with a sign + or -
                    // so we need to peek two characters ahead
                    assert(s.len >= 1); // guaranteed by switch
                    const c1 = s[0];
                    if (isDigit(c1))
                        break :digit true;
                    if ('+' == c1 or '-' == c1) {
                        if (s.len > 1) {
                            const c2 = s[1]; // if digit then this should be a digit
                            if (isDigit(c2))
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
    /// reads separators until reaching a non-whitespace and not ',' character.
    /// Returns true if read something, false otherwise.
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
    }
    /// read comment from iterator, return true of encountered comment, false otherwise
    pub fn ignoreComment(self: *Iterator) bool {
        const original_i = self.iter.i;
        if (self.iter.nextCodepoint()) |c| {
            if (c != ';') {
                self.iter.i = original_i;
                return false;
            }
            while (self.iter.nextCodepoint()) |comment| {
                if (comment == '\n')
                    break;
            }
            return true;
        }
        self.iter.i = original_i;
        return false;
    }
    /// not part of the specification but useful predicat.
    /// defined in a way to match clojre.edn/read-string behaviour
    pub fn isTokenDelimiter(discriminant: []const u8) bool {
        return isSeparator(discriminant) or isDelimiter(discriminant) or isCommentStart(discriminant);
    }
    pub fn readNumber(self: *Iterator) IterError!Token {
        const original_i = self.iter.i;
        _ = self.consumeSign();
        {
            // numbers can't begin with 0 unless it is zero
            const s = self.iter.peek(2);
            if (s.len == 2 and s[0] == '0' and isDigit(s[1])) {
                return IterError.ZeroPrefixNum;
            }
        }
        _ = self.consumeDigits();
        const discriminant = self.iter.peek(1);
        if (discriminant.len != 0) {
            switch (discriminant[0]) {
                inline 'N', 'M' => |disc| {
                    // 'N' indicates bignumbers
                    // 'M' indicates exact precisions floating point numbers
                    if (self.iter.nextCodepoint()) |v| {
                        assert(v == disc);
                    } else {
                        unreachable;
                    }
                    const afterDisc = self.iter.peek(1);

                    if (afterDisc.len == 0 or isTokenDelimiter(afterDisc)) {
                        return Token{ .literal = self.iter.bytes[original_i..self.iter.i], .tag = if (disc == 'N') Tag.integer else Tag.float };
                    }
                    return IterError.NumberErr;
                },
                else => {
                    // TODO: check if this test can be delay untill the end. meaning after testing fractional
                    // and exponentional parts at the end of the procedure.
                    // test for correctness and performance.
                    // it is mainly here for clarity and because I *believe* most numbers will be integers
                    if (isTokenDelimiter(discriminant)) {
                        return Token{ .literal = self.iter.bytes[original_i..self.iter.i], .tag = Tag.integer };
                    }
                    // section below tests for valid floating point number
                    var fractional: bool = false;
                    var exponentional: bool = false;
                    // numbers can have a fraction part followed by an exponent part
                    // like 12345789.876543210e10
                    //      ^~~~~~~~^~~~~~~~~~^~~
                    //      digits  fraction  exponent
                    if (discriminant[0] == '.') {
                        _ = self.iter.nextCodepointSlice(); // consume '.'
                        _ = self.consumeDigits();
                        fractional = true;
                    }
                    const exponent_section = self.iter.peek(1);
                    if (exponent_section.len != 0) {
                        if (exponent_section[0] == 'e' or exponent_section[0] == 'E') {
                            _ = self.iter.nextCodepointSlice() orelse unreachable;
                            _ = self.consumeSign();
                            if (self.consumeDigits() == 0) {
                                return IterError.InvalidNumber;
                            }
                            exponentional = true;
                        }
                    }
                    if (fractional or exponentional) {
                        const disc2 = self.iter.peek(1);
                        if (disc2.len == 0 or isTokenDelimiter(disc2)) {
                            return Token{ .literal = self.iter.bytes[original_i..self.iter.i], .tag = Tag.float };
                        } else {
                            return IterError.NumberErr;
                        }
                    } else {
                        return IterError.NumberErr;
                    }
                },
            }
        } else {
            return Token{ .literal = self.iter.bytes[original_i..self.iter.i], .tag = Tag.integer };
        }
    }
    /// character value is the string after \ in the format \3 or \u123
    pub fn readCharacterValue(self: *Iterator) IterError![]const u8 {
        const start_i = self.iter.i;
        _ = self.iter.nextCodepointSlice() orelse return IterError.NoFirstCharacter;

        var end_i = self.iter.i;
        while (self.iter.nextCodepointSlice()) |c| : (end_i = self.iter.i) {
            if (isSeparator(c) or isDelimiter(c)) {
                self.iter.i = end_i;
                break;
            }
        }
        return self.iter.bytes[start_i..end_i];
    }

    pub fn readString(self: *Iterator) IterError![]const u8 {
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
                _ = self.iter.nextCodepointSlice() orelse return IterError.InvalidString;
            }
        } else return IterError.InvalidString;
        const end_i = self.iter.i;

        return self.iter.bytes[original_i..end_i];
    }
    /// read symbol from iterator and test for correctness but does not test if first character is a tag or keyword delimiter
    fn readSymbolPartialTest(self: *Iterator) IterError![]const u8 {
        const original_i = self.iter.i;
        var end_i = original_i;
        while (self.iter.nextCodepointSlice()) |c| : (end_i = self.iter.i) {
            if (isTokenDelimiter(c)) {
                self.iter.i = end_i;
                break;
            }
        }
        const symbol = self.iter.bytes[original_i..end_i];
        if (symbol.len == 0) {
            return IterError.SymbolErr;
        }
        if (!isValidFirstCharacter(symbol)) {
            return IterError.SymbolErr;
        }
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
        return symbol;
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
    // NOTE(Salim): assumes false most of the time
    /// reads character from iterator. Returns true if it is '+' or '-' and advances the self.iter
    /// otherwise, returns false and self.iter is returned to its original position.
    fn consumeSign(self: *Iterator) bool {
        const c = self.iter.peek(1);
        if (c.len != 0) {
            if (c[0] == '-' or c[0] == '+') {
                _ = self.iter.nextCodepointSlice(); // advances self.iter
                return true;
            }
        }
        return false;
    }
    /// reads digits from self.iter until encountering a non digit
    fn consumeDigits(self: *Iterator) usize {
        const original_i = self.iter.i;
        var end_i = original_i;
        while (self.iter.nextCodepoint()) |digit| : (end_i = self.iter.i) {
            if (!isDigit(digit)) {
                self.iter.i = end_i;
                break;
            }
        }
        return end_i - original_i;
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
pub const Token = struct {
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
