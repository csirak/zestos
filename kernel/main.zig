const lib = @import("lib.zig");
const riscv = @import("riscv.zig");
const KMem = @import("mem/kmem.zig");

extern var timer_scratch: *u64;

const Global = struct {
    var started: bool = false;
};

pub export fn main() void {
    if (riscv.cpuid() == 0) {
        lib.println("get ready for the zest");
        lib.println("zest-os booting");

        KMem.init();

        Global.started = true;
        riscv.fence_iorw();
    } else {
        while (!Global.started) {}
        riscv.fence_iorw();
    }
}
