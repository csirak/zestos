const lib = @import("../lib.zig");
const Spinlock = @import("../locks/spinlock.zig");
const Process = @import("../procs/proc.zig");
const Device = @import("../device.zig");

const Self = @This();

var lock: Spinlock = Spinlock.init("console");

pub fn init() void {
    Device.registerDevice(getDevice());
}

pub fn println(s: []const u8) void {
    lock.acquire();
    lib.println(s);
    lock.release();
}

pub fn print(s: []const u8) void {
    lock.acquire();
    lib.print(s);
    lock.release();
}

pub fn printInt(i: u64) void {
    lock.acquire();
    lib.printInt(i);
    lock.release();
}

pub inline fn printAndInt(s: []const u8, n: u64) void {
    lock.acquire();
    lib.printAndInt(s, n);
    lock.release();
}

pub fn printAndDec(s: []const u8, n: u64) void {
    lock.acquire();
    lib.printAndDec(s, n);
    lock.release();
}

pub fn coreLog(comptime s: []const u8) void {
    lock.acquire();
    lib.coreLog(s);
    lock.release();
}

pub fn kpanic(comptime s: []const u8) void {
    lock.acquire();
    lib.kpanic(s);
    lock.release();
}

pub fn write(_: *Self, user_ptr: u64, size: u64) !void {
    const proc = Process.currentOrPanic();

    for (0..size) |i| {
        var byte: [1]u8 = undefined;
        try proc.pagetable.?.copyFrom(user_ptr + i, &byte, 1);
        lib.putChar(byte[0]);
    }
}

pub fn getDevice() Device {
    return .{
        .ptr = undefined,
        .writeAllFn = @ptrCast(&write),
        .major = 1,
    };
}
