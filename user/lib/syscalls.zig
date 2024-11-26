pub const SYSCALL_FORK = 1;
pub const SYSCALL_EXIT = 2;
pub const SYSCALL_WAIT = 3;
pub const SYSCALL_PIPE = 4;
pub const SYSCALL_READ = 5;
pub const SYSCALL_EXEC = 7;
pub const SYSCALL_STAT = 8;
pub const SYSCALL_CHDIR = 9;
pub const SYSCALL_DUP = 10;
pub const SYSCALL_GETPID = 11;
pub const SYSCALL_SBRK = 12;
pub const SYSCALL_SLEEP = 13;
pub const SYSCALL_UPTIME = 14;
pub const SYSCALL_OPEN = 15;
pub const SYSCALL_WRITE = 16;
pub const SYSCALL_MAKE_NODE = 17;
pub const SYSCALL_UNLINK = 18;
pub const SYSCALL_LINK = 19;
pub const SYSCALL_MKDIR = 20;
pub const SYSCALL_CLOSE = 21;

inline fn syscall(comptime x: comptime_int) u64 {
    asm volatile ("li a7, %[x]"
        :
        : [x] "i" (x),
    );
    asm volatile ("ecall");
    var y: u64 = 0;
    asm ("mv %[y], a0"
        : [y] "=r" (y),
    );
    return y;
}

pub fn fork() u64 {}
pub fn exit(status: u64) noreturn {
    _ = status;
    _ = syscall(SYSCALL_EXIT);
    while (true) {}
}
pub fn wait() u64 {}
pub fn pipe() u64 {}
pub fn read() u64 {}
pub fn exec() u64 {}
pub fn stat() u64 {}
pub fn chdir() u64 {}
pub fn dup() u64 {}
pub fn getpid() u64 {}
pub fn sbrk() u64 {}
pub fn sleep() u64 {}
pub fn uptime() u64 {}
pub fn open() u64 {}

pub fn write(file_descriptor: u64, buffer: [*]u8, len: usize) u64 {
    _ = file_descriptor;
    _ = buffer;
    _ = len;
    return syscall(SYSCALL_WRITE);
}

pub fn write_slice(file_descriptor: u64, buffer: []u8) u64 {
    return write(file_descriptor, buffer.ptr, buffer.len);
}

pub fn make_node() u64 {}
pub fn unlink() u64 {}
pub fn link() u64 {}
pub fn mkdir() u64 {}
pub fn close() u64 {}
