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

    const zero = [_]u8{0} ** fs.BLOCK_SIZE;
    var i: u64 = 0;
    while (i < fs.TOTAL_BLOCKS) : (i += 1) {
        writeBlock(i, zero);
    }

    writeSuperBlock();

    const root_inum = diskINodeAlloc(fs.INODE_DIR);

    const dot = fs.dirEntryBytes(root_inum, ".");
    const dotdot = fs.dirEntryBytes(root_inum, "..");

    iNodeAppend(root_inum, dot, @sizeOf(fs.DirEntry));
    iNodeAppend(root_inum, dotdot, @sizeOf(fs.DirEntry));

    addUserPrograms("user/bin", std.heap.page_allocator) catch |err| {
        debug.panic("Failed to add user programs: {s}", .{@errorName(err)});
    };

    var root_inode: fs.DiskINode = undefined;
    readINode(root_inum, &root_inode);

    root_inode.size = (@divFloor(root_inode.size, fs.BLOCK_SIZE) + 1) * fs.BLOCK_SIZE;
    writeINode(root_inum, root_inode);
    bitMapAdd(free_block);
    debugPrint("blocks used: {d}\n", .{free_block - fs.NUM_META_BLOCKS});
}

fn writeSuperBlock() void {
    const extension_bytes = [_]u8{0} ** (fs.BLOCK_SIZE - @sizeOf(fs.SuperBlock));
    const super_block_bytes = std.mem.toBytes(fs.SUPER_BLOCK);
    writeBlock(fs.SUPER_BLOCK_NUM, super_block_bytes ++ extension_bytes);
}

fn diskINodeAlloc(typ: u16) u16 {
    const inode = fs.DiskINode{
        .typ = typ,
    };
    writeINode(free_inode, inode);

    defer free_inode += 1;
    return free_inode;
}

fn writeINode(inum: u16, inode: fs.DiskINode) void {
    var buffer: fs.Block = undefined;
    const block_num = fs.inodeBlockNum(inum);
    readBlock(block_num, &buffer);

    const index = inum % fs.INODES_PER_BLOCK;
    const block_offset = index * @sizeOf(fs.DiskINode);
    const buffer_inode: *fs.DiskINode = @alignCast(@ptrCast(buffer[block_offset..][0..@sizeOf(fs.DiskINode)]));
    buffer_inode.* = inode;

    writeBlock(block_num, buffer);
}

fn readINode(inum: u16, inode: *fs.DiskINode) void {
    var buffer: fs.Block = undefined;
    const block_num = fs.inodeBlockNum(inum);
    readBlock(block_num, &buffer);

    const index = inum % fs.INODES_PER_BLOCK;
    const block_offset = index * @sizeOf(fs.DiskINode);
    const buffer_inode: *fs.DiskINode = @alignCast(@ptrCast(buffer[block_offset..][0..@sizeOf(fs.DiskINode)]));
    inode.* = buffer_inode.*;
}

fn initMapBlock(inode: *fs.DiskINode, block_index: u64) u32 {
    if (block_index < fs.DIRECT_ADDRESS_SIZE) {
        if (inode.direct[block_index] == 0) {
            inode.direct[block_index] = free_block;
            free_block += 1;
        }
        return inode.direct[block_index];
    }
    if (inode.addr_block == 0) {
        inode.addr_block = free_block;
        free_block += 1;
    }
    const direct_offset_index = block_index - fs.DIRECT_ADDRESS_SIZE;
    const indirect_depth = @divFloor(direct_offset_index, fs.INDIRECT_ADDRESS_SIZE);
    const indirect_index = direct_offset_index % fs.INDIRECT_ADDRESS_SIZE;

    var indirect_block = fs.IndirectAddressBlock{};
    var cur_block = inode.addr_block;
    readBlock(cur_block, @ptrCast(@alignCast(&indirect_block)));

    for (0..indirect_depth) |_| {
        if (indirect_block.next_block == 0) {
            indirect_block.next_block = free_block;
            free_block += 1;
            const indirect_addres_bytes = std.mem.toBytes(indirect_block);
            writeBlock(cur_block, indirect_addres_bytes);
        }
        cur_block = indirect_block.next_block;
        readBlock(cur_block, @ptrCast(@alignCast(&indirect_block)));
    }

    if (indirect_block.addrs[indirect_index] == 0) {
        indirect_block.addrs[indirect_index] = free_block;
        const indirect_addres_bytes = std.mem.toBytes(indirect_block);
        writeBlock(cur_block, indirect_addres_bytes);
        free_block += 1;
    }
    return indirect_block.addrs[indirect_index];
}

fn iNodeAppend(inum: u16, bytes: []u8, size: u64) void {
    var buffer: fs.Block = undefined;
    var inode: fs.DiskINode = undefined;
    readINode(inum, &inode);

    const start = inode.size;
    var file_offset = start;
    var bytes_left = size;

    while (bytes_left > 0) {
        const block_index = @divFloor(file_offset, fs.BLOCK_SIZE);

        const block_num = initMapBlock(&inode, block_index);
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
    inode.size += file_offset - start;
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
    const inode_num = diskINodeAlloc(fs.INODE_FILE);
    const dir_entry = fs.dirEntryBytes(inode_num, name);
    iNodeAppend(fs.ROOT_INODE, dir_entry, @sizeOf(fs.DirEntry));

    const program_file = std.fs.cwd().openFile(path, .{}) catch |err| {
        debug.panic("Failed to create disk: {s}", .{@errorName(err)});
    };

    var buffer: fs.Block = undefined;
    const size = program_file.getEndPos() catch |err| {
        debug.panic("Failed to get program file size: {s}", .{@errorName(err)});
    };
    var bytes_read: u64 = 0;
    while (bytes_read < size) {
        const buffer_size = program_file.readAll(&buffer) catch |err| {
            debug.panic("Failed to read program file: {s}", .{@errorName(err)});
        };
        bytes_read += buffer_size;
        iNodeAppend(inode_num, &buffer, buffer_size);
    }
}

fn addUserPrograms(path: []const u8, allocator: std.mem.Allocator) !void {
    const dir = try std.fs.cwd().openDir(path, .{});
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const name = entry.name;
        const paths = [_][]const u8{ path, name };
        const full_path = try std.fs.path.join(allocator, &paths);
        if (entry.kind == .file) {
            if (name[0] != '_') {
                continue;
            }
            // user programs start with _
            addUserProgram(full_path, name[1..]);
            debugPrint("added user program {s}\n", .{name[1..]});
        }
    }
}

pub fn main() void {
    makeFs(true);
}
