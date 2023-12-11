# Zeal
[edn](https://github.com/edn-format/edn) parser and serializer in zig

# Status
This is alpha software so expect bugs.

## Usage
1. add `zeal` to `build.zig.zon`:

``` zig
.dependencies = .{
    ...
.zeal = .{
            .url = "https://github.com/earthfail/zeal/archive/v0.0.1.tar.gz",
    }
    ...
}
```
then run `zig build` to get a hash mismatch. Add this hash to `.hash`
field next to `.url` field above.
2. add `zeal` to `build.zig`:

``` zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    ....
    const zeal = b.dependency("zeal", .{
        .optimize = optimize,
        .target = target,
    });
    // for exe, lib, tests, etc.
    exe.addModule("zeal", zeal.module("zeal"));
    ....
```

3. import in your code:
``` zig

const std = @import("std");
const zeal = @import("zeal");
fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(
        buffer,
        '\n',
    )) orelse return null;
    // trim annoying windows-only carriage return character
    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    } else {
        return line;
    }
}
fn repl_edn() !void {
    var gpa = std.heap.GeneralPurposeAllocator(
    //.{ .verbose_log = true, .retain_metadata = true }
    .{}){};
    const g_allocator = gpa.allocator();
    defer {
        // _ = gpa.detectLeaks();

        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch {
            @panic("gpa leaked");
        };
    }

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buffer: [2000]u8 = undefined;
    try stdout.writeAll("edn is an extensible data notation\n");
    while (true) {
        try stdout.print("reading input:", .{});
        if (try nextLine(stdin, &buffer)) |input| {
            defer {
                if (gpa.detectLeaks()) {
                    std.debug.print("gpa detected leaks with input '{s}'\n", .{input});
                }
            }
            // const allocator = arena.allocator();
            var reader = EdnReader.init(g_allocator, input);
            reader.data_readers = std.StringHashMap(parser.TagHandler).init(g_allocator);
            try reader.data_readers.?.put("inst", edn_to_inst);
            defer reader.deinit();
            // if (EdnReader.readEdn(allocator, &iter)) |edn| {
            if (reader.readEdn()) |edn| {
                log.info("address {*} type {s}, value:", .{ edn, @tagName(edn.*) });
                // log.info("edn from log {}\n",.{edn.*});
                // try stdout.print("{}\n", .{edn.*});
                const serialize = try parser.Edn.serialize(edn.*, g_allocator);
                defer g_allocator.free(serialize);

                try stdout.print("{s}\n", .{serialize});

                edn.deinit(g_allocator);
            } else |err| {
                try stdout.print("got error parsing input {}. Salam\n", .{err});
                // break;
            }
        } else break;
    }
    try stdout.print("finished\n", .{});
}

```
