const std = @import("std");
const utils = @import("utils.zig");

const Command = @import("command.zig");
const Source = @import("source.zig");

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
        .type = .{ .parse = &indirectList },
    },
};

const menu = Command{
    .type = .{ .children = menu_items[0..] },
    .help =
    \\Inode Table: 
    \\l - list inodes
    \\il - indirect block address list 
    ,
};

pub fn parse(src: *Source, context: ?*anyopaque) ?Command {
    src.matchIden("it") orelse return null;
    return menu.parse(src, context);
}

pub fn list(src: *Source, _: ?*anyopaque) ?Command {
    src.matchIden("l") orelse return null;

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

pub fn indirectList(src: *Source, _: ?*anyopaque) ?Command {
    src.matchIden("il") orelse return null;
    src.matchNum() orelse return null;

    const inum = src.getNum(u16).?;

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
