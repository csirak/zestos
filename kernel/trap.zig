const riscv = @import("riscv.zig");
const lib = @import("lib.zig");

const Spinlock = @import("locks/spinlock.zig");
const StdOut = @import("io/stdout.zig");
const Process = @import("procs/proc.zig");
const Syscalls = @import("procs/syscall.zig");
const Virtio = @import("fs/virtio.zig");

const Interrupt = enum { Timer, Software, External, Syscall, Unknown };

var ticks: u64 = 0;
var tickslock: Spinlock = undefined;

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
        lib.kpanic("user trap not from user mode");
    }

    riscv.w_stvec(@intFromPtr(&kernelvec));

    const proc = Process.currentOrPanic();

    proc.trapframe.?.epc = riscv.r_sepc();

    const reason = getSupervisorInterrupt();

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
            lib.println("timer");
            proc.yield();
        },

        .External => {
            lib.println("external");
        },

        else => {
            lib.kpanic("Unknown interrupt");
            proc.setKilled();
        },
    }

    if (proc.isKilled()) {
        proc.exit(-1);
    }

    userTrapReturn();
}

pub fn userTrapReturn() void {
    var proc = Process.currentOrPanic();
    // deactivate until in user mode
    riscv.intr_off();

    const user_vec_trampoline = riscv.TRAMPOLINE + @intFromPtr(&uservec) - @intFromPtr(&trampoline);
    riscv.w_stvec(user_vec_trampoline);

    proc.trapframe.?.kernel_satp = riscv.r_satp();
    proc.trapframe.?.kernel_sp = proc.kstackPtr + riscv.PGSIZE;
    proc.trapframe.?.kernel_trap = @intFromPtr(&userTrap);
    proc.trapframe.?.kernel_hartid = riscv.r_tp();

    // clear current interrupt turn on user interrupts and set previous mode
    const sstatus = riscv.r_sstatus();
    const user_sstatus = (sstatus & ~riscv.SSTATUS_SPP) | riscv.SSTATUS_SPIE;
    riscv.w_sstatus(user_sstatus);

    riscv.w_sepc(proc.trapframe.?.epc);
    const satp = proc.pagetable.?.getAsSatp();

    const user_ret_trampoline = riscv.TRAMPOLINE + @intFromPtr(&userret) - @intFromPtr(&trampoline);

    const user_ret: *const fn (u64) void = @ptrFromInt(user_ret_trampoline);
    user_ret(satp);
}

pub fn forkReturn() void {
    // make sure to boot fs when running
    const proc = Process.currentOrPanic();
    proc.lock.release();
    userTrapReturn();
}

export fn kerneltrap() void {
    const sepc = riscv.r_sepc();
    // const scause = riscv.r_scause();
    const sstatus = riscv.r_sstatus();
    const current = Process.current();

    if (sstatus & riscv.SSTATUS_SPP == 0) {
        lib.kpanic("Not from Supervisor Mode");
    }

    if (riscv.intr_get()) {
        lib.kpanic("Interrupts on");
    }

    const cause = getSupervisorInterrupt();

    if (cause == .Unknown) {
        lib.kpanic("Unknown interrupt");
    }

    if (current) |proc| {
        if (proc.state == .Running and cause == .Timer) {
            proc.yield();
        }
    }

    riscv.w_sepc(sepc);
    riscv.w_sstatus(sstatus);
}

// must be called in kernel mode with stvec set to kernelvec
fn getSupervisorInterrupt() Interrupt {
    const cause = riscv.r_scause();

    if (cause == riscv.SCAUSE_TRAP_SYSCALL) {
        return .Syscall;
    }

    if (cause & riscv.SCAUSE_TYPE_MASK == 0) {
        lib.println("unknown trap");
        lib.printInt(cause);
        return .Unknown;
    }

    // Interrupt
    // for now only software interrupt is a timer interrupt

    const flag = cause & riscv.SCAUSE_FLAG_MASK;
    switch (flag) {
        riscv.SCAUSE_INT_SOFTWARE => {
            if (riscv.cpuid() == 0) {
                tickslock.acquire();
                ticks += 1;
                Process.wakeup(&ticks);
                tickslock.release();
            }
            return .Timer;
        },
        riscv.SCAUSE_INT_PLIC => {
            plicInterrupt();
            return .External;
        },
        else => {
            lib.print("unknown fault: ");
            lib.printInt(flag);
            return .Unknown;
        },
    }
}

fn plicInterrupt() void {
    const interrupt_id = riscv.plic_claim();

    switch (interrupt_id) {
        riscv.VIRTIO0_IRQ => {
            Virtio.diskInterrupt();
        },
        else => {
            lib.println("plic interrupt");
            lib.printInt(interrupt_id);
            lib.kpanic("Unknown PLIC interrupt");
        },
    }

    if (interrupt_id != 0) {
        riscv.plic_complete(interrupt_id);
    }
}
