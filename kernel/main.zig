const lib = @import("lib.zig");
const std = @import("std");

extern var end: [*]u8;
extern var timer_scratch: *u64;

fn intToString(int: u64, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "0x{x}", .{int}) catch "";
}

pub export fn main() void {
    var buf: [20]u8 = undefined;
    const ptr: *u64 = @ptrFromInt(@intFromPtr(&timer_scratch) + 3 * @sizeOf(u64));
    const s = intToString(ptr.*, &buf);

    lib.print("Hello, World!");
    lib.print(s);
}
