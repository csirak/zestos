const std = @import("std");
const Process = @import("procs/proc.zig");
const Introspect = @import("tools/introspect/main.zig");

const riscv = @import("riscv.zig");
const lib = @import("lib.zig");

const main = @import("main.zig").main;

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
    const clint_mtimecmp = riscv.CLINT_MTIMECMP(tid);
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
    const fp = riscv.r_fp();
    lib.printf("panic: {s}\n", .{msg});
    lib.printf("ra: 0x{x}\n", .{ra});
    Introspect.init(ra, fp) catch |e| lib.printf("Introspection error: {}\n", .{e});
    while (true) {}
}
