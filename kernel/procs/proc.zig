const std = @import("std");
const mem = @import("../mem/mem.zig");
const riscv = @import("../riscv.zig");
const lib = @import("../lib.zig");

const Cpu = @import("../cpu.zig");
const Trap = @import("../trap.zig");

const Spinlock = @import("../locks/spinlock.zig");

const KMem = @import("../mem/kmem.zig");
const PageTable = @import("../mem/pagetable.zig");

const Console = @import("../io/console.zig");

const fs = @import("../fs/fs.zig");
const Log = @import("../fs/log.zig");
const File = @import("../fs/file.zig");
const FileTable = @import("../fs/filetable.zig");
const INode = @import("../fs/inode.zig");
const INodeTable = @import("../fs/inodetable.zig");

const Self = @This();

const ProcState = enum { Unused, Used, Sleeping, Runnable, Running, Zombie };

extern fn trampoline() void;

extern fn switch_context(old_context: *SysCallContext, new_context: *SysCallContext) void;

pub const TrapFrame = extern struct {
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
pub const MAX_ARGS = 32;
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
        PROCS[i].kstackPtr = riscv.KSTACK(i) + riscv.KSTACK_SIZE;

        for (0..fs.MAX_OPEN_FILES) |j| {
            PROCS[i].open_files[j] = null;
        }
    }
}

/// Returns with lock held
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
    errdefer proc.lock.release();
    if (proc == undefined) {
        return error.ProcNotAvailable;
    }

    proc.pid = allocPid();
    proc.state = .Used;
    proc.trapframe = @ptrCast(try KMem.alloc());
    errdefer proc.free() catch unreachable;
    try proc.initPageTable();

    proc.call_context = std.mem.zeroes(SysCallContext);
    proc.call_context.ra = @intFromPtr(&Trap.forkReturn);
    proc.call_context.sp = proc.kstackPtr;

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
    defer self.lock.release();
    return self.killed;
}

pub fn getPid(self: *Self) u64 {
    self.lock.acquire();
    defer self.lock.release();
    return self.pid;
}

pub fn setKilled(self: *Self) void {
    self.lock.acquire();
    defer self.lock.release();
    self.killed = true;
}

pub fn fileDescriptorAlloc(self: *Self, file: *File) !u64 {
    for (0..fs.MAX_OPEN_FILES) |i| {
        if (self.open_files[i] == null) {
            self.open_files[i] = file;
            return i;
        }
    }
    return error.NoFileDescriptorAvailable;
}

pub fn fileDescriptorFree(self: *Self, fd: u64) !void {
    if (fd < fs.MAX_OPEN_FILES and self.open_files[fd] != null) {
        self.open_files[fd] = null;
        return;
    }
    return error.InvalidFD;
}

pub fn yield(self: *Self) void {
    self.lock.acquire();
    defer self.lock.release();
    self.state = .Runnable;
    // closes lock and then returns with lock held.
    self.switchToScheduler();
}

pub fn fork(self: *Self) !u64 {
    const newProc = try alloc();
    self.pagetable.?.copy(&newProc.pagetable.?, self.mem_size) catch |e| {
        newProc.free() catch unreachable;
        newProc.lock.release();
        return e;
    };

    newProc.mem_size = self.mem_size;
    newProc.trapframe.?.* = self.trapframe.?.*;
    newProc.trapframe.?.a0 = 0;

    for (0..fs.MAX_OPEN_FILES) |i| if (self.open_files[i]) |file| {
        newProc.open_files[i] = FileTable.duplicate(file);
    };

    newProc.cwd = INodeTable.duplicate(self.cwd);

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

pub fn wait(self: *Self, _: u64) !u64 {
    proc_glob_lock.acquire();
    defer proc_glob_lock.release();
    var has_children = false;

    while (true) {
        for (&PROCS) |*proc| {
            proc.lock.acquire();
            defer proc.lock.release();
            if (proc.parent != self) {
                continue;
            }
            has_children = true;
            if (proc.state == .Zombie) {
                const pid = proc.pid;
                try proc.free();
                return pid;
            }
        }
        // check if killed
        if (!has_children or self.isKilled()) {
            return error.NoChildren;
        }

        self.sleep(self, &proc_glob_lock);
    }
}

pub fn resizeMem(self: *Self, change: i64) !void {
    const old_size = self.mem_size;
    const new_size: u64 = @intCast(@as(i64, @intCast(old_size)) + change);

    // TODO: check if change is valid
    if (change > 0) {
        self.mem_size = try self.pagetable.?.userAlloc(
            old_size,
            new_size,
            mem.PTE_W,
        );
    } else {
        self.mem_size = try self.pagetable.?.userDeAlloc(
            self.mem_size,
            new_size,
        );
    }
}

/// atomically lock process and release external lockprocess will be scheduled to run again when awakened
/// reacquire lock
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

    for (&self.open_files) |*file| if (file.*) |f| {
        FileTable.free(f);
        file.* = null;
    };

    Log.beginTx();
    INodeTable.removeRef(self.cwd);
    Log.endTx();
    self.cwd = undefined;

    proc_glob_lock.acquire();
    self.reparent();
    wakeup(self.parent);

    // sched requires lock to be held
    self.lock.acquire();
    self.exit_status = status;
    self.state = .Zombie;

    // cant defer because sched actually exits to diff proc
    proc_glob_lock.release();

    self.switchToScheduler();
    lib.kpanic("ZOMBIE WALKING");
}

pub fn reparent(self: *Self) void {
    for (&PROCS) |*proc| {
        if (proc.parent == self) {
            proc.parent = init_proc;
            wakeup(init_proc);
        }
    }
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

    if (self.trapframe == null) {
        lib.kpanic("trapframe is null");
    }

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
    defer proc.lock.release();
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
    proc.trapframe.?.sp = riscv.PGSIZE;
    proc.state = .Runnable;

    proc.cwd = try INodeTable.getNamedInode("/");
    lib.strCopy(proc.name[0..], "init", 4);
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

pub inline fn currentOrPanic() *Self {
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
