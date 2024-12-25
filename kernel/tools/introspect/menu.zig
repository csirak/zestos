const Command = @import("command.zig");
const InodeTable = @import("inodetable.zig");
const Disk = @import("disk.zig");

const children = [_]Command{
    .{
        .type = .{ .parse = &InodeTable.parse },
    },
    .{
        .type = .{ .parse = &Disk.parse },
    },
};

pub const Menu = Command{ .type = .{ .children = children[0..] } };
