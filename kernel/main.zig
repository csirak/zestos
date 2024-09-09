const lib = @import("lib.zig");
const riscv = @import("riscv.zig");
const Device = @import("device.zig");
const Traps = @import("trap.zig");
const Timer = @import("timer.zig");

const Process = @import("procs/proc.zig");
const KMem = @import("mem/kmem.zig");

const Plic = @import("io/plic.zig");
const Console = @import("io/console.zig");

const BufferCache = @import("fs/buffercache.zig");
const Virtio = @import("fs/virtio.zig");
const FileTable = @import("fs/filetable.zig");
const INodeTable = @import("fs/inodetable.zig");

var started: bool = false;

pub export fn main() void {
    if (riscv.cpuid() == 0) {
        Device.init();
        Console.init();

        lib.println("get ready for the zest");
        lib.println("zest-os booting");

        KMem.init();
        KMem.coreInit();

        Process.init();

        Timer.init();
        Traps.coreInit();

        Plic.init();
        Plic.coreInit();

        BufferCache.init();
        INodeTable.init();
        FileTable.init();
        Virtio.init();

        Process.userInit() catch |e| {
            lib.printf("error: {}\n", .{e});
            lib.kpanic("error initializing init");
        };

        started = true;
        Console.coreLog("started!");

        @fence(.seq_cst);
    } else {
        while (!started) {}
        @fence(.seq_cst);

        KMem.coreInit();
        Traps.coreInit();
        Plic.coreInit();

        Console.coreLog("started!");
    }

    Process.scheduler();
}
