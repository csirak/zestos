const riscv = @import("riscv.zig");
const lib = @import("lib.zig");

const Self = @This();
interrupts_enabled: bool,
disabled_depth: u16,
var cpus: [riscv.NCPU]Self = undefined;

pub fn pushInterrupt(self: *Self) void {
    const old = riscv.intr_get();
    riscv.intr_off();
    if (self.disabled_depth == 0) {
        self.interrupts_enabled = old;
    }
    self.disabled_depth += 1;
}

pub fn popInterrupt(self: *Self) void {
    if (riscv.intr_get()) {
        lib.kpanic("interrupts are enabled");
    }
    if (self.disabled_depth == 0) {
        lib.kpanic("popping off empty");
    }
    self.disabled_depth -= 1;
    if (self.disabled_depth == 0 and self.interrupts_enabled) {
        riscv.intr_on();
    }
}

pub fn current() *Self {
    return &cpus[riscv.cpuid()];
}
