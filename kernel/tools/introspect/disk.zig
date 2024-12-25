const std = @import("std");

const Command = @import("command.zig");
const utils = @import("utils.zig");

const blockdump = @import("../blockdump.zig");

const fs = @import("../../fs/fs.zig");

const menu_items = [_]Command{
    .{
        .type = .{ .parse = &read },
    },
    .{
        .type = .{ .parse = &help },
    },
};

const menu = Command{
    .type = .{ .children = menu_items[0..] },
};

pub fn parse(source: []u8, context: ?*anyopaque) ?Command {
    const name = "d";
    if (!utils.matchName(name, source)) return null;
    return menu.parse(source[name.len..], context);
}

pub fn read(source: []u8, _: ?*anyopaque) ?Command {
    const name = "r";
    if (!utils.matchName(name, source)) return null;

    const src = utils.cleanSource(source[name.len..]);
    const len = utils.parseNum(src) orelse return null;
    const block_num = std.fmt.parseUnsigned(u16, src[0..len], 0) catch |e| {
        utils.logf("Parse Error: {s} {}", .{ src, e });
        return null;
    };
    if (block_num >= fs.TOTAL_BLOCKS) return null;
    const block = utils.loadBlock(fs.ROOT_DEVICE, block_num);

    utils.logln("");
    blockdump.blockDump(block_num, &block, 8);
    return Command.end;
}

pub fn help(source: []u8, _: ?*anyopaque) ?Command {
    const name = "h";
    if (!utils.matchName(name, source)) return null;
    utils.logln("Disk: ");
    utils.logln("r - read block");
    utils.logln("params: block_num: u16");
    return Command.end;
}
