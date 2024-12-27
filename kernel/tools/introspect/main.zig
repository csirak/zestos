const std = @import("std");

const Source = @import("source.zig");
const TrapContext = @import("trap.zig");

const Menu = @import("menu.zig").Menu;

const riscv = @import("../../riscv.zig");
const lib = @import("../../lib.zig");
const kmem = @import("../../mem/kmem.zig");
const mem = @import("../../mem/mem.zig");

const Console = @import("../../io/console.zig");

const STACK_SIZE = 5;

// too large for kstack
var input_buf = [_]u8{0} ** riscv.PGSIZE;

// goals: allow queries over the kernel data
//    - process context
//         - sycalls
//         - faults
//     - process memory
//         - both kernel and proc address
//     - kernel state
//     - processes
//     - kernel memory
//     - files
//     - disk
pub fn init(ra: u64, fp: u64) !void {
    const frame = struct {
        var sp: u64 = undefined;
        var new_sp: u64 = undefined;
    };

    frame.sp = riscv.r_sp();
    frame.new_sp = @intFromPtr(try kmem.allocMult(STACK_SIZE));
    // guard page change to single map
    try kmem.pagetable.revokePagePerm(frame.new_sp, mem.PTE_W);

    riscv.w_sp(frame.new_sp + STACK_SIZE * riscv.PGSIZE);

    TrapContext.load(ra, fp);

    lib.print("\n\nINSTROSPECTION MODE\n\n");
    while (true) {
        var line = getLine();
        if (line.isNext("q")) {
            break;
        }
        _ = Menu.parse(&line, null);
    }

    riscv.w_sp(frame.sp);

    try kmem.pagetable.enablePagePerm(frame.new_sp, mem.PTE_W);
    kmem.freeRange(frame.new_sp, frame.new_sp + STACK_SIZE * riscv.PGSIZE);
}

fn getLine() Source {
    var cur: u64 = 0;
    @memset(&input_buf, 0);
    lib.print("\n> ");
    while (!validInput(input_buf)) : (cur += @sizeOf(u8)) {
        const write_addr = @intFromPtr(&input_buf) + cur;
        _ = Console.read(false, write_addr, 1) catch |e| lib.printf("error: {}\n", .{e});
    }
    return Source.init(input_buf[0 .. cur - 1]);
}

fn validInput(buf: riscv.Page) bool {
    for (buf) |c| {
        if (c == '\n') {
            return true;
        }
    }
    return false;
}
