const Spinlock = @import("locks/spinlock.zig");
const riscv = @import("riscv.zig");

var ticks: u64 = 0;
const tickslock = Spinlock.init("time");

export fn kerneltrap() void {}

extern fn kernelvec() void;

pub fn coreInit() void {
    riscv.w_stvec(@intFromPtr(&kernelvec));
}
