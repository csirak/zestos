const std = @import("std");

const riscv = @import("../../riscv.zig");
const lib = @import("../../lib.zig");
const kmem = @import("../../mem/kmem.zig");
const mem = @import("../../mem/mem.zig");

const Console = @import("../../io/console.zig");

const ErrContext = @import("err.zig");
const Menu = @import("menu.zig").Menu;

const STACK_SIZE = 5;

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

// too large for kstack
var input_buf = [_]u8{0} ** riscv.PGSIZE;

pub fn init() !void {
    const frame = struct {
        var sp: u64 = undefined;
        var new_sp: u64 = undefined;
    };

    frame.sp = riscv.r_sp();
    frame.new_sp = @intFromPtr(try kmem.allocMult(STACK_SIZE));
    // guard page change to single map
    try kmem.pagetable.revokePagePerm(frame.new_sp, mem.PTE_W);

    riscv.w_sp(frame.new_sp + STACK_SIZE * riscv.PGSIZE);

    const err_context = ErrContext.loadFromTrap();
    _ = err_context;

    lib.print("\n\nINSTROSPECTION MODE\n\n");
    while (true) {
        const line = getLine();
        if (std.mem.eql(u8, line, "q")) {
            break;
        }
        _ = Menu.parse(line, null);
    }
    lib.print("\n\nEND INSTROSPECTION MODE\n\n");

    riscv.w_sp(frame.sp);

    try kmem.pagetable.enablePagePerm(frame.new_sp, mem.PTE_W);
    kmem.freeRange(frame.new_sp, frame.new_sp + STACK_SIZE * riscv.PGSIZE);
}

fn getLine() []u8 {
    var cur: u64 = 0;
    @memset(&input_buf, 0);
    lib.print("\n> ");
    while (!validInput(input_buf)) : (cur += @sizeOf(u8)) {
        const write_addr = @intFromPtr(&input_buf) + cur;
        _ = Console.read(false, write_addr, 1) catch |e| lib.printf("error: {}\n", .{e});
    }
    return input_buf[0 .. cur - 1];
}

fn validInput(buf: riscv.Page) bool {
    for (buf) |c| {
        if (c == '\n') {
            return true;
        }
    }
    return false;
}
