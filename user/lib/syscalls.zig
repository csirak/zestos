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
pub const SYSCALL_INTROSPECT = 69;

inline fn errorToNull(r: u64) ?u64 {
    return if (@as(i64, @intCast(r)) < 0) null else r;
}
inline fn syscall(comptime x: comptime_int) u64 {
    var y: u64 = 0;
    asm volatile ("li a7, %[x]"
        :
        : [x] "i" (x),
    );
    asm volatile ("ecall");
    asm ("mv %[y], a0"
        : [y] "=r" (y),
    );
    return y;
}

inline fn syscall2(a0: u64, a1: u64, comptime x: comptime_int) u64 {
    var y: u64 = 0;

    asm volatile ("mv a0, %[x]"
        :
        : [x] "r" (a0),
    );
    asm volatile ("mv a1, %[x]"
        :
        : [x] "r" (a1),
    );

    asm volatile ("li a7, %[x]"
        :
        : [x] "i" (x),
    );
    asm volatile ("ecall");
    asm ("mv %[y], a0"
        : [y] "=r" (y),
    );
    return y;
}

inline fn syscall3(a0: u64, a1: u64, a2: u64, comptime x: comptime_int) u64 {
    var y: u64 = 0;

    asm volatile ("mv a0, %[x]"
        :
        : [x] "r" (a0),
    );
    asm volatile ("mv a1, %[x]"
        :
        : [x] "r" (a1),
    );
    asm volatile ("mv a2, %[x]"
        :
        : [x] "r" (a2),
    );

    asm volatile ("li a7, %[x]"
        :
        : [x] "i" (x),
    );
    asm volatile ("ecall");
    asm ("mv %[y], a0"
        : [y] "=r" (y),
    );
    return y;
}

pub fn fork() u64 {}
pub fn exit(status: u64) noreturn {
    _ = status;
    _ = syscall(SYSCALL_EXIT);
    // exit never returns but compiler doesnt know
    while (true) {}
}
pub fn wait() u64 {}
pub fn pipe() u64 {}

pub fn read(file_descriptor: u64, buffer: [*]u8, len: usize) ?u64 {
    return errorToNull(syscall3(file_descriptor, @intFromPtr(buffer), @intCast(len), SYSCALL_READ));
}

pub inline fn read_slice(file_descriptor: u64, buffer: []u8) ?u64 {
    return read(file_descriptor, buffer.ptr, buffer.len);
}

pub fn exec() u64 {}
pub fn stat() u64 {}
pub fn chdir() u64 {}
pub fn dup() u64 {}
pub fn getpid() u64 {}
pub fn sbrk() u64 {}
pub fn sleep() u64 {}
pub fn uptime() u64 {}

pub fn open(path: [*:0]const u8, flags: u64) ?u64 {
    return errorToNull(syscall2(@intFromPtr(path), flags, SYSCALL_OPEN));
}

pub fn write(file_descriptor: u64, buffer: [*]u8, len: usize) ?u64 {
    return errorToNull(syscall3(file_descriptor, @intFromPtr(buffer), @intCast(len), SYSCALL_WRITE));
}

pub inline fn write_slice(file_descriptor: u64, buffer: []u8) ?u64 {
    return write(file_descriptor, buffer.ptr, buffer.len);
}

pub fn make_node() u64 {}
pub fn unlink() u64 {}
pub fn link() u64 {}
pub fn mkdir() u64 {}
pub fn close(fd: u64) ?u64 {
    _ = fd;
    return errorToNull(syscall(SYSCALL_CLOSE));
}

pub fn introspect() void {
    _ = syscall(SYSCALL_INTROSPECT);
}
