const lib = @import("lib.zig");
const riscv = @import("riscv.zig");
const Process = @import("procs/proc.zig");
const Traps = @import("trap.zig");
const KMem = @import("mem/kmem.zig");
const Plic = @import("io/plic.zig");
const StdOut = @import("io/stdout.zig");

var started: bool = false;

pub export fn main() void {
    if (riscv.cpuid() == 0) {
        lib.println("get ready for the zest");
        lib.println("zest-os booting");

        KMem.init();
        KMem.coreInit();

        Process.init();

        Traps.init();
        Traps.coreInit();

        Plic.init();
        Plic.coreInit();

        Process.userInit() catch |e| {
            lib.println("error initializing user process");
            lib.printErr(e);
        };

        started = true;
        StdOut.coreLog("started!");

        @fence(.seq_cst);
    } else {
        while (!started) {}
        @fence(.seq_cst);

        KMem.coreInit();
        Traps.coreInit();
        Plic.coreInit();

        StdOut.coreLog("started!");
    }

    Process.scheduler();
}
