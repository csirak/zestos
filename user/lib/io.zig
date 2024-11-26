const std = @import("std");
const write = @import("syscalls.zig").write;
const PGSIZE = 4096;
var print_buffer = [_]u8{0} ** (PGSIZE);
var print_fba = std.heap.FixedBufferAllocator.init(&print_buffer);
const print_allocator = print_fba.allocator();

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    const out = std.fmt.allocPrint(print_allocator, fmt, args) catch unreachable;
    _ = write(1, out.ptr, out.len);
}
