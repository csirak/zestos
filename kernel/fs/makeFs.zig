const std = @import("std");
const debug = std.debug;

const fs = @import("fs.zig");

var free_inode: u16 = 1;
var free_block: u32 = fs.NUM_META_BLOCKS;
var disk: std.fs.File = undefined;
var glob_log: bool = false;

fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (glob_log) {
        debug.print(fmt, args);
    }
}

pub fn makeFs(log: bool) void {
    glob_log = log;
    debugPrint("nmeta: {d} (boot, super, log blocks: {d} inode blocks: {d}, bitmap blocks: {d})\ndata blocks: {d}\ntotal: {d}\n\n", .{ fs.NUM_META_BLOCKS, fs.NUM_LOG_BLOCKS, fs.NUM_INODE_BLOCKS, fs.NUM_BITMAP_BLOCKS, fs.NUM_DATA_BLOCKS, fs.TOTAL_BLOCKS });

    const file_name = "fs.img";

    disk = std.fs.cwd().createFile(file_name, .{ .read = true }) catch |err| {
        debug.panic("Failed to create disk: {s}", .{@errorName(err)});
    };
    defer disk.close();

    writeZeros();

    writeSuperBlock();

    const root_inum = diskINodeAlloc(fs.INODE_DIR);

    const dot = fs.dirEntry(root_inum, ".");
    const dotdot = fs.dirEntry(root_inum, "..");

    iNodeAppend(root_inum, std.mem.asBytes(&dot));
    iNodeAppend(root_inum, std.mem.asBytes(&dotdot));

    addUserProgram("user/_init", "init");
    addUserProgram("user/_sh", "sh");

    var root_inode: fs.DiskINode = undefined;
    readINode(root_inum, &root_inode);

    root_inode.size = (@divFloor(root_inode.size, fs.BLOCK_SIZE) + 1) * fs.BLOCK_SIZE;
    writeINode(root_inum, root_inode);
    bitMapAdd(free_block);
    debugPrint("blocks used: {d}\n", .{free_block - fs.NUM_META_BLOCKS});
}

fn writeZeros() void {
    const zero = [_]u8{0} ** fs.BLOCK_SIZE;
    var i: u64 = 0;
    while (i < fs.TOTAL_BLOCKS) : (i += 1) {
        writeBlock(i, zero);
    }
}

fn writeSuperBlock() void {
    const extension_bytes_size = fs.BLOCK_SIZE - @sizeOf(fs.SuperBlock);
    const extension_bytes = [_]u8{0} ** extension_bytes_size;
    const super_block_bytes: [@sizeOf(fs.SuperBlock)]u8 = @bitCast(fs.SUPER_BLOCK);
    writeBlock(fs.SUPER_BLOCK_NUM, super_block_bytes ++ extension_bytes);
}

fn diskINodeAlloc(typ: u16) u16 {
    defer free_inode += 1;

    const inode = fs.DiskINode{
        .typ = typ,
    };
    writeINode(free_inode, inode);

    return free_inode;
}

fn writeINode(inum: u16, inode: fs.DiskINode) void {
    var buffer: fs.Block = undefined;
    const block_num = fs.inodeBlockNum(inum);
    readBlock(block_num, &buffer);

    const inode_bytes = std.mem.asBytes(&inode);
    const index = inum % fs.INODES_PER_BLOCK;
    const block_offset = index * @sizeOf(fs.DiskINode);
    const indexed_buffer = buffer[block_offset..];

    @memcpy(indexed_buffer[0..@sizeOf(fs.DiskINode)], inode_bytes);
    writeBlock(block_num, buffer);
}

fn readINode(inum: u16, inode: *fs.DiskINode) void {
    var buffer: fs.Block = undefined;
    const block_num = fs.inodeBlockNum(inum);
    readBlock(block_num, &buffer);

    const index = inum % fs.INODES_PER_BLOCK;
    const block_offset = index * @sizeOf(fs.DiskINode);
    const inode_bytes = buffer[block_offset..][0..@sizeOf(fs.DiskINode)];
    const buffer_inode: *const fs.DiskINode = @alignCast(@ptrCast(inode_bytes));
    inode.* = buffer_inode.*;
}

