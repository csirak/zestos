const std = @import("std");

const Command = @import("command.zig");
const utils = @import("utils.zig");

const blockdump = @import("../blockdump.zig");

const fs = @import("../../fs/fs.zig");
const Buffer = @import("../../fs/buffer.zig");
const Inode = @import("../../fs/inode.zig");
const InodeTable = @import("../../fs/inodetable.zig");

const menu_items = [_]Command{
    .{
        .type = .{ .parse = &list },
    },
    .{
        .type = .{ .parse = &help },
    },
    .{
        .type = .{ .parse = &indirectList },
    },
};

const menu = Command{
    .type = .{ .children = menu_items[0..] },
};

pub fn parse(source: []u8, context: ?*anyopaque) ?Command {
    const name = "it";
    if (!utils.matchName(name, source)) return null;
    return menu.parse(source[name.len..], context);
}
pub fn list(source: []u8, _: ?*anyopaque) ?Command {
    const name = "l";
    if (!utils.matchName(name, source)) return null;

    utils.logln("Inum\tType\tReferences\tInode Block\tFirst Block\tAddress Block\tSize");

    for (loadInodes(), 0..) |in, i| {
        if (in.num_links == 0) continue;
        utils.logf("{d}", .{i});
        utils.logf("\t{s}", .{fs.logTyp(in.typ)});
        utils.logf("\t{d}\t", .{in.num_links});
        utils.logf("\t0x{x}\t", .{fs.inodeBlockNum(@intCast(i))});
        utils.logf("\t0x{x}\t", .{in.direct[0]});
        utils.logf("\t0x{x}\t", .{in.addr_block});
        utils.logf("\t{d}\n", .{in.size});
    }

    return Command.end;
}

pub fn help(source: []u8, _: ?*anyopaque) ?Command {
    const name = "h";
    if (!utils.matchName(name, source)) return null;
    utils.logln("Inode Table: ");
    utils.logln("l - list inodes");
    return Command.end;
}

pub fn indirectList(source: []u8, _: ?*anyopaque) ?Command {
    const name = "il";
    if (!utils.matchName(name, source)) return null;

    const src = utils.cleanSource(source[name.len..]);
    const len = utils.parseNum(src) orelse return null;
    const inum = std.fmt.parseUnsigned(u16, src[0..len], 0) catch |e| {
        utils.logf("Parse Error: {s} {}", .{ src, e });
        return null;
    };
    if (inum >= fs.NUM_INODES) return null;

    const inode = loadInodes()[inum];

    utils.logf("Inode: {}\n", .{inum});

    var cur = inode.addr_block;
    while (cur != 0) {
        const addrs = std.mem.bytesAsValue(fs.IndirectAddressBlock, &utils.loadBlock(fs.ROOT_DEVICE, @intCast(cur)));
        utils.logf("0x{x}\n", .{cur});
        cur = addrs.next_block;
    }

    return Command.end;
}

// batch for disk read
// not threadsafe yet
fn loadInodes() *[fs.NUM_INODES]fs.DiskINode {
    const static = struct {
        var inode_blocks: [fs.NUM_INODE_BLOCKS]fs.Block align(8) = undefined;
    };

    for (0..fs.NUM_INODE_BLOCKS) |i| {
        const block = utils.loadBlock(fs.ROOT_DEVICE, @intCast(fs.loaded_super_block.inode_start + i));
        @memcpy(static.inode_blocks[i][0..], block[0..]);
    }
    return @ptrCast(&static.inode_blocks);
}
