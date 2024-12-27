const utils = @import("utils.zig");

const Command = @import("command.zig");
const Source = @import("source.zig");

const Process = @import("../../procs/proc.zig");

const lib = @import("../../lib.zig");
const riscv = @import("../../riscv.zig");

const Frame = extern struct {
    ra: u64,
    fp: *Frame,
};

const Context = struct {
    scause: u64 = 0,
    stval: u64 = 0,
    sepc: u64 = 0,
    ra: u64 = 0,
    fp: ?*Frame = null,
    cur_proc: ?struct {
        pid: u64 = 0,
        epc: u64 = 0,
    } = null,
};

pub var cur = Context{};

const menu_items = [_]Command{
    .{
        .type = .{ .parse = &log },
    },
};

const menu = Command{
    .type = .{ .children = menu_items[0..] },
};

pub fn parse(src: *Source, context: ?*anyopaque) ?Command {
    src.matchIden("t") orelse return null;
    return menu.parse(src, context);
}

pub fn log(src: *Source, _: ?*anyopaque) ?Command {
    src.matchIden("a") orelse return null;

    lib.printf("scause    | 0x{x}\n", .{cur.scause});
    lib.printf("stval     | 0x{x}\n", .{cur.stval});
    lib.printf("sepc      | 0x{x}\n", .{cur.sepc});
    lib.printf("ra      | 0x{x}\n", .{cur.ra});

    if (cur.cur_proc) |p| {
        lib.printf("pid       | 0x{x}\n", .{p.pid});
        lib.printf("epc       | 0x{x}\n", .{p.epc});
    }
    return Command.end;
}

pub fn load(ra: u64, fp: u64) void {
    cur = .{
        .scause = riscv.r_scause(),
        .stval = riscv.r_stval(),
        .sepc = riscv.r_sepc(),
        .ra = ra,
        .fp = @ptrFromInt(fp),
        .cur_proc = if (Process.current()) |p| .{
            .pid = p.getPid(),
            .epc = p.trapframe.?.epc,
        } else null,
    };
}
