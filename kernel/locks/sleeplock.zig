const lib = @import("../lib.zig");

const Cpu = @import("../cpu.zig");
const Spinlock = @import("spinlock.zig");
const Process = @import("../procs/proc.zig");

const Self = @This();

lock: Spinlock,
locked: bool,
name: []const u8,
id: u64 = 0,
pid: u64,

pub fn init(name: []const u8) Self {
    return Self{
        .lock = Spinlock.init("sleep lock"),
        .locked = false,
        .name = name,
        .pid = 0,
    };
}

pub fn initId(name: []const u8, id: u64) Self {
    return Self{
        .lock = Spinlock.init("sleep lock"),
        .locked = false,
        .name = name,
        .id = id,
        .pid = 0,
    };
}

pub fn acquire(self: *Self) void {
    self.lock.acquire();
    // lib.print("Acquiring sleeplock: ");
    // lib.print(self.name);
    // lib.print(" id: ");
    // lib.printByte(@intCast(self.id));
    // lib.println("");

    const proc = Process.currentOrPanic();
    while (self.locked) {
        lib.println("Sleeping");
        proc.sleep(self, &self.lock);
    }
    self.locked = true;
    self.pid = proc.getPid();
    self.lock.release();
}

pub fn release(self: *Self) void {
    self.lock.acquire();
    // lib.print("Releasing sleeplock: ");
    // lib.print(self.name);
    // lib.print(" id: ");
    // lib.printByte(@intCast(self.id));
    // lib.println("");

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
