pub const Page = *[PGSIZE]u8;

pub const NCPU = 4;
pub const MAX_PROCS = 64;
pub const PGSIZE = 4096; // bytes per page

pub const UART0: u64 = 0x10000000;
pub const UART0_IRQ: u64 = 10;

pub const VIRTIO0: u64 = 0x10001000;
pub const VIRTIO0_IRQ: u64 = 1;

pub const CLINT: u64 = 0x2000000;
pub const PLIC: u64 = 0x0c000000;
pub const KERNBASE: u64 = 0x80000000;

pub const PLIC_SIZE = 0x400000;
pub const TIMER_INTERVAL = 1000000;
pub const CLINT_MTIME: *u64 = @ptrFromInt(CLINT + 0xBFF8);

pub inline fn CLINT_MTIMECMP(hartid: u64) *u64 {
    return @ptrFromInt(CLINT + 0x4000 + 8 * (hartid));
}

pub const MAXVA: u64 = (1 << (9 + 9 + 9 + 12 - 1));
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

// Machine Status Register, mstatus
pub const MSTATUS_MPP_MASK: u64 = 3 << 11;
pub const MSTATUS_MPP_M: u64 = 3 << 11;
pub const MSTATUS_MPP_S: u64 = 1 << 11;
pub const MSTATUS_MPP_U: u64 = 0 << 11;
pub const MSTATUS_MIE: u64 = 1 << 3;

// Machine-mode Interrupt Enable
pub const MIE_MEIE: u64 = 1 << 11; // external
pub const MIE_MTIE: u64 = 1 << 7; // timer
pub const MIE_MSIE: u64 = 1 << 3; // software

// Supervisor Interrupt Enable
pub const SIE_SEIE: u64 = 1 << 9; // external
pub const SIE_STIE: u64 = 1 << 5; // timer
pub const SIE_SSIE: u64 = 1 << 1; // software

// Supervisor Status Register, sstatus
pub const SSTATUS_SPP: u64 = 1 << 8; // Previous mode, 1=Supervisor, 0=User
pub const SSTATUS_SPIE: u64 = 1 << 5; // Supervisor Previous Interrupt Enable
pub const SSTATUS_UPIE: u64 = 1 << 4; // User Previous Interrupt Enable
pub const SSTATUS_SIE: u64 = 1 << 1; // Supervisor Interrupt Enable
pub const SSTATUS_UIE: u64 = 1 << 0; // User Interrupt Enable

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

pub inline fn r_sstatus() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], sstatus"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn w_sstatus(x: u64) void {
    asm volatile ("csrw sstatus, %[x]"
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

pub inline fn r_mie() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], mie"
        : [x] "=r" (x),
    );
    return x;
}

pub inline fn w_mie(x: u64) void {
    asm volatile ("csrw mie, %[x]"
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

// Supervisor device interrupts
pub inline fn intr_on() void {
    w_sstatus(r_sstatus() | SSTATUS_SIE);
}
pub inline fn intr_off() void {
    w_sstatus(r_sstatus() & ~SSTATUS_SIE);
}

pub inline fn intr_get() bool {
    return (r_sstatus() & SSTATUS_SIE) != 0;
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

pub inline fn flush_tlb() void {
    asm volatile ("sfence.vma zero, zero");
}

pub inline fn atomic_swap(ptr: anytype, val: u64) u64 {
    var out: u64 = undefined;
    asm volatile ("amoswap.w.aq %[old], %[val], (%[ptr])"
        : [old] "=r" (out),
        : [ptr] "r" (ptr),
          [val] "r" (val),
    );
    return out;
}

pub inline fn atomic_write_zero(ptr: anytype) void {
    asm volatile ("amoswap.w zero, zero, (%[ptr])"
        :
        : [ptr] "r" (ptr),
    );
}

pub inline fn w_satp(x: u64) void {
    asm volatile ("csrw satp, %[x]"
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

// Machine-mode interrupt vector
pub inline fn w_mtvec(x: u64) void {
    asm volatile ("csrw mtvec, %[x]"
        :
        : [x] "r" (x),
    );
}

// Supervisor-mode trap vector
pub inline fn w_stvec(x: u64) void {
    asm volatile ("csrw stvec, %[x]"
        :
        : [x] "r" (x),
    );
}

// Hartid and Thread Pointer

pub inline fn r_mhartid() u64 {
    var x: u64 = 0;
    asm volatile ("csrr %[x], mhartid"
        : [x] "=r" (x),
    );
    return x;
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