fn iNodeAppend(inum: u16, bytes: []const u8) void {
    var buffer: fs.Block = undefined;
    var inode: fs.DiskINode = undefined;
    readINode(inum, &inode);
    // debug.print("inode size: {d} bytes added: {d}\n", .{ inode.size, bytes.len });

    var file_offset = inode.size;
    var bytes_left = bytes.len;

    var indirect_addrs_cache: ?[fs.INDIRECT_ADDRESS_SIZE]u32 = null;

    const blocks_to_write = @divFloor(inode.size + bytes.len, fs.BLOCK_SIZE);
    if (blocks_to_write > fs.MAX_ADDRESS_SIZE) {
        debug.panic("File offset out of bounds", .{});
    }

    while (bytes_left > 0) {
        const block_index = @divFloor(file_offset, fs.BLOCK_SIZE);

        const block_num = num: {
            if (block_index < fs.DIRECT_ADDRESS_SIZE) {
                // get block within direct range
                if (inode.direct[block_index] == 0) {
                    inode.direct[block_index] = free_block;
                    free_block += 1;
                }
                break :num inode.direct[block_index];
            } else {
                // get block within indirect range
                if (inode.direct[fs.DIRECT_ADDRESS_SIZE] == 0) {
                    inode.direct[fs.DIRECT_ADDRESS_SIZE] = free_block;
                    free_block += 1;
                }
                // load indirect address only once into cache
                var indirect_addrs = indirect_addrs_cache orelse addrs: {
                    indirect_addrs_cache = undefined;
                    const indirect_block_num = inode.direct[fs.DIRECT_ADDRESS_SIZE];
                    readBlock(indirect_block_num, @ptrCast(@alignCast(&indirect_addrs_cache)));
                    break :addrs indirect_addrs_cache.?;
                };

                // get block within indirect range
                const indirect_index = block_index - fs.DIRECT_ADDRESS_SIZE;
                if (indirect_addrs[indirect_index] == 0) {
                    indirect_addrs[indirect_index] = free_block;
                    free_block += 1;
                }
                break :num indirect_addrs[indirect_index];
            }
        };

        readBlock(block_num, &buffer);

        const file_bytes_left_in_block = fs.BLOCK_SIZE - (file_offset % fs.BLOCK_SIZE);
        const bytes_to_write = @min(bytes_left, file_bytes_left_in_block);
        const buffer_write_offset = file_offset - (block_index * fs.BLOCK_SIZE);

        const buffer_write_slice = buffer[buffer_write_offset..][0..bytes_to_write];
        @memcpy(buffer_write_slice, bytes[0..bytes_to_write]);

        bytes_left -= bytes_to_write;
        file_offset += bytes_to_write;
        writeBlock(block_num, buffer);
    }
    inode.size = file_offset;
    writeINode(inum, inode);
}

fn readBlock(block_num: u64, block: *fs.Block) void {
    disk.seekTo(block_num * fs.BLOCK_SIZE) catch |err| {
        debug.panic("Failed to seek to block {d}: {s}", .{ block_num, @errorName(err) });
    };
    _ = disk.readAll(block) catch |err| {
        debug.panic("Failed to read block {d}: {s}", .{ block_num, @errorName(err) });
    };
}

fn writeBlock(block_num: u64, block: fs.Block) void {
    disk.seekTo(block_num * fs.BLOCK_SIZE) catch |err| {
        debug.panic("Failed to seek to block {d}: {s}", .{ block_num, @errorName(err) });
    };
    disk.writeAll(&block) catch |err| {
        debug.panic("Failed to write block {d}: {s}", .{ block_num, @errorName(err) });
    };
}

fn bitMapAdd(blocks: u64) void {
    var buffer: fs.Block = undefined;
    for (0..(blocks)) |block| {
        const block_index = @divFloor(block, fs.BLOCK_SIZE) + fs.SUPER_BLOCK.bmap_start;
        const byte_index = @divFloor(block, 8);
        const bit_index = block % 8;
        readBlock(block_index, &buffer);
        buffer[byte_index] |= @as(u8, 1) << @intCast(bit_index);
        writeBlock(block_index, buffer);
    }
}

fn addUserProgram(path: []const u8, name: []const u8) void {
    debugPrint("adding user program {s}\n", .{name});
    const inode = diskINodeAlloc(fs.INODE_FILE);
    const dir_entry = fs.dirEntry(inode, name);
    iNodeAppend(fs.ROOT_INODE, std.mem.asBytes(&dir_entry));

    const program_file = std.fs.cwd().openFile(path, .{}) catch |err| {
        debug.panic("Failed to create disk: {s}", .{@errorName(err)});
    };

    var buffer: [1024]u8 = undefined;
    const size = program_file.getEndPos() catch |err| {
        debug.panic("Failed to get program file size: {s}", .{@errorName(err)});
    };
    var bytes_read: u64 = 0;
    while (bytes_read < size) {
        bytes_read += program_file.readAll(&buffer) catch |err| {
            debug.panic("Failed to read program file: {s}", .{@errorName(err)});
        };
        iNodeAppend(inode, &buffer);
    }
    debugPrint("bytes_read: {d}\n", .{bytes_read});
}
