const lib = @import("lib.zig");
const riscv = @import("riscv.zig");
const Procedure = @import("proc.zig");
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
        Procedure.init();
        Traps.init();
        Traps.coreInit();
        Plic.init();
        Plic.coreInit();

        Procedure.userInit() catch |e| {
            lib.println("error initializing user process");
            lib.printErr(e);
        };

        started = true;
        riscv.fence_iorw();
    } else {
        while (!started) {}
        riscv.fence_iorw();
        Traps.coreInit();
        Plic.coreInit();
    }
}
