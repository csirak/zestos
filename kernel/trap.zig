const riscv = @import("riscv.zig");
const lib = @import("lib.zig");
const fs = @import("fs/fs.zig");

const KMem = @import("mem/kmem.zig");
const PageTable = @import("mem/pagetable.zig");
const mem = @import("mem/mem.zig");

const Spinlock = @import("locks/spinlock.zig");
const Process = @import("procs/proc.zig");
const Syscalls = @import("procs/syscall.zig");
const Virtio = @import("fs/virtio.zig");

const Console = @import("io/console.zig");
const UART = @import("io/uart.zig");

const Interrupt = enum { Timer, Software, External, Syscall, Breakpoint, Unknown };

var ticks: u64 = 0;
var tickslock: Spinlock = undefined;
var first_ret = true;

extern fn kernelvec() void;
extern fn uservec() void;
extern fn userret() void;
extern fn trampoline() void;
pub fn init() void {
    tickslock = Spinlock.init("time");
}

pub fn coreInit() void {
    riscv.w_stvec(@intFromPtr(&kernelvec));
}

pub fn userTrap() void {
    if (riscv.r_sstatus() & riscv.SSTATUS_SPP != 0) {
        Console.kpanic("user trap not from user mode");
    }

    riscv.w_stvec(@intFromPtr(&kernelvec));

    const proc = Process.currentOrPanic();

    proc.trapframe.?.epc = riscv.r_sepc();
    const scause = riscv.r_scause();
    const reason = getSupervisorInterrupt(scause);
    switch (reason) {
        .Syscall => {
            if (proc.isKilled()) {
                proc.exit(-1);
            }

            // 32 bit instruction size
            proc.trapframe.?.epc += 4;
            riscv.intr_on();
            Syscalls.doSyscall();
        },

        .Timer => {
            proc.yield();
        },

        .External => {},

        else => {
            proc.setKilled();
            @panic("Unknown interrupt");
        },
    }

    if (proc.isKilled()) {
        Console.println("killed");
        proc.exit(-1);
    }

    userTrapReturn();
}

pub fn userTrapReturn() noreturn {
    var proc = Process.currentOrPanic();

    // deactivate until in user mode
    riscv.intr_off();

    const user_vec_trampoline = riscv.TRAMPOLINE + @intFromPtr(&uservec) - @intFromPtr(&trampoline);
    riscv.w_stvec(user_vec_trampoline);

    proc.trapframe.?.kernel_satp = riscv.r_satp();
    proc.trapframe.?.kernel_sp = proc.kstackPtr;
    proc.trapframe.?.kernel_trap = @intFromPtr(&userTrap);
    proc.trapframe.?.kernel_hartid = riscv.r_tp();

    // clear current interrupt turn on user interrupts and set previous mode
    const sstatus = riscv.r_sstatus();
    const user_sstatus = (sstatus & ~riscv.SSTATUS_SPP) | riscv.SSTATUS_SPIE;
    riscv.w_sstatus(user_sstatus);

    riscv.w_sepc(proc.trapframe.?.epc);
    const satp = proc.pagetable.?.getAsSatp();

    const user_ret_trampoline = riscv.TRAMPOLINE + @intFromPtr(&userret) - @intFromPtr(&trampoline);
    const user_ret: *const fn (u64) noreturn = @ptrFromInt(user_ret_trampoline);
    user_ret(satp);
}

pub fn forkReturn() void {
    const proc = Process.currentOrPanic();
    proc.lock.release();

    if (first_ret) {
        first_ret = false;
        fs.init();
    }

    userTrapReturn();
}

export fn kerneltrap() void {
    const sepc = riscv.r_sepc();
    const scause = riscv.r_scause();

    const sstatus = riscv.r_sstatus();
    const current = Process.current();

    if (sstatus & riscv.SSTATUS_SPP == 0) {
        Console.kpanic("Not from Supervisor Mode");
    }

    if (riscv.intr_get()) {
        Console.kpanic("Interrupts on");
    }

    const reason = getSupervisorInterrupt(scause);

    if (reason == .Unknown) {
        lib.println("");
        Console.printf("stack: {x}\n", .{riscv.r_sp()});
        Console.printf("stval: {x}\n", .{riscv.r_stval()});
        Console.printf("sepc: {x}\n", .{riscv.r_sepc()});
        Console.printf("ra: {x}\n", .{riscv.r_ra()});
        Console.printf("a0: {x}\n", .{riscv.r_a0()});
        Console.printf("cause: {x}\n", .{scause});
        Console.kpanic("Unknown interrupt");
    }

    if (current) |proc| {
        if (proc.state == .Running and reason == .Timer) {
            proc.yield();
        }
    }

    riscv.w_sepc(sepc);
    riscv.w_sstatus(sstatus);
}

// must be called in kernel mode with stvec set to kernelvec
fn getSupervisorInterrupt(cause: u64) Interrupt {
    if (cause == riscv.SCAUSE_TRAP_SYSCALL) {
        return .Syscall;
    }

    if (cause & riscv.SCAUSE_TYPE_MASK == 0) {
        return .Unknown;
    }

    // Interrupt
    // for now only software interrupt is a timer interrupt

    const flag = cause & riscv.SCAUSE_FLAG_MASK;
    switch (flag) {
        riscv.SCAUSE_INT_SOFTWARE => {
            clockInterrupt();
            const clear_pending_mask: u8 = 2;
            riscv.w_sip(riscv.r_sip() & ~clear_pending_mask);

            return .Timer;
        },
        riscv.SCAUSE_INT_PLIC => {
            plicInterrupt();
            return .External;
        },
        else => {
            Console.printf("unknown fault: {}\n", .{flag});
            return .Unknown;
        },
    }
}

fn plicInterrupt() void {
    const interrupt_id = riscv.plic_claim();

    switch (interrupt_id) {
        0 => {
            return;
        },
        riscv.UART0_IRQ => {
            UART.handleInterrupt();
        },
        riscv.VIRTIO0_IRQ => {
            Virtio.diskInterrupt();
        },
        else => {
            Console.printf("unknown plic interrupt: {x}\n", .{interrupt_id});
        },
    }

    riscv.plic_complete(interrupt_id);
}

inline fn clockInterrupt() void {
    if (riscv.cpuid() != 0) {
        return;
    }

    tickslock.acquire();
    defer tickslock.release();
    ticks += 1;
    Process.wakeup(&ticks);
}
