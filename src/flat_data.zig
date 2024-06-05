//! generate flat data with know types and positions with each record on separate line
//! used to set a base line for what is the fastest trivial data to parse (and not in binary format because I am new)
const std = @import("std");
const expect = std.testing.expect;
const process = std.process;
const fs = std.fs;
// TODO(Salim): Figure out how zig build works for the seven millionth time
const parser = @import("parser.zig");
const EdnReader = parser.EdnReader;
const Edn = parser.Edn;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch {
            @panic("gpa leaked");
        };
    }
    const args = try process.argsAlloc(g_allocator);
    defer process.argsFree(g_allocator, args);

    const file_name = if (args.len > 1) args[1] else "resources/64KB.edn";
    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();

    const reader = file.reader();
    var list = std.ArrayList(u8).init(g_allocator);
    try reader.readAllArrayList(&list, 1000 * 1000 * 1000);
    const input = try list.toOwnedSlice();
    defer g_allocator.free(input);
    var edn_reader = try EdnReader.init(g_allocator, input);

    var edn = try edn_reader.readEdn();
    defer edn.deinit(g_allocator);

    switch (edn) {
        .list, .vector => |v| {
            var result_file = try fs.cwd().createFile("resources/64KB.txt", .{});
            std.debug.print("creating a file resources/64KB.txt\n", .{});
            defer result_file.close();

            for (v.items) |rcrd| {
                switch (rcrd) {
                    .hashmap => |record| {
                        var iterator = record.iterator();
                        var first: bool = true;
                        while (iterator.next()) |entry| {
                            const value = try Edn.serialize(entry.value_ptr.*, g_allocator);
                            defer g_allocator.free(value);
                            if (!first) {
                                try result_file.writeAll(" ");
                            } else {
                                first = false;
                            }
                            try result_file.writeAll(value);
                        }
                        try result_file.writeAll("\n");
                    },
                    else => {
                        std.debug.print("expect record to be a hashmap got {}\n", .{rcrd});
                        return;
                    },
                }
            }
        },
        else => {
            std.debug.print("need data to be in a vector\n", .{});
            return;
        },
    }
}
