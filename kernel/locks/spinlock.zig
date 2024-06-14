const Cpu = @import("../cpu.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");

const Self = @This();

locked: bool,
name: []const u8,
cpu: ?*Cpu,

pub fn init(name: []const u8) Self {
    return Self{
        .locked = false,
        .name = name,
        .cpu = null,
    };
}

pub fn acquire(self: *Self) void {
    var c = Cpu.current();
    c.pushInterrupt();
    if (self.haveLock()) {
        lib.kpanic("Spinlock already locked");
    }

    var v = riscv.atomic_swap(&self.locked, 1);
    while (v != 0) {
        v = riscv.atomic_swap(&self.locked, 1);
    }

    riscv.fence();
    self.cpu = c;
}

pub fn release(self: *Self) void {
    if (!self.haveLock()) {
        lib.kpanic("Spinlock not held");
    }
    self.cpu = null;
    riscv.fence();

    riscv.atomic_write_zero(&self.locked);
    Cpu.current().popInterrupt();
}

pub inline fn haveLock(self: *Self) bool {
    return self.locked and self.cpu == Cpu.current();
}
