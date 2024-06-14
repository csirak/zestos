const riscv = @import("../riscv.zig");

pub inline fn pageAlignUp(a: u64) u64 {
    const ps: u64 = riscv.PGSIZE;
    return ((a + ps - 1) & ~(ps - 1));
}

pub inline fn pageAlignDown(a: u64) u64 {
    const ps: u64 = riscv.PGSIZE;

    return ((a) & ~(ps - 1));
}

pub const PTE_V = (1 << 0);
pub const PTE_R = (1 << 1);
pub const PTE_W = (1 << 2);
pub const PTE_X = (1 << 3);
pub const PTE_U = (1 << 4);
