const std = @import("std");
const process = std.process;
const fs = std.fs;

const tracy = @import("tracy");

pub fn main() !void {
    // var t = try std.time.Timer.start();
    tracy.setThreadName("json");
    defer tracy.message("json thread exit");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var os_allocator = tracy.TracingAllocator.initNamed("json_gpa", gpa.allocator());
    const allocator = os_allocator.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    // const file_name = if (args.len > 1) args[1] else return error.needFile;
    const file_name = "resources/64KB.json";
    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();

    // var buf_reader = std.io.bufferedReader(file.reader());
    // const reader = buf_reader.reader();
    const reader = file.reader();

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try reader.readAllArrayList(&list, 1000 * 1000 * 1000);

    const input = try list.toOwnedSlice();
    defer allocator.free(input);

    const stdout = std.io.getStdOut().writer();
    // const Record = struct { name: []u8, language: []u8, id: []u8, bio: []u8, version: f64 };
    var t = try std.time.Timer.start();

    tracy.frameMark();
    const zone = tracy.initZone(@src(), .{ .name = "json reader" });

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();
    try stdout.print("{}\n", .{parsed.value.array.items.len});
    std.debug.print("{}\n", .{@as(f64, @floatFromInt(t.read())) / 1000_000});
    zone.deinit();
    const stdin = std.io.getStdIn().reader();
    const b = try stdin.readByte();
    std.debug.print("got b {}\n", .{b});
}
