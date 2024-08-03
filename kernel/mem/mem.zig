const riscv = @import("../riscv.zig");

pub inline fn pageAlignUp(a: u64) u64 {
    const ps: u64 = riscv.PGSIZE;
    return ((a + ps - 1) & ~(ps - 1));
}

pub inline fn pageAlignDown(a: u64) u64 {
    const ps: u64 = riscv.PGSIZE;

    return ((a) & ~(ps - 1));
}

pub inline fn pageOffset(a: u64) u64 {
    const ps: u64 = riscv.PGSIZE;
    return (a & (ps - 1));
}

// use riscv's sv39 page table scheme.
const SATP_SV39: u64 = (8 << 60);

pub inline fn MAKE_SATP(pagetable_address: u64) u64 {
    return SATP_SV39 | (pagetable_address >> 12);
}

pub inline fn GET_SATP(satp: u64) u64 {
    return (satp & ~SATP_SV39) << 12;
}

pub const PTE_V = (1 << 0);
pub const PTE_R = (1 << 1);
pub const PTE_W = (1 << 2);
pub const PTE_X = (1 << 3);
pub const PTE_U: u8 = (1 << 4);
