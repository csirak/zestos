const syscall = @import("../kernel/procs/syscall.zig");

pub fn putChar(c: u8) void {
    asm volatile ("syscall"
        :
        : [number] "{a7}" (syscall.SYSCALL_PUT_CHAR),
          [arg1] "{a0}" (c),
        : "memory"
    );
}

pub fn getPid() u64 {
    var pid: u64 = undefined;
    asm volatile ("syscall"
        : [ret] "=r" (pid),
        : [number] "{a7}" (syscall.SYSCALL_GET_PID),
        : "memory"
    );
    return pid;
}
