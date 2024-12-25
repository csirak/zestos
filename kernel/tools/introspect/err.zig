const Process = @import("../../procs/proc.zig");

const riscv = @import("../../riscv.zig");
const lib = @import("../../lib.zig");

scause: u64,
stval: u64,
sepc: u64,
cur_proc: ?struct {
    pid: u64,
    epc: u64,
},

pub fn loadFromTrap() @This() {
    return .{
        .scause = riscv.r_scause(),
        .stval = riscv.r_stval(),
        .sepc = riscv.r_sepc(),
        .cur_proc = if (Process.current()) |p| .{
            .pid = p.getPid(),
            .epc = p.trapframe.?.epc,
        } else null,
    };
}

pub fn log(self: @This()) void {
    lib.printf("scause    | 0x{x}\n", .{self.scause});
    lib.printf("stval     | 0x{x}\n", .{self.stval});
    lib.printf("sepc      | 0x{x}\n", .{self.sepc});

    if (self.cur_proc) |p| {
        lib.printf("pid       | 0x{x}\n", .{p.pid});
        lib.printf("epc       | 0x{x}\n", .{p.epc});
    }
}
