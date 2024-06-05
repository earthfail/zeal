const std = @import("std");
// const log = std.log;
const mem = std.mem;
const big = std.math.big;
const unicode = std.unicode;
const expect = std.testing.expect;
const testing = std.testing;
const assert = std.debug.assert;

const lexer = @import("lexer.zig");

fn readBigInteger(allocator: mem.Allocator, buffer: []const u8) !Edn.BigInt {
    var v = try big.int.Managed.init(allocator);
    try v.setString(10, buffer);
    return v.toConst();
}

pub const EdnReader = struct {
    iter: lexer.Iterator,
    allocator: mem.Allocator,
    data_readers: ?std.StringHashMap(TagHandler) = null,

    // TODO(Salim): add ErrorEdn to procedures that return errors after finding all the errors
    const ErrorEdn = mem.Allocator.Error;
    // TODO(Salim): Make an Unmanaged version that takes an allocator. Could be used with ephemeral allocator for temporary allocations.
    // Should test if this modification improves performance
    pub fn init(allocator: mem.Allocator, buffer: []const u8) !EdnReader {
        const iter = try lexer.Iterator.init(buffer);
        return .{
            .iter = iter,
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *EdnReader) void {
        if (self.data_readers) |*readers| {
            readers.deinit();
        }
    }
    // TODO(Salim): write all possible errors in set
    pub fn readEdn(self: *EdnReader) !Edn {
        var allocator = self.allocator;
        var iter = &self.iter;
        if (iter.next()) |token| {
            switch (token.tag) {
                .symbol => {
                    if (mem.eql(u8, "true", token.literal.?)) {
                        // allocator.free(token.literal.?);
                        return Edn.true;
                    } else if (mem.eql(u8, "false", token.literal.?)) {
                        // allocator.free(token.literal.?);
                        return Edn.false;
                    } else if (mem.eql(u8, "nil", token.literal.?)) {
                        // allocator.free(token.literal.?);
                        return Edn.nil;
                    } else {
                        // const value = try allocator.create(Edn);
                        // value.* = Edn{ .symbol = try allocator.dupe(u8, token.literal.?) };
                        const value = Edn{ .symbol = try allocator.dupe(u8, token.literal.?) };
                        return value;
                    }
                },
                .keyword => {
                    // const value = try allocator.create(Edn);
                    // value.* = Edn{ .keyword = try allocator.dupe(u8, token.literal.?) };
                    const value = Edn{ .keyword = try allocator.dupe(u8, token.literal.?) };
                    return value;
                },
                .string => {
                    // const value = try allocator.create(Edn);
                    // value.* = Edn{ .string = token.literal.? };
                    const value = Edn{ .string = try canonicalString(allocator, token.literal.?) };
                    return value;
                },
                .character => {
                    // const c = lexer.Iterator.firstCodePoint(token.literal.?);
                    // allocator.free(token.literal.?);
                    // const value = try allocator.create(Edn);
                    // value.* = .{ .character = c };
                    const value = Edn{ .character = canonicalCharacter(token.literal.?) };
                    return value;
                },
                .integer => {
                    const literal = token.literal.?;
                    // defer token.deinit(iter.allocator);
                    // const value = try allocator.create(Edn);
                    // errdefer allocator.destroy(value);
                    var value: Edn = undefined;

                    if (literal[literal.len - 1] == 'N') {
                        // value.* = .{ .bigInteger = try readBigInteger(allocator, literal[0 .. literal.len - 1]) };
                        value = Edn{ .bigInteger = try readBigInteger(allocator, literal[0 .. literal.len - 1]) };
                        return value;
                    } else {
                        if (std.fmt.parseInt(i64, literal, 10)) |int| {
                            // value.* = .{ .integer = int };
                            value = Edn{ .integer = int };
                            return value;
                        } else |_| {
                            // value.* = .{ .bigInteger = try readBigInteger(allocator, literal) };
                            value = Edn{ .bigInteger = try readBigInteger(allocator, literal) };
                            return value;
                        }
                    }
                },
                .float => {
                    const literal = token.literal.?;
                    // defer token.deinit(iter.allocator);
                    // const value = try allocator.create(Edn);
                    // errdefer allocator.destroy(value);
                    var value: Edn = undefined;

                    if (literal[literal.len - 1] == 'M') {
                        // var a = try readBigInteger(allocator, literal[0 .. literal.len - 1]);
                        // // defer a.deinit();
                        // var f = try big.Rational.init(allocator);
                        // errdefer f.deinit();

                        // try f.copyInt(a);
                        // // value.* = .{ .bigFloat = f };
                        var f = try big.Rational.init(allocator);
                        // TODO(Salim): Fix parsing float
                        try f.setFloat(f64, 1.1);
                        value = Edn{ .bigFloat = f };
                        return value;
                    } else {
                        if (std.fmt.parseFloat(f64, literal)) |float| {
                            // value.* = .{ .float = float };
                            value = Edn{ .float = float };
                            return value;
                        } else |err| {
                            return err;
                        }
                        // const value = try allocator.create(Edn);
                    }
                },
                .@"(" => {
                    // const value = try allocator.create(Edn);
                    // value.* = .{ .list = Edn.List.init(allocator) };
                    // errdefer value.deinit(allocator);
                    // var value: Edn = undefined;
                    // var list = std.ArrayList(Edn).init(allocator);
                    var list = Edn.List{};
                    while (iter.peek()) |token2| {
                        switch (token2.tag) {
                            .@"}", .@"]" => return error.ParenMismatch,
                            .@")" => {
                                _ = iter.next();
                                return Edn{ .list = list };
                            },
                            else => {
                                // const item = try EdnReader.readEdn(allocator, iter);
                                const item = try self.readEdn();
                                // errdefer item.deinit(allocator);

                                try list.append(allocator, item);
                            },
                        }
                    }
                    return error.@"collection delimiter";
                },
                .@"[" => {
                    // const value = try allocator.create(Edn);
                    // value.* = .{ .vector = Edn.Vector.init(allocator) };
                    // errdefer value.deinit(allocator);
                    var vector = Edn.Vector{};
                    while (iter.peek()) |token2| {
                        switch (token2.tag) {
                            .@"}", .@")" => return error.ParenMismatch,
                            .@"]" => {
                                _ = iter.next();
                                return Edn{ .vector = vector };
                            },
                            else => {
                                const item = try self.readEdn();
                                // errdefer item.deinit(allocator);

                                try vector.append(allocator, item);
                            },
                        }
                    }
                    return error.@"collection delimiter";
                },
                .@"#{" => {
                    // const value = try allocator.create(Edn);
                    // value.* = .{ .hashset = Edn.Hashset.init(allocator) };
                    // errdefer value.deinit(allocator);
                    var hashset = Edn.Hashset{};
                    while (iter.peek()) |token2| {
                        switch (token2.tag) {
                            .@")", .@"]" => return error.ParenMismatch,
                            .@"}" => {
                                _ = iter.next();
                                return Edn{ .hashset = hashset };
                            },
                            else => {
                                var item = try self.readEdn();
                                errdefer item.deinit(allocator);

                                const item_copy = try allocator.create(Edn);
                                // @memcpy(item_copy, &item);
                                item_copy.* = item;
                                errdefer item_copy.deinit(allocator);
                                try hashset.put(allocator, item_copy, {});
                            },
                        }
                    }
                    return error.@"collection delimiter";
                },
                .@"{" => {
                    // const value = try allocator.create(Edn);
                    // value.* = .{ .hashmap = Edn.Hashmap.init(allocator) };
                    // errdefer value.deinit(allocator);

                    var hashmap = Edn.Hashmap{};
                    while (iter.peek()) |token2| {
                        switch (token2.tag) {
                            .@")", .@"]" => return error.ParenMismatch,
                            .@"}" => {
                                _ = iter.next();
                                return Edn{ .hashmap = hashmap };
                            },
                            else => {
                                var key = try self.readEdn();
                                errdefer key.deinit(allocator);

                                if (iter.peek()) |token3| {
                                    switch (token3.tag) {
                                        .@")", .@"]" => return error.ParenMismatch2,
                                        .@"}" => return error.OddNumberHashMap,
                                        else => {
                                            var val = try self.readEdn();
                                            errdefer val.deinit(allocator);

                                            var key_copy = try allocator.create(Edn);
                                            key_copy.* = key;
                                            errdefer key_copy.deinit(allocator);
                                            try hashmap.put(allocator, key_copy, val);
                                        },
                                    }
                                } else return error.OddNumberHashMap2;
                            },
                        }
                    }
                    return error.@"collection delimiter";
                },
                .@"#_" => {
                    var t = try self.readEdn();
                    t.deinit(allocator);
                    return self.readEdn();
                },
                .tag => {
                    // const value = try allocator.create(Edn);
                    var value: Edn = undefined;
                    // errdefer {
                    //     std.debug.print("removing value\n", .{});
                    //     allocator.destroy(value);
                    // }

                    var tag_value = try self.readEdn();
                    // errdefer {
                    //     std.debug.print("removing tag_value\n", .{});
                    //     tag_value.deinit(allocator);
                    // }
                    if (self.data_readers) |readers| {
                        if (readers.get(token.literal.?)) |reader| {
                            const v = try reader(allocator, tag_value);
                            tag_value.deinit(allocator);
                            const tag_element = Tag{ .tag = token.literal.?, .data = .{ .element = v } };
                            value = Edn{ .tag = tag_element };
                            return value;
                        }
                    }
                    const tag_value_copy = try allocator.create(Edn);
                    tag_value_copy.* = tag_value;
                    const tag_element = Tag{ .tag = token.literal.?, .data = .{ .edn = tag_value_copy } };
                    value = Edn{ .tag = tag_element };
                    return value;
                },
                .@"]", .@")", .@"}" => {
                    return error.@"no collection defined";
                },
            }
        }
        return error.@"edn is an extensible data format";
    }
    // TODO(Salim): Think about using simd to increase performance.
    /// create a string from `general_string` with "\n" replaced with \n and "\t" replaced with \t
    /// "\r" replaced with \r and  and "\"" with " and "\\" replaced with \
    fn canonicalString(allocator: mem.Allocator, general_string: []const u8) ![]const u8 {
        var canonical_string = try std.ArrayList(u8).initCapacity(allocator, general_string.len);

        var i: usize = 0;
        while (i < general_string.len) {
            if (general_string[i] == '\\') {
                // if lexer worked correctly, then this should not fire up
                assert(i != general_string.len - 1);
                const next_char = general_string[i + 1];
                switch (next_char) {
                    'n' => canonical_string.appendAssumeCapacity('\n'),
                    't' => canonical_string.appendAssumeCapacity('\t'),
                    'r' => canonical_string.appendAssumeCapacity('\r'),
                    '\"' => canonical_string.appendAssumeCapacity('\"'),
                    '\\' => canonical_string.appendAssumeCapacity('\\'),
                    else => return error.UnknownEscape,
                }
                i += 2;
            } else {
                try canonical_string.append(general_string[i]);
                i += 1;
            }
        }
        return canonical_string.toOwnedSlice();
    }
    // TODO(Salim): test using a fuzing method
    fn canonicalCharacter(general_character: []const u8) Edn.Character {
        assert(general_character.len > 0);
        if (general_character.len == 1)
            return general_character[0];
        if (general_character[0] == 'u') {
            return std.fmt.parseUnsigned(Edn.Character, general_character[1..], 16) catch unreachable;
        }

        return unicode.utf8Decode(general_character) catch unreachable;
    }
};

// I decided to keep keyword and symbol simple and we can compute each part (prefix,name) on demand.
pub const Edn = union(enum) {
    nil,
    boolean: bool,
    string: []const u8,
    character: Character,

    symbol: Symbol,
    keyword: Keyword,

    integer: i64,
    bigInteger: BigInt,
    float: f64,
    bigFloat: std.math.big.Rational,
    list: List,
    vector: Vector,
    hashmap: Hashmap,
    hashset: Hashset,
    tag: Tag,

    pub const Character = u21;
    pub const List = std.ArrayListUnmanaged(Edn);
    pub const Vector = std.ArrayListUnmanaged(Edn);
    // TODO(Salim): Create a Context to use ArrayHashMap instead of the AutoContext in AutoArrayHashMap
    pub const Hashmap = std.AutoArrayHashMapUnmanaged(*Edn, Edn);
    pub const Hashset = std.AutoArrayHashMapUnmanaged(*Edn, void);
    pub const BigInt = std.math.big.int.Const;

    pub const nil = Edn{ .nil = {} };
    pub const @"true" = Edn{ .boolean = true };
    pub const @"false" = Edn{ .boolean = false };

    // frees memory inside `self` but doesn't call the allocator on `self`
    pub fn deinit(self: *Edn, allocator: mem.Allocator) void {
        switch (self.*) {
            .nil, .boolean => return,
            .integer, .float, .character => {
                return;
            },
            .string, .symbol, .keyword => |*literal| {
                allocator.free(literal.*);
            },
            // TODO(Salim): remove simple conditions like for .bitInt, .nil, .boolean ...
            inline .bigInteger => |_| {
                return;
            },
            inline .bigFloat => |*number| {
                number.deinit();
            },
            inline .list, .vector => |*collection| {
                for (collection.items) |*item| {
                    item.deinit(allocator);
                }
                collection.deinit(allocator);
            },
            .hashmap => |*collection| {
                var iterator = collection.iterator();
                while (iterator.next()) |entry| {
                    entry.key_ptr.*.deinit(allocator);
                    entry.value_ptr.*.deinit(allocator);
                    allocator.destroy(entry.key_ptr.*);
                }
                collection.deinit(allocator);
            },
            .hashset => |*collection| {
                var iterator = collection.iterator();
                while (iterator.next()) |entry| {
                    entry.key_ptr.*.deinit(allocator);
                }
                collection.deinit(allocator);
            },
            .tag => {
                allocator.free(self.tag.tag);
                switch (self.tag.data) {
                    .edn => |element| {
                        element.deinit(allocator);
                    },
                    .element => |element| {
                        element.deinit(element.pointer, allocator);
                        allocator.destroy(element);
                        // maybe define tags differently to include a deinit function
                        //element
                        // allocator.destroy(@ptrFromInt(element));
                        // if (self.data_readers) |readers| {
                        //     if (readers.get(token.literal.?)) |reader| {
                        //         const v = reader.handle(allocator, tag_value.*);
                        //         tag_value.deinit(allocator);
                        //         const tag_element = Tag{ .tag = token.literal.?, .element = .{ .pointer = v } };
                        //         value.* = .{ .tag = tag_element };
                        //         return value;
                        //     }
                        // }
                    },
                }
                // allocator.destroy(self);
            },
        }
    }
    pub fn serialize(value: Edn, allocator: mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();
        const writer = buffer.writer();
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
                const case: std.fmt.Case = .lower;
                const string_rep = try big_int.toStringAlloc(allocator, 10, case);
                defer allocator.free(string_rep);
                try writer.print("{s}N", .{string_rep});
            },
            .float => {
                try writer.print("{d}", .{value.float});
            },
            .bigFloat => {
                const big_float = value.bigFloat;
                // const num_alloc = big_float.p.allocator;
                // const den_alloc = big_float.q.allocator;
                const case: std.fmt.Case = .lower;

                const num_string = try big_float.p.toString(allocator, 10, case);
                defer allocator.free(num_string);

                const den_string = try big_float.q.toString(allocator, 10, case);
                defer allocator.free(den_string);

                if (mem.eql(u8, "1", den_string)) {
                    try writer.print("{s}M", .{num_string});
                } else unreachable;
            },
            .character => {
                if (value.character == '\n')
                    try writer.writeAll("\\newline")
                else if (value.character == '\r')
                    try writer.writeAll("\\return")
                else if (value.character == '\t')
                    try writer.writeAll("\\tab")
                else if (value.character == ' ')
                    try writer.writeAll("\\space")
                else
                    try writer.print("\\{u}", .{value.character});
            },
            .string => {
                try writer.print("\"{s}\"", .{value.string});
            },
            .list => {
                try writer.writeAll("( ");
                for (value.list.items) |item| {
                    const item_serialized = try Edn.serialize(item, allocator);
                    defer allocator.free(item_serialized);

                    try writer.writeAll(item_serialized);
                    try writer.writeAll(" ");
                }
                try writer.writeAll(" )");
            },
            .vector => {
                try writer.writeAll("[");
                for (value.vector.items) |item| {
                    const item_serialized = try Edn.serialize(item, allocator);
                    defer allocator.free(item_serialized);

                    try writer.writeAll(item_serialized);
                    try writer.writeAll(" ");
                }
                try writer.writeAll("]");
            },
            .hashmap => {
                try writer.writeAll("{");
                var iterator = value.hashmap.iterator();
                while (iterator.next()) |entry| {
                    // todo: continue migrating
                    const key_serialized = try Edn.serialize(entry.key_ptr.*.*, allocator);
                    defer allocator.free(key_serialized);
                    const value_serialized = try Edn.serialize(entry.value_ptr.*, allocator);
                    defer allocator.free(value_serialized);

                    try writer.writeAll(key_serialized);
                    try writer.writeAll(" ");
                    try writer.writeAll(value_serialized);
                    try writer.writeAll(", ");
                }
                try writer.writeAll("}");
            },
            .hashset => {
                try writer.writeAll("#{");
                var iterator = value.hashset.iterator();
                while (iterator.next()) |entry| {
                    const key_serialized = try Edn.serialize(entry.key_ptr.*.*, allocator);
                    defer allocator.free(key_serialized);
                    try writer.writeAll(key_serialized);
                    try writer.writeAll(", ");
                }
                try writer.writeAll("}");
            },
            .tag => {
                switch (value.tag.data) {
                    .edn => |element| {
                        try writer.print("#{s} ", .{value.tag.tag});
                        const element_serialized = try Edn.serialize(element.*, allocator);
                        defer allocator.free(element_serialized);
                        try writer.writeAll(element_serialized);
                    },
                    .element => |element| {
                        if (element.serialize) |_| {
                            const tag_serialized = try element.serialize.?(element.pointer, allocator);
                            defer allocator.free(tag_serialized);
                            try writer.print("#{s} ", .{value.tag.tag});
                            try writer.writeAll(tag_serialized);
                        }
                    },
                }
            },
        }
        return buffer.toOwnedSlice();
    }
    // pub fn format(value: Edn, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    //     // log.info("writer type {}", .{@TypeOf(writer)});
    //     switch (value) {
    //         .nil => try writer.writeAll("nil"),
    //         .boolean => {
    //             if (value.boolean) {
    //                 try writer.writeAll("true");
    //             } else try writer.writeAll("false");
    //         },
    //         .symbol => {
    //             try writer.print("{s}", .{value.symbol});
    //         },
    //         .keyword => {
    //             try writer.print(":{s}", .{value.keyword});
    //         },
    //         .integer => {
    //             try writer.print("{d}", .{value.integer});
    //         },
    //         .bigInteger => {
    //             const big_int = value.bigInteger;
    //             const alloc = big_int.allocator;
    //             const case: std.fmt.Case = .lower;
    //             const string_rep = big_int.toString(alloc, 10, case) catch return;
    //             defer alloc.free(string_rep);
    //             try writer.print("{s}N", .{string_rep});
    //         },
    //         .float => {
    //             try writer.print("{d}", .{value.float});
    //         },
    //         .bigFloat => {
    //             const big_float = value.bigFloat;
    //             const num_alloc = big_float.p.allocator;
    //             const den_alloc = big_float.q.allocator;
    //             const case: std.fmt.Case = .lower;
    //             const num_string = big_float.p.toString(num_alloc, 10, case) catch return;
    //             const den_string = big_float.q.toString(den_alloc, 10, case) catch {
    //                 num_alloc.free(num_string);
    //                 return;
    //             };
    //             defer num_alloc.free(num_string);
    //             defer den_alloc.free(den_string);
    //             if (mem.eql(u8, "1", den_string)) {
    //                 try writer.print("{s}M", .{num_string});
    //             } else unreachable;
    //         },
    //         .character => {
    //             if (value.character == '\n')
    //                 try writer.writeAll("\\newline")
    //             else if (value.character == '\r')
    //                 try writer.writeAll("\\return")
    //             else if (value.character == '\t')
    //                 try writer.writeAll("\\tab")
    //             else if (value.character == ' ')
    //                 try writer.writeAll("\\space")
    //             else
    //                 try writer.print("\\{u}", .{value.character});
    //         },
    //         .string => {
    //             try writer.print("\"{s}\"", .{value.string});
    //         },
    //         .list => {
    //             try writer.writeAll("( ");
    //             for (value.list.items) |item| {
    //                 try format(item.*, fmt, options, writer);
    //                 try writer.writeAll(" ");
    //             }
    //             try writer.writeAll(" )");
    //         },
    //         .vector => {
    //             try writer.writeAll("[");
    //             for (value.vector.items) |item| {
    //                 try format(item.*, fmt, options, writer);
    //                 try writer.writeAll(" ");
    //             }
    //             try writer.writeAll("]");
    //         },
    //         .hashmap => {
    //             try writer.writeAll("{");
    //             var iterator = value.hashmap.iterator();
    //             while (iterator.next()) |entry| {
    //                 try format(entry.key_ptr.*.*, fmt, options, writer);
    //                 try writer.writeAll(" ");
    //                 try format(entry.value_ptr.*.*, fmt, options, writer);
    //                 try writer.writeAll(", ");
    //             }
    //             try writer.writeAll("}");
    //         },
    //         .hashset => {
    //             try writer.writeAll("#{");
    //             var iterator = value.hashset.iterator();
    //             while (iterator.next()) |entry| {
    //                 try format(entry.key_ptr.*.*, fmt, options, writer);
    //                 try writer.writeAll(", ");
    //             }
    //             try writer.writeAll("}");
    //         },
    //         .tag => {
    //             try writer.print("#{s} ", .{value.tag.tag});
    //             switch (value.tag.data) {
    //                 .edn => {
    //                     try format(value.tag.data.edn.*, fmt, options, writer);
    //                 },
    //                 .element => |_| {
    //                     return error.InvalidArgument;
    //                     // if (std.meta.hasFn(ele.T, "format")) {
    //                     //     try format(@as(ele.T, @ptrFromInt(ele.pointer)).*, fmt, options, writer);
    //                     // } else {
    //                     //     try writer.print("{}", .{@as(ele.T, @ptrFromInt(ele.pointer)).*});
    //                     // }
    //                 },
    //             }
    //         },
    //     }
    // }
};
pub const TagEnum = enum { edn, element };
pub const ErrorTag = mem.Allocator.Error || error{TypeNotSupported};
pub const SerializeError = mem.Allocator.Error || error{InvalidData};
pub const TagHandler = *const fn (allocator: mem.Allocator, edn: Edn) ErrorTag!*TagElement;
pub const TagElement = struct {
    pointer: *anyopaque,
    deinit: *const fn (pointer: *anyopaque, allocator: mem.Allocator) void,
    serialize: ?*const fn (pointer: *anyopaque, allocator: mem.Allocator) SerializeError![]const u8 = null,
};
pub const Tag = struct {
    tag: []const u8,
    data: union(TagEnum) { edn: *Edn, element: *TagElement },
};

pub const Symbol = []const u8;
pub const Keyword = []const u8;
