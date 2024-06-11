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
