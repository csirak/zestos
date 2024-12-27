const std = @import("std");
const write = @import("syscalls.zig").write;

const PGSIZE = 4096;

var print_buffer = [_]u8{0} ** (PGSIZE);
var print_fba = std.heap.FixedBufferAllocator.init(&print_buffer);
const print_allocator = print_fba.allocator();

pub fn fprintf(fd: u64, comptime fmt: []const u8, args: anytype) void {
    const out = std.fmt.allocPrint(print_allocator, fmt, args) catch unreachable;
    _ = write(fd, out.ptr, out.len);
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    fprintf(1, fmt, args);
}

pub fn print(s: []const u8) void {
    _ = write(1, @constCast(s.ptr), s.len);
}

pub fn errPrint(s: []const u8) void {
    _ = write(2, s.ptr, s.len);
}
