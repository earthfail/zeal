# Zeal
[edn](https://github.com/edn-format/edn) parser and serializer in zig
with faster parsing than standard `clojure.edn/read`[^2]

# Status
This is alpha software so expect bugs.
## TODO
- understand json.Scanner to improve performance. Currently scanner
  takes 1ms and edn lexer takes 6ms (about the same time as
  json.parser X_X) in debugg build but ReleaseFast they are the same
- decrease allocations.

## Usage
1. add `zeal` to `build.zig.zon`:

``` zig
.dependencies = .{
    ...
.zeal = .{
    .url = "https://github.com/earthfail/zeal/archive/v0.0.3.tar.gz",
    .hash = "1220335d9cb009618d8c1a7c1e099e64d6144b5d3021aa19fa90063879bef68c18ca",
    }
    ...
}
```
2. add `zeal` to `build.zig`:

``` zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // define exe for your use case
    const exe = b.addExecutable(.{
        .name = "project-name",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // add zeal as dependency
    const zeal = b.dependency("zeal", .{
        .optimize = optimize,
        .target = target,
    });
    exe.addModule("zeal", zeal.module("zeal"));
    b.installArtifact(exe);
    // rest of build.zig

```

3. import in your code:
``` zig
const zeal = @import("zeal");
```

## Example

``` zig
const std = @import("std");
const mem = std.mem;
const log = std.log;
const expect = std.testing.expect;
const zeal = @import("zeal");
const parser = zeal.parser;
const EdnReader = zeal.EdnReader;
const Edn = zeal.Edn;
const TagElement = zeal.TagElement;
const ErrorTag = zeal.ErrorTag;

/// simple function to read a line from user
/// taken from [ziglearn.org](https://ziglearn.org/chapter-2/#readers-and-writers) by [Sobeston](https://github.com/Sobeston)
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
// read edn from stdin
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
    // buffer to hold user input
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

            // define ednreader
            var reader = EdnReader.init(g_allocator, input);
            // initialize readers to tagged elements
            reader.data_readers = std.StringHashMap(parser.TagHandler).init(g_allocator);
            // define reader for #inst elements.
            try reader.data_readers.?.put("inst", edn_to_inst);
            defer reader.deinit();

            if (reader.readEdn()) |edn| {
                // try stdout.print("{}\n", .{edn.*});
                // convert edn to []const u8
                defer edn.deinit(g_allocator);
                const serialize = try parser.Edn.serialize(edn.*, g_allocator);
                defer g_allocator.free(serialize);

                try stdout.print("{s}\n", .{serialize});

            } else |err| {
                try stdout.print("got error parsing input {}. Salam\n", .{err});
                // break;
            }
        } else break;
    }
    try stdout.print("finished\n", .{});
}
/// given a integer in Edn form, returns a tagged element with that integer plus ten
fn edn_to_inst(allocator: mem.Allocator, edn: Edn) parser.ErrorTag!*TagElement {
    switch (edn) {
        .integer => |i| {
            var i_p = try allocator.create(@TypeOf(i));
            i_p.* = i + 10;
            var ele = try allocator.create(TagElement);
            ele.pointer = @intFromPtr(i_p);
            ele.deinit = inst_deinit;
            ele.serialize = inst_serialize;
            return ele;
        },
        else => {
            return ErrorTag.TypeNotSupported;
        },
    }
}
fn inst_deinit(pointer: usize, allocator: mem.Allocator) void {
    const i_p: *i64 = @ptrFromInt(pointer);
    allocator.destroy(i_p);
}
// specifiy how to convert data back to string
fn inst_serialize(pointer: usize, allocator: mem.Allocator) parser.SerializeError![]const u8 {
    const i_p: *i64 = @ptrFromInt(pointer);
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    const writer = buffer.writer();
    writer.print("{d}", .{i_p.*}) catch return parser.SerializeError.InvalidData;
    return buffer.toOwnedSlice();
}
pub fn main() !void {
    try repl_edn();
}
```

[^2]: tested on
    [json64KB](https://microsoftedge.github.io/Demos/json-dummy-data/64KB.json)
    converted to edn with `(spit "64KB.edn" data)` and `zig build -Doptimize=ReleaseFast`
