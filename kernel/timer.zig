const Spinlock = @import("locks/spinlock.zig");

pub var ticks: u64 = 0;
pub var lock: Spinlock = undefined;

pub fn init() void {
    lock = Spinlock.init("time");
}

pub fn tick() void {
    lock.acquire();
    defer lock.release();
    ticks += 1;
}

pub fn getTick() u64 {
    lock.acquire();
    defer lock.release();
    return ticks;
}
