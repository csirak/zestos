const Command = @import("command.zig");

const Disk = @import("disk.zig");
const TrapContext = @import("trap.zig");
const InodeTable = @import("inodetable.zig");
const Process = @import("proc.zig");

const children = [_]Command{
    .{
        .type = .{ .parse = &Disk.parse },
    },
    .{
        .type = .{ .parse = &InodeTable.parse },
    },
    .{
        .type = .{ .parse = &TrapContext.parse },
    },
    .{
        .type = .{ .parse = &Process.parse },
    },
};

pub const Menu = Command{
    .type = .{ .children = children[0..] },
    .help =
    \\Introspection Mode
    \\d - disk
    \\p - processes
    \\t - trap context
    \\it - trap context
    ,
};
