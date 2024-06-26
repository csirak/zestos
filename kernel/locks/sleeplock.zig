const lib = @import("../lib.zig");

const Spinlock = @import("spinlock.zig");
const Process = @import("../procs/proc.zig");

const Self = @This();

lock: Spinlock,
locked: bool,
name: []const u8,
pid: u64,

pub fn init(name: []const u8) Self {
    return Self{
        .lock = Spinlock.init("sleep lock"),
        .locked = false,
        .name = name,
        .pid = 0,
    };
}

pub fn acquire(self: *Self) void {
    self.lock.acquire();
    defer self.lock.release();

    const proc = Process.currentOrPanic();

    while (self.locked) {
        proc.sleep(self, &self.lock);
    }
    self.locked = true;
    self.pid = proc.getPid();
}

pub fn release(self: *Self) void {
    self.lock.acquire();
    defer self.lock.release();
    self.locked = false;
    self.pid = 0;

    Process.wakeup(self);
}

pub fn isHolding(self: *Self) bool {
    self.lock.acquire();
    defer self.lock.release();
    return self.locked and self.pid == Process.currentOrPanic().getPid();
}
