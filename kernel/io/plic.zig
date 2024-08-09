const riscv = @import("../riscv.zig");

inline fn plicSupervisorEnableAddr(coreId: u64) *u32 {
    return @ptrFromInt(riscv.PLIC + 0x2080 + (coreId) * 0x100);
}
inline fn plicSupervisorPriorityAddr(coreId: u64) *u32 {
    return @ptrFromInt(riscv.PLIC + 0x201000 + (coreId) * 0x2000);
}

pub fn init() void {
    const uart_irq_addr: *volatile u32 = @ptrFromInt(riscv.PLIC + riscv.UART0_IRQ * 4);
    const virtio_irq_addr: *volatile u32 = @ptrFromInt(riscv.PLIC + riscv.VIRTIO0_IRQ * 4);

    uart_irq_addr.* = 1;
    virtio_irq_addr.* = 1;
}

pub fn coreInit() void {
    const coreId = riscv.cpuid();

    plicSupervisorEnableAddr(coreId).* = (1 << riscv.UART0_IRQ) | (1 << riscv.VIRTIO0_IRQ);
    plicSupervisorPriorityAddr(coreId).* = 0;
}
