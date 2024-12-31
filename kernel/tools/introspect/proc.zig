const std = @import("std");
const utils = @import("utils.zig");

const Command = @import("command.zig");
const TrapContext = @import("trap.zig");
const Source = @import("source.zig");

const riscv = @import("../../riscv.zig");

const Process = @import("../../procs/proc.zig");

const main_menu_items = [_]Command{
    .{
        .type = .{ .parse = &list },
    },
    .{
        .type = .{ .parse = &getProc },
    },
};

const main_menu = Command{
    .type = .{ .children = main_menu_items[0..] },
    .help =
    \\Processes:
    \\l - list
    \\c - current process
    \\[PID: u64] - pid
    ,
};

const proc_menu_items = [_]Command{
    .{
        .type = .{ .parse = &fileTable },
    },
    .{
        .type = .{ .parse = &stackTrace },
    },
    .{
        .type = .{ .parse = &kstackTrace },
    },
};

const proc_menu = Command{
    .type = .{ .children = proc_menu_items[0..] },
    .help =
    \\Process Data:
    \\st - stack trace
    \\kst - kernel stack trace
    ,
};

pub fn parse(src: *Source, context: ?*anyopaque) ?Command {
    src.matchIden("p") orelse return null;
    return main_menu.parse(src, context);
}

pub fn list(src: *Source, _: ?*anyopaque) ?Command {
    src.matchIden("l") orelse return null;
    utils.logln("PID\tName\tState");
    for (Process.PROCS) |p| {
        if (p.state == .Unused) continue;
        utils.logf("{}\t", .{p.pid});
        utils.logNullTerm(&p.name);
        utils.logf("\t{s}\t\n", .{@tagName(p.state)});
    }
    return Command.end;
}

pub fn getProc(src: *Source, _: ?*anyopaque) ?Command {
    var pid: u64 = 0;
    if (src.matchIden("c")) |_| {
        if (TrapContext.cur.cur_proc) |p| pid = p.pid else return null;
    } else {
        src.matchNum() orelse return null;
        pid = src.getNum(u64).?;
    }
    var proc = Process.PROCS[pid];
    return proc_menu.parse(src, &proc);
}

pub fn fileTable(src: *Source, ctx: ?*anyopaque) ?Command {
    src.matchIden("ft") orelse return null;
    const proc: *Process = @alignCast(@ptrCast(ctx orelse return null));

    utils.logln("File table:");

    for (proc.open_files, 0..) |maybe_f, i| {
        if (maybe_f) |f| switch (f.data) {
            .inode_file => |file| {
                utils.logf("{}\t{}\tinode \n", .{ i, file.inode.inum });
            },
            .device => |d| {
                utils.logf("{}\t{}\tdevice\n", .{ i, d.inode.inum });
            },
            .pipe => {
                utils.logf("{d}: pipe\n", .{i});
            },
            else => {
                utils.logf("{d}: unknown\n", .{i});
            },
        };
    }

    return Command.end;
}
pub fn stackTrace(src: *Source, _: ?*anyopaque) ?Command {
    src.matchIden("st") orelse return null;

    return Command.end;
}

pub fn kstackTrace(src: *Source, ctx: ?*anyopaque) ?Command {
    src.matchIden("kst") orelse return null;

    const proc: *Process = @alignCast(@ptrCast(ctx orelse return null));
    const stack_top = proc.kstackPtr + riscv.KSTACK_SIZE;

    const ra = TrapContext.cur.ra;
    var frame = TrapContext.cur.fp.?;

    utils.logln("Kernel stack trace:");
    utils.logf("0x{x},\n", .{ra});
    while (@intFromPtr(frame) < stack_top and frame.ra < riscv.PHYSTOP) {
        utils.logf("0x{x},\n", .{frame.ra});
        frame = frame.fp;
    }

    return Command.end;
}
