const riscv = @import("../riscv.zig");

pub inline fn pageAlignUp(a: u64) u64 {
    const ps: u64 = riscv.PGSIZE;
    return ((a + ps - 1) & ~(ps - 1));
}

pub inline fn pageAlignDown(a: u64) u64 {
    return ((a) & ~(riscv.PGSIZE - 1));
}
