const lib = @import("lib.zig");
const riscv = @import("riscv.zig");
const Procedure = @import("procs/proc.zig");
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
        StdOut.println("zest core: 0 started!");
        riscv.fence_iorw();
    } else {
        while (!started) {}

        riscv.fence_iorw();
        KMem.coreInit();
        Traps.coreInit();
        Plic.coreInit();

        const id = riscv.cpuid();
        const idchar = [_]u8{@intCast(id + 48)};
        const out = "zest core: " ++ idchar ++ " started!";
        StdOut.println(out);
    }

    Procedure.scheduler();
}
