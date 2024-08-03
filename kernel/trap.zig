const riscv = @import("riscv.zig");
const lib = @import("lib.zig");

const Spinlock = @import("locks/spinlock.zig");
const StdOut = @import("io/stdout.zig");
const Procedure = @import("procs/proc.zig");

var ticks: u64 = 0;
var tickslock: Spinlock = undefined;

extern fn kernelvec() void;
extern fn uservec() void;
extern fn userret() void;
extern fn trampoline() void;

export fn kerneltrap() void {}

pub fn init() void {
    tickslock = Spinlock.init("time");
}

pub fn coreInit() void {
    riscv.w_stvec(@intFromPtr(&kernelvec));
}

pub fn userTrap() void {
    const proc = Procedure.current();
    lib.printInt(proc.trapframe.?.a7);
}

pub fn userTrapReturn() void {
    var proc = Procedure.current();
    // deactivate until in user mode
    riscv.intr_off();

    const user_vec_trampoline = riscv.TRAMPOLINE + @intFromPtr(&uservec) - @intFromPtr(&trampoline);
    riscv.w_stvec(user_vec_trampoline);

    proc.trapframe.?.kernel_satp = riscv.r_satp();
    proc.trapframe.?.kernel_sp = proc.kstackPtr + riscv.PGSIZE;
    proc.trapframe.?.kernel_trap = @intFromPtr(&userTrap);
    proc.trapframe.?.kernel_hartid = riscv.r_tp();

    // turn on user interrupts and set previous mode
    const sstatus = riscv.r_sstatus();
    const user_sstatus = (sstatus & ~riscv.SSTATUS_SPP) | riscv.SSTATUS_SPIE;
    riscv.w_sstatus(user_sstatus);

    riscv.w_sepc(proc.trapframe.?.epc);
    const satp = proc.pagetable.?.getAsSatp();

    const user_ret_trampoline = riscv.TRAMPOLINE + @intFromPtr(&userret) - @intFromPtr(&trampoline);
    const user_ret: *const fn (u64) void = @ptrFromInt(user_ret_trampoline);

    user_ret(satp);
}
