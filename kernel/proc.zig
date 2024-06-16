const std = @import("std");
const mem = @import("mem/mem.zig");
const riscv = @import("riscv.zig");
const lib = @import("lib.zig");

const KMem = @import("mem/kmem.zig");
const Spinlock = @import("locks/spinlock.zig");
const PageTable = @import("mem/pagetable.zig");

const Self = @This();

const ProcState = enum { UNUSED, USED, SLEEPING, RUNNABLE, RUNNING, ZOMBIE };

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

const SysCallContext = extern struct {
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

var proc_glob_lock: Spinlock = Spinlock.init("proc_glob_lock");

var pid_lock: Spinlock = Spinlock.init("pid_lock");
var init_proc: *Self = undefined;
var nextpid: u64 = 1;

lock: Spinlock,

// spin lock must be held
state: ProcState,
killed: bool,
exit_status: u64,
pid: u64,

// must have global lock
parent: *Self,

// private to proc lock not needed
kstackPtr: u64,
mem_size: u64,
pagetable: ?PageTable,

trapframe: ?*TrapFrame,
sys_call_context: SysCallContext,
name: [20]u8,

pub fn init() void {
    for (0..riscv.MAX_PROCS) |i| {
        const id = [_]u8{ @intCast((i / 10) + 48), @intCast((i % 10) + 48) };

        PROCS[i].lock = Spinlock.init("proc" ++ id);
        PROCS[i].state = .UNUSED;
        PROCS[i].kstackPtr = riscv.KSTACK(i);
    }
}

pub fn alloc() !*Self {
    var proc: *Self = undefined;
    var i: usize = 0;
    while (i < riscv.MAX_PROCS) : (i += 1) {
        var p = &PROCS[i];
        p.lock.acquire();
        if (p.state == .UNUSED) {
            proc = p;
            break;
        } else {
            p.lock.release();
        }
    }
    if (proc == undefined) {
        return error.ProcNotAvailable;
    }

    proc.pid = allocPid();
    proc.state = .USED;

    proc.initPageTable() catch |e| {
        try proc.free();
        proc.lock.release();
        return e;
    };

    proc.sys_call_context = std.mem.zeroes(SysCallContext);
    lib.printInt(proc.sys_call_context.ra);
    proc.sys_call_context.ra = @intFromPtr(&forkret());
    proc.sys_call_context.sp = proc.kstackPtr + riscv.PGSIZE;
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
    self.state = .UNUSED;
}

pub fn allocPid() u64 {
    pid_lock.acquire();
    const out = nextpid;
    nextpid += 1;
    pid_lock.release();
    return out;
}

pub fn userInit() !void {
    const proc = try alloc();
    init_proc = proc;

    // allocate code memory
    const page: riscv.Page = @ptrCast(try KMem.alloc());
    @memset(page, 0);
    try proc.pagetable.?.mapPages(
        0,
        @intFromPtr(page),
        riscv.PGSIZE,
        mem.PTE_R | mem.PTE_W | mem.PTE_X | mem.PTE_U,
    );
    @memcpy(page[0..init_code.len], &init_code);

    proc.mem_size = riscv.PGSIZE;
    proc.trapframe.?.epc = 0;
}

export fn forkret() void {}

extern fn trampoline() void;

fn initPageTable(self: *Self) !void {
    self.trapframe = @ptrCast(try KMem.alloc());
    self.pagetable = try PageTable.init();

    try self.pagetable.?.mapPages(
        riscv.TRAMPOLINE,
        @intFromPtr(&trampoline),
        riscv.PGSIZE,
        mem.PTE_R | mem.PTE_X,
    );

    try self.pagetable.?.mapPages(
        riscv.TRAPFRAME,
        @intFromPtr(self.trapframe),
        riscv.PGSIZE,
        mem.PTE_R | mem.PTE_W,
    );
}
