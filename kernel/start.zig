extern fn main() void;
const riscv = @import("riscv.zig");

export fn start() noreturn {
    const mstatus = riscv.r_mstatus();
    const set_mstatus = ((mstatus & ~riscv.MSTATUS_MPP_MASK) | riscv.MSTATUS_MPP_S) | riscv.MSTATUS_MIE;
    riscv.w_mstatus(set_mstatus);

    riscv.w_mepc(@intFromPtr(&main));
    riscv.w_satp(0);

    // delegate all interrupts and exceptions to supervisor mode.
    riscv.w_medeleg(0xffff);
    riscv.w_mideleg(0xffff);
    riscv.w_sie(riscv.r_sie() | riscv.SIE_SEIE | riscv.SIE_STIE | riscv.SIE_SSIE);

    riscv.w_pmpaddr0(0x3fffffffffffff);
    riscv.w_pmpcfg0(0xf);

    riscv.w_tp(riscv.r_tp());

    riscv.mret();
    unreachable;
}
