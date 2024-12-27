const std = @import("std");

const utils = @import("utils.zig");

const Command = @import("command.zig");
const Source = @import("source.zig");

const blockdump = @import("../blockdump.zig");

const fs = @import("../../fs/fs.zig");

const menu_items = [_]Command{
    .{
        .type = .{ .parse = &read },
    },
};

const menu = Command{
    .type = .{ .children = menu_items[0..] },
    .help =
    \\Disk:
    \\r - read block
    \\params: block_num: u16
    ,
};

pub fn parse(src: *Source, context: ?*anyopaque) ?Command {
    src.matchIden("d") orelse return null;
    return menu.parse(src, context);
}

pub fn read(src: *Source, _: ?*anyopaque) ?Command {
    src.matchIden("r") orelse return null;
    src.matchNum() orelse return null;

    const block_num = src.getNum(u16).?;
    if (block_num >= fs.TOTAL_BLOCKS) return null;
    const block = utils.loadBlock(fs.ROOT_DEVICE, block_num);

    utils.logln("");
    blockdump.blockDump(block_num, &block, 8);
    return Command.end;
}
