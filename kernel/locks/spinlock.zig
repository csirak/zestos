const Cpu = @import("../cpu.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");

const Self = @This();

locked: bool,
name: []const u8,
cpu: *Cpu,

pub fn init(name: []const u8) Self {
    return Self{
        .locked = false,
        .name = name,
        .cpu = undefined,
    };
}

pub fn acquire(self: *Self) void {
    var c = Cpu.current();
    c.pushInterrupt();

    if (self.haveLock()) {
        lib.kpanic("Spinlock already locked");
    }
    while (riscv.atomic_swap(&self.locked, @intFromBool(true)) != 0) {}
    riscv.fence();
    self.cpu = c;
}

pub fn release(self: *Self) void {
    if (!self.haveLock()) {
        lib.kpanic("Spinlock not held");
    }
    self.locked = false;
    self.cpu = undefined;
    riscv.fence();

    _ = riscv.atomic_swap(&self.locked, 0);
    var c = Cpu.current();
    c.popInterrupt();
}

pub inline fn haveLock(self: *Self) bool {
    return self.locked and self.cpu == Cpu.current();
}
