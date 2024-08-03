pub const NCPU = 4;
pub const PGSIZE: u64 = 4096; // bytes per page

pub const TIMER_INTERVAL = 1000000;
pub const CLINT: u64 = 0x2000000;
pub const CLINT_MTIME: *u64 = @ptrFromInt(CLINT + 0xBFF8);

pub inline fn CLINT_MTIMECMP(hartid: u64) *u64 {
    return @ptrFromInt(CLINT + 0x4000 + 8 * (hartid));
}

pub const MAXVA: u64 = (1 << (9 + 9 + 9 + 12 - 1));
pub const KERNBASE: u64 = 0x80000000;
pub const PHYSTOP: u64 = (KERNBASE + 128 * 1024 * 1024);

// map the trampoline page to the highest address,
// in both user and kernel space.
pub const TRAMPOLINE: u64 = (MAXVA - PGSIZE);
pub const TRAPFRAME: u64 = (TRAMPOLINE - PGSIZE);

// map kernel stacks beneath the trampoline,
// each surrounded by invalid guard pages.
pub inline fn KSTACK(p: u64) u64 {
    return TRAMPOLINE - ((p) + 1) * 2 * PGSIZE;
}

pub const MSTATUS_MPP_MASK: u64 = 3 << 11;
pub const MSTATUS_MPP_M: u64 = 3 << 11;
pub const MSTATUS_MPP_S: u64 = 1 << 11;
pub const MSTATUS_MPP_U: u64 = 0 << 11;
pub const MSTATUS_MIE: u64 = 1 << 3;

// Supervisor Interrupt Enable
pub const SIE_SEIE: u64 = 1 << 9; // external
pub const SIE_STIE: u64 = 1 << 5; // timer
pub const SIE_SSIE: u64 = 1 << 1; // software

pub inline fn r_mhartid() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], mhartid"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn r_mstatus() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], mstatus"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn w_mstatus(x: u64) void {
    asm volatile ("csrw mstatus, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn w_mepc(x: u64) void {
    asm volatile ("csrw mepc, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn mret() void {
    asm volatile ("mret");
}

pub inline fn w_satp(x: u64) void {
    asm volatile ("csrw satp, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn r_medeleg() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], medeleg"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn w_medeleg(x: u64) void {
    asm volatile ("csrw medeleg, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn r_mideleg() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], mideleg"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn w_mideleg(x: u64) void {
    asm volatile ("csrw mideleg, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn r_sie() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], sie"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn w_sie(x: u64) void {
    asm volatile ("csrw sie, %[x]"
        :
        : [x] "r" (x),
    );
}

// Physical Memory Protection
pub inline fn w_pmpcfg0(x: u64) void {
    asm volatile ("csrw pmpcfg0, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn w_pmpaddr0(x: u64) void {
    asm volatile ("csrw pmpaddr0, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn fence() void {
    asm volatile ("fence");
}

pub inline fn fence_iorw() void {
    asm volatile ("fence iorw, iorw");
}

pub fn cpuid() u64 {
    return r_tp();
}

pub inline fn r_tp() u64 {
    var x: u64 = 0;
    asm volatile ("mv %[x], tp"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn w_tp(x: u64) void {
    asm volatile ("mv tp, %[x]"
        :
        : [x] "r" (x),
    );
}

pub inline fn w_mscratch(x: u64) void {
    asm volatile ("csrw mscratch, %[x]"
        :
        : [x] "r" (x),
    );
}
