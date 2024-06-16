const Spinlock = @import("locks/spinlock.zig");
const riscv = @import("riscv.zig");

var ticks: u64 = 0;
var tickslock: Spinlock = undefined;

export fn kerneltrap() void {}

extern fn kernelvec() void;

pub fn init() void {
    tickslock = Spinlock.init("time");
}

pub fn coreInit() void {
    riscv.w_stvec(@intFromPtr(&kernelvec));
}
