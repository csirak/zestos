const std = @import("std");
const mem = @import("../mem/mem.zig");
const riscv = @import("../riscv.zig");
const lib = @import("../lib.zig");

const Cpu = @import("../cpu.zig");
const Trap = @import("../trap.zig");

const Spinlock = @import("../locks/spinlock.zig");

const KMem = @import("../mem/kmem.zig");
const PageTable = @import("../mem/pagetable.zig");

const StdOut = @import("../io/stdout.zig");

const fs = @import("../fs/fs.zig");
const File = @import("../fs/file.zig");
const INodeTable = @import("../fs/inodetable.zig");
const INode = @import("../fs/inode.zig");

const Self = @This();

const ProcState = enum { Unused, Used, Sleeping, Runnable, Running, Zombie };

extern fn trampoline() void;

extern fn switch_context(old_context: *SysCallContext, new_context: *SysCallContext) void;

const TrapFrame = extern struct {
    kernel_satp: u64, // kernel page table
    kernel_sp: u64, // top of process's kernel stack
    kernel_trap: u64, // usertrap()
    epc: u64, // saved user program counter
    kernel_hartid: u64, // saved kernel tp

    ra: u64,
    sp: u64,
    gp: u64,
    tp: u64,
    t0: u64,
    t1: u64,
    t2: u64,
    s0: u64,
    s1: u64,
    a0: u64,
    a1: u64,
    a2: u64,
    a3: u64,
    a4: u64,
    a5: u64,
    a6: u64,
    a7: u64,
    s2: u64,
    s3: u64,
    s4: u64,
    s5: u64,
    s6: u64,
    s7: u64,
    s8: u64,
    s9: u64,
    s10: u64,
    s11: u64,
    t3: u64,
    t4: u64,
    t5: u64,
    t6: u64,
};

pub const SysCallContext = extern struct {
    ra: u64,
    sp: u64,
    // calle-saved
    s0: u64,
    s1: u64,
    s2: u64,
    s3: u64,
    s4: u64,
    s5: u64,
    s6: u64,
    s7: u64,
    s8: u64,
    s9: u64,
    s10: u64,
    s11: u64,
};

pub const NAME_SIZE = 20;
const init_code = [_]u8{
    0x17, 0x05, 0x00, 0x00, 0x13, 0x05, 0x45, 0x02,
    0x97, 0x05, 0x00, 0x00, 0x93, 0x85, 0x35, 0x02,
    0x93, 0x08, 0x70, 0x00, 0x73, 0x00, 0x00, 0x00,
    0x93, 0x08, 0x20, 0x00, 0x73, 0x00, 0x00, 0x00,
    0xef, 0xf0, 0x9f, 0xff, 0x2f, 0x69, 0x6e, 0x69,
    0x74, 0x00, 0x00, 0x24, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
};

var PROCS: [riscv.MAX_PROCS]Self = undefined;

var proc_glob_lock: Spinlock = undefined;

var pid_lock: Spinlock = undefined;

var init_proc: *Self = undefined;
var nextpid: u64 = 1;

lock: Spinlock,

// spin lock must be held
state: ProcState,
killed: bool,
exit_status: i64,
pid: u64,
channel: u64,

// must have global lock
parent: *Self,

// private to proc lock not needed
kstackPtr: u64,
mem_size: u64,
pagetable: ?PageTable,
cwd: *INode,
open_files: [fs.MAX_OPEN_FILES]?*File,
trapframe: ?*TrapFrame,
call_context: SysCallContext,
name: [NAME_SIZE]u8,

pub fn init() void {
    proc_glob_lock = Spinlock.init("proc_glob_lock");
    pid_lock = Spinlock.init("pid_lock");

    for (0..riscv.MAX_PROCS) |i| {
        PROCS[i].lock = Spinlock.init("proc");
        PROCS[i].state = .Unused;
        PROCS[i].kstackPtr = riscv.KSTACK(i);
    }
}

pub fn alloc() !*Self {
    var proc: *Self = undefined;
    var i: usize = 0;
    while (i < riscv.MAX_PROCS) : (i += 1) {
        var p = &PROCS[i];
        p.lock.acquire();
        if (p.state == .Unused) {
            proc = p;
            break;
        }
        p.lock.release();
    }
    if (proc == undefined) {
        return error.ProcNotAvailable;
    }

    proc.pid = allocPid();
    proc.state = .Used;
    proc.trapframe = @ptrCast(try KMem.alloc());

    proc.initPageTable() catch |e| {
        proc.free() catch unreachable;
        proc.lock.release();
        return e;
    };

    proc.call_context = std.mem.zeroes(SysCallContext);
    proc.call_context.ra = @intFromPtr(&Trap.forkReturn);
    proc.call_context.sp = proc.kstackPtr + riscv.PGSIZE;
    return proc;
}

pub fn free(self: *Self) !void {
    if (self.trapframe) |trapframe| KMem.free(@intFromPtr(trapframe));
    self.trapframe = null;

    if (self.pagetable) |*pagetable| try pagetable.*.userFree(self.mem_size);
    self.pagetable = null;

    self.mem_size = 0;
    self.pid = 0;
    self.name[0] = 0;
    self.killed = false;
    self.exit_status = 0;
    self.state = .Unused;
}

pub fn isKilled(self: *Self) bool {
    self.lock.acquire();
    const killed = self.killed;
    self.lock.release();
    return killed;
}

pub fn getPid(self: *Self) u64 {
    self.lock.acquire();
    const pid = self.pid;
    self.lock.release();
    return pid;
}

