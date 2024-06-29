const lib = @import("../lib.zig");
const exec = @import("exec.zig").exec;
const Process = @import("proc.zig");

const builtin = @import("builtin");

pub const SYSCALL_EXIT = 2;
pub const SYSCALL_EXEC = 7;
pub const SYSCALL_GET_PID = 9;
pub const SYSCALL_PUT_CHAR = 64;

const MAX_PATH = 128;

var path_buff: [MAX_PATH]u8 = undefined;

pub fn doSyscall() void {
    const proc = Process.currentOrPanic();

    const syscall_num = proc.trapframe.?.a7;

    lib.print("syscall_num: ");
    lib.printIntDec(syscall_num);
    lib.println("");
    switch (syscall_num) {
        SYSCALL_EXIT => {
            const status = proc.trapframe.?.a0;
            proc.exit(@intCast(status));
        },
        SYSCALL_EXEC => {
            const path_user_address = proc.trapframe.?.a0;
            proc.pagetable.?.copyFrom(path_user_address, @ptrCast(&path_buff), MAX_PATH) catch |e| {
                lib.printErr(e);
                lib.kpanic("Failed to copy path from user to kernel");
            };

            exec(@ptrCast(&path_buff)) catch |e| {
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
            lib.printAndInt("\naddress: ", proc.trapframe.?.epc);
            lib.kpanic("Unknown syscall");
        },
    }
}
