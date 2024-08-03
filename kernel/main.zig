const lib = @import("lib.zig");
const riscv = @import("riscv.zig");
const Device = @import("device.zig");
const Traps = @import("trap.zig");

const Process = @import("procs/proc.zig");
const KMem = @import("mem/kmem.zig");

const Plic = @import("io/plic.zig");
const StdOut = @import("io/stdout.zig");

const BufferCache = @import("fs/buffercache.zig");
const Virtio = @import("fs/virtio.zig");
const FileTable = @import("fs/filetable.zig");
const INodeTable = @import("fs/inodetable.zig");

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

        BufferCache.init();
        FileTable.init();
        INodeTable.init();
        Virtio.init();
        Device.init();
        StdOut.init();

        Process.userInit() catch |e| {
            lib.println("error initializing user process");
            lib.printf("error: {}\n", .{e});
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
