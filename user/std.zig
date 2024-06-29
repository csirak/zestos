const kernel_syscall = @import("../kernel/procs/syscall.zig");

fn ecall(number: u64) void {
    asm volatile ("ecall"
        :
        : [number] "{a7}" (number),
    );
}
