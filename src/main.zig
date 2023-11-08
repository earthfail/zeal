const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const ascii = std.ascii;
const expect = std.testing.expect;
const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch @panic("leaked");
    }
    _ = allocator;
    var it: Iterator = Iterator{ .buffer = "\\tab" };
    const s = it.next();
    std.debug.print("{?s} and i={d}\n", .{ s, it.index });

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

const Iterator = struct {
    buffer: []const u8,
    index: usize = 0,

    const Self = @This();

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
            // '\\' => blk: {
            //     if(self.peek_ch()) |c_peek|{
            //         switch(c_peek) {
            //             'c' =>
            //         }
            //     }else
            //         break :blk null;
            // },
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

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
