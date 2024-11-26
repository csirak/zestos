const main = @import("main.zig").main;
const riscv = @import("riscv.zig");
const lib = @import("lib.zig");
const std = @import("std");
const Process = @import("procs/proc.zig");

export var timer_scratch = [_]u64{0} ** (riscv.NCPU * 5);

export fn start() noreturn {
    const mstatus = riscv.r_mstatus();
    const set_mstatus = ((mstatus & ~riscv.MSTATUS_MPP_MASK) | riscv.MSTATUS_MPP_S) | riscv.MSTATUS_MIE;
    riscv.w_mstatus(set_mstatus);

    riscv.w_mepc(@intFromPtr(&main));
    riscv.w_satp(0);

    riscv.w_medeleg(0xffff);
    riscv.w_mideleg(0xffff);
    riscv.w_sie(riscv.r_sie() | riscv.SIE_SEIE | riscv.SIE_STIE | riscv.SIE_SSIE);

    riscv.w_pmpaddr0(0x3fffffffffffff);
    riscv.w_pmpcfg0(0xf);

    timerInit();

    riscv.w_tp(riscv.r_mhartid());

    riscv.mret();
    unreachable;
}

extern fn timervec() void;

inline fn timerInit() void {
    const tid = riscv.r_mhartid();
    const clint_mtimecmp: *u64 = riscv.CLINT_MTIMECMP(tid);
    clint_mtimecmp.* = riscv.CLINT_MTIME.* + riscv.TIMER_INTERVAL;

    var timer_scratch_2d: *[riscv.NCPU][5]u64 = @ptrCast(&timer_scratch);
    timer_scratch_2d[tid][3] = @intFromPtr(clint_mtimecmp);
    timer_scratch_2d[tid][4] = riscv.TIMER_INTERVAL;
    riscv.w_mscratch(@intFromPtr(&timer_scratch_2d[tid]));

    riscv.w_mtvec(@intFromPtr(&timervec));
    riscv.w_mstatus(riscv.r_mstatus() | riscv.MSTATUS_MIE);
    riscv.w_mie(riscv.r_mie() | riscv.MIE_MTIE);
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    const ra = @returnAddress();
    const proc = Process.current();
    if (proc) |p| {
        lib.printf("pid: {}\n", .{p.getPid()});
        lib.printf("epc: {}\n", .{p.trapframe.?.epc});
    }
    lib.printf("stack: 0x{x}\n", .{riscv.r_sp()});
    lib.printf("stval: 0x{x}\n", .{riscv.r_stval()});
    lib.printf("sepc: 0x{x}\n", .{riscv.r_sepc()});
    lib.printf("ra: 0x{x}\n", .{ra});
    lib.printf("a0: 0x{x}\n", .{riscv.r_a0()});
    lib.printf("cause: 0x{x}\n", .{riscv.r_scause()});
    lib.kpanic(msg);
}
