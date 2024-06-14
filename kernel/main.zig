const lib = @import("lib.zig");
const riscv = @import("riscv.zig");
const KMem = @import("mem/kmem.zig");
const StdOut = @import("io/stdout.zig");

extern var timer_scratch: *u64;
extern var stack0: *u64;

var started: bool = false;

pub export fn main() void {
    if (riscv.cpuid() == 0) {
        lib.println("get ready for the zest");
        lib.println("zest-os booting");

        KMem.init();

        started = true;
        riscv.fence_iorw();
    } else {
        while (!started) {}
        riscv.fence_iorw();
    }
}
