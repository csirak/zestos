const std = @import("std");
const lib = @import("../../lib.zig");
const fs = @import("../../fs/fs.zig");
const Buffer = @import("../../fs/buffer.zig");

pub fn matchName(name: []const u8, source: []u8) bool {
    if (source.len < name.len) return false;

    for (name, 0..) |c, i| {
        if (source[i] != c) {
            return false;
        }
    }
    return true;
}

pub fn cleanSource(source: []u8) []u8 {
    var i: usize = 0;
    while (i < source.len and source[i] == ' ') : (i += 1) {}
    return source[i..];
}

pub fn parseNum(source: []u8) ?usize {
    const nums = "0123456789";
    const alphas = "abcdefABCDEF";
    const prefix = "0x";
    const is_hex = matchName(prefix, source);

    const src = if (is_hex) source[prefix.len..] else source;

    for (src, 0..) |c, i| {
        if (c == ' ') {
            return if (is_hex) i + prefix.len else i;
        }
        const is_num = std.mem.indexOfScalar(u8, nums, c);
        const is_alpha = std.mem.indexOfScalar(u8, alphas, c);

        if (is_num != null or (is_hex and is_alpha != null)) continue else return null;
    }
    return source.len;
}

pub fn nextToken(source: []u8) []u8 {
    for (source, 0..) |c, i| {
        if (c == ' ') {
            return source[0..i];
        }
    }
}

pub fn loadBlock(device: u16, num: u16) fs.Block {
    const static = struct {
        var buffer: Buffer = undefined;
    };
    static.buffer.loadFromDisk(device, num);
    return static.buffer.data;
}

pub fn log(s: []const u8) void {
    lib.print(s);
}

pub fn logln(s: []const u8) void {
    lib.println(s);
}

pub fn logf(comptime s: []const u8, args: anytype) void {
    lib.printf(s, args);
}
