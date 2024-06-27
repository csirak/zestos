const lib = @import("../lib.zig");
const exec = @import("exec.zig").exec;
const Process = @import("proc.zig");

pub const SYSCALL_EXEC = 7;
pub const SYSCALL_GET_PID = 9;
pub const SYSCALL_PUT_CHAR = 64;

pub fn doSyscall() void {
    const proc = Process.currentOrPanic();

    const syscall_num = proc.trapframe.?.a7;

    switch (syscall_num) {
        SYSCALL_EXEC => {
            exec("/init") catch |e| {
                lib.printErr(e);
                lib.kpanic("Failed to exec /init");
            };
        },
        SYSCALL_GET_PID => {
            proc.trapframe.?.a0 = proc.pid;
        },
        SYSCALL_PUT_CHAR => {
            const c = proc.trapframe.?.a0;
            lib.println("c: ");
            lib.putChar(@intCast(c));
        },
        else => {
            lib.kpanic("Unknown syscall");
        },
    }
}
