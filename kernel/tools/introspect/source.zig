const std = @import("std");
const utils = @import("utils.zig");

src: []u8,
pos: u64,

const Self = @This();

pub fn init(src: []u8) Self {
    return Self{ .src = src, .pos = 0 };
}

pub fn isNext(self: *Self, iden: []const u8) bool {
    self.clean();

    if (self.src.len - self.pos < iden.len) return false;

    const src = self.src[self.pos..];
    for (iden, 0..) |c, i| {
        if (src[i] != c) {
            return false;
        }
    }
    return true;
}

pub fn matchIden(self: *Self, iden: []const u8) ?void {
    if (!self.isNext(iden)) return null;
    self.pos += iden.len;
}

pub fn matchNum(self: *Self) ?void {
    self.clean();
    if (self.src.len - self.pos < 1) return null;

    const prefix = "0x";
    const is_hex = self.matchIden(prefix) == null;

    for (self.src[self.pos..]) |c| {
        if (c == ' ') return;
        const nums = "0123456789";
        const alphas = "abcdefABCDEF";
        const is_num = std.mem.indexOfScalar(u8, nums, c) != null;
        const is_alpha = std.mem.indexOfScalar(u8, alphas, c) != null;

        if (!is_num and !(is_hex and is_alpha)) return null;
    }
}

pub fn getNum(self: *Self, Size: type) ?Size {
    const src = self.src[self.pos..];
    const len = self.nextSpace();

    defer self.pos += len;
    return std.fmt.parseUnsigned(Size, src[0..len], 0) catch |e| {
        utils.logf("Parse Error: {s} {}", .{ src, e });
        return null;
    };
}

fn nextSpace(self: *Self) u64 {
    for (self.src[self.pos..], 0..) |c, i| {
        if (c == ' ') {
            return i;
        }
    }
    return self.src.len - self.pos;
}

fn clean(self: *Self) void {
    while (self.pos < self.src.len and self.src[self.pos] == ' ') : (self.pos += 1) {}
}
