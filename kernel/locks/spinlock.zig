const Cpu = @import("../cpu.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");
const builtin = @import("std").builtin;

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
        lib.println(self.name);
        lib.kpanic("Spinlock already locked");
    }

    while (@atomicRmw(bool, &self.locked, .Xchg, true, .acquire)) {}
    @fence(.seq_cst);

    self.cpu = c;
}

pub fn release(self: *Self) void {
    if (!self.haveLock()) {
        lib.print(self.name);
        lib.kpanic("Spinlock not held");
    }
    self.cpu = null;
    riscv.fence();

    @atomicStore(bool, &self.locked, false, .release);
    Cpu.current().popInterrupt();
}

pub inline fn haveLock(self: *Self) bool {
    return self.locked and self.cpu == Cpu.current();
}
