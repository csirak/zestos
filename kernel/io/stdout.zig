const lib = @import("../lib.zig");
const Spinlock = @import("../locks/spinlock.zig");

var lock: Spinlock = Spinlock.init("console");

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

pub fn coreLog(comptime s: []const u8) void {
    lock.acquire();
    lib.coreLog(s);
    lock.release();
}
