const Spinlock = @import("locks/spinlock.zig");
const riscv = @import("riscv.zig");
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

var proc_glob_lock: Spinlock = Spinlock.init("proc_glob_lock");
var PROCS: [riscv.MAX_PROCS]Self = undefined;

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
pagetable: PageTable,

trapframe: *TrapFrame,
sys_call_context: SysCallContext,
name: *[]const u8,