pub fn setKilled(self: *Self) void {
    self.lock.acquire();
    self.killed = true;
    self.lock.release();
}

pub fn yield(self: *Self) void {
    self.lock.acquire();
    self.state = .Runnable;
    // closes lock and then returns with lock held.
    self.switchToScheduler();
    self.lock.release();
}

pub fn fork(self: *Self) !void {
    const newProc = try alloc();
    self.pagetable.?.copy(newProc.pagetable.?, self.mem_size) catch |e| {
        newProc.free() catch unreachable;
        newProc.lock.release();
        return e;
    };

    newProc.mem_size = self.mem_size;
    newProc.trapframe.?.* = self.trapframe.?.*;
    newProc.trapframe.?.a0 = 0;

    newProc.cwd = try INodeTable.duplicate(self.cwd);

    lib.strCopy(newProc.name[0..], self.name[0..], 20);
    const pid = newProc.pid;

    newProc.lock.release();

    proc_glob_lock.acquire();
    newProc.parent = self;
    proc_glob_lock.release();

    newProc.lock.acquire();
    newProc.state = .Runnable;
    newProc.lock.release();

    return pid;
}

// atomically lock process and release external lock
// process will be scheduled to run again when awakened
// reacquire lock
pub fn sleep(self: *Self, channel: *anyopaque, passed_lock: *Spinlock) void {
    self.lock.acquire();
    passed_lock.release();

    self.channel = @intFromPtr(channel);
    self.state = .Sleeping;

    self.switchToScheduler();

    self.channel = 0;

    self.lock.release();
    passed_lock.acquire();
}

pub fn exit(self: *Self, status: i64) void {
    if (self == init_proc) {
        lib.kpanic("init process exit");
    }

    proc_glob_lock.acquire();
    wakeup(self.parent);

    self.lock.acquire();
    self.exit_status = status;
    self.state = .Zombie;
    proc_glob_lock.release();
}

pub fn initPageTable(self: *Self) !void {
    self.pagetable = try self.getTrapFrameMappedPageTable();
}

pub fn getTrapFrameMappedPageTable(self: *Self) !PageTable {
    var new_pagetable = try PageTable.init();

    try new_pagetable.mapPages(
        riscv.TRAMPOLINE,
        @intFromPtr(&trampoline),
        riscv.PGSIZE,
        mem.PTE_R | mem.PTE_X,
    );

    try new_pagetable.mapPages(
        riscv.TRAPFRAME,
        @intFromPtr(self.trapframe.?),
        riscv.PGSIZE,
        mem.PTE_R | mem.PTE_W,
    );
    return new_pagetable;
}

pub fn userInit() !void {
    const proc = try alloc();
    init_proc = proc;

    // allocate code memory
    const page: *riscv.Page = @ptrCast(try KMem.allocZeroed());
    try proc.pagetable.?.mapPages(
        0,
        @intFromPtr(page),
        riscv.PGSIZE,
        mem.PTE_R | mem.PTE_W | mem.PTE_X | mem.PTE_U,
    );
    @memcpy(page[0..init_code.len], &init_code);

    proc.mem_size = riscv.PGSIZE;
    proc.trapframe.?.epc = 0;
    proc.state = .Runnable;

    lib.strCopy(proc.name[0..], "init", 4);
    proc.cwd = try INodeTable.namedInode("/");
    proc.lock.release();
}

pub fn scheduler() void {
    var cpu = Cpu.current();
    cpu.proc = null;

    while (true) {
        riscv.intr_on();
        for (&PROCS) |*proc| {
            proc.lock.acquire();
            if (proc.state == .Runnable) {
                proc.state = .Running;
                cpu.proc = proc;
                switch_context(&cpu.call_context, &proc.call_context);
                cpu.proc = null;
            }
            proc.lock.release();
        }
    }
}

pub fn copyToUser(dest: u64, src: *[]u8, size: u64) !void {
    try currentOrPanic().pagetable.?.copyInto(dest, src, size);
}

/// not a struct function because for now it's used by the scheduler because
/// the current process doesn't need any information on the process to wake up
pub fn wakeup(channel: *anyopaque) void {
    const cur = current();
    for (&PROCS) |*proc| {
        if (proc != cur and proc.channel == @intFromPtr(channel)) {
            proc.lock.acquire();
            proc.state = .Runnable;
            proc.lock.release();
        }
    }
}

pub fn current() ?*Self {
    const cpu = Cpu.current();
    cpu.pushInterrupt();
    defer cpu.popInterrupt();
    return cpu.proc;
}

pub fn currentOrPanic() *Self {
    const proc = current() orelse lib.kpanic("No current process");
    return proc;
}

pub fn allocPid() u64 {
    pid_lock.acquire();
    defer pid_lock.release();
    defer nextpid += 1;
    return nextpid;
}

// proc lock is released in scheduler
fn switchToScheduler(self: *Self) void {
    if (!self.lock.haveLock()) {
        lib.kpanic("proc lock not held on scheduler switch");
    }

    var cpu = Cpu.current();

    if (cpu.disabled_depth != 1) {
        lib.kpanic("scheduler switch while interrupt stack not aligned");
    }
    if (self.state == .Running) {
        lib.kpanic("scheduler switch while already running");
    }
    if (riscv.intr_get()) {
        lib.kpanic("scheduler switch while interrupts enabled");
    }

    const interrupts_enabled = cpu.interrupts_enabled;
    // swap and restore when done
    switch_context(&self.call_context, &cpu.call_context);
    cpu.interrupts_enabled = interrupts_enabled;
}
