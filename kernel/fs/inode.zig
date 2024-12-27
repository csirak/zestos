const lib = @import("../lib.zig");
const fs = @import("fs.zig");

const Sleeplock = @import("../locks/sleeplock.zig");
const Process = @import("../procs/proc.zig");
const BufferCache = @import("buffercache.zig");
const Log = @import("log.zig");
const INodeTable = @import("inodetable.zig");

const Self = @This();

device: u16,
inum: u16,
reference_count: u16,

sleeplock: Sleeplock,
valid: bool,
disk_inode: fs.DiskINode,

pub const Stat = extern struct {
    device: i32,
    inum: u32,
    typ: u16,
    reference_count: u16,
    size: u64,
};

pub fn lock(self: *Self) void {
    if (self.reference_count < 1) {
        lib.kpanic("INode lock failed");
    }

    self.sleeplock.acquire();
    if (self.valid) {
        return;
    }
    self.disk_inode = BufferCache.loadInodeFromDisk(self.device, self.inum);
    self.valid = true;
}

pub fn release(self: *Self) void {
    if (!self.sleeplock.isHolding() and self.reference_count < 1) {
        lib.kpanic("INode release failed");
    }

    self.sleeplock.release();
}

pub fn mapBlock(self: *Self, addr_index: u16) u32 {
    if (addr_index < fs.DIRECT_ADDRESS_SIZE) {
        const address = self.disk_inode.direct[addr_index];
        if (address != 0) {
            return address;
        }

        const new_addr = BufferCache.allocDiskBlock(self.device);
        self.disk_inode.direct[addr_index] = new_addr;
        return new_addr;
    }

    const indirect_addr_index = addr_index - fs.DIRECT_ADDRESS_SIZE;

    if (indirect_addr_index >= fs.INDIRECT_ADDRESS_SIZE) {
        lib.kpanic("out of indirect address space");
    }

    if (self.disk_inode.addr_block == 0) {
        self.disk_inode.addr_block = BufferCache.allocDiskBlock(self.device);
    }

    var indirect_addr_block_buffer = BufferCache.read(self.device, @intCast(self.disk_inode.addr_block));
    var cur_block = self.disk_inode.addr_block;

    defer BufferCache.release(indirect_addr_block_buffer);
    var indirect_block: *fs.IndirectAddressBlock = @ptrCast(@alignCast(&indirect_addr_block_buffer.data));

    const direct_offset_index = addr_index - fs.DIRECT_ADDRESS_SIZE;
    const indirect_depth = @divFloor(direct_offset_index, fs.INDIRECT_ADDRESS_SIZE);
    const indirect_index = direct_offset_index % fs.INDIRECT_ADDRESS_SIZE;

    for (0..indirect_depth) |_| {
        if (indirect_block.next_block == 0) {
            indirect_block.next_block = BufferCache.allocDiskBlock(self.device);
            Log.write(indirect_addr_block_buffer);
        }
        cur_block = indirect_block.next_block;
        BufferCache.release(indirect_addr_block_buffer);
        indirect_addr_block_buffer = BufferCache.read(self.device, @intCast(indirect_block.next_block));
        indirect_block = @ptrCast(@alignCast(&indirect_addr_block_buffer.data));
    }

    const indirect_addr = indirect_block.addrs[indirect_index];
    if (indirect_addr != 0) {
        return indirect_addr;
    }

    const new_indirect_addr = BufferCache.allocDiskBlock(self.device);
    indirect_block.addrs[indirect_addr_index] = new_indirect_addr;
    Log.write(indirect_addr_block_buffer);

    return new_indirect_addr;
}

pub fn readToAddress(self: *Self, dest: u64, file_start: u64, req_size: u64, comptime user_space: bool) !u32 {
    if (self.disk_inode.size < file_start) {
        return error.OutOfBounds;
    }
    const size = @min(req_size, self.disk_inode.size - file_start);
    var file_offset = file_start;
    var cur_dest = dest;

    var bytes_read: u32 = 0;
    while (bytes_read < size) {
        const addr_index: u16 = @intCast(@divFloor(file_offset, fs.BLOCK_SIZE));
        const block_addr = self.mapBlock(addr_index);
        const block_buffer = BufferCache.read(self.device, @intCast(block_addr));
        defer BufferCache.release(block_buffer);
        const bytes_to_write: u32 = @intCast(@min(size - bytes_read, fs.BLOCK_SIZE - (file_offset % fs.BLOCK_SIZE)));
        const bytes_offset = file_offset % fs.BLOCK_SIZE;
        var src: [*]u8 = @ptrCast(&block_buffer.data[bytes_offset]);
        if (user_space) {
            var user_pagetable = Process.currentOrPanic().pagetable;
            try user_pagetable.copyInto(cur_dest, src, bytes_to_write);
        } else {
            const dest_ptr: *[fs.BLOCK_SIZE]u8 = @ptrFromInt(cur_dest);
            @memcpy(dest_ptr[0..bytes_to_write], src[0..bytes_to_write]);
        }

        bytes_read += bytes_to_write;
        file_offset += bytes_to_write;
        cur_dest += bytes_to_write;
    }

    return bytes_read;
}

pub fn writeToAddress(self: *Self, src: u64, offset: u32, size: u64, comptime user_space: bool) !u64 {
    if (self.disk_inode.size < offset or (offset + size) < offset) {
        return error.OutOfBounds;
    }

    var bytes_written: u32 = 0;
    while (bytes_written < size) {
        const block_offset = bytes_written + offset;
        const block_num: u16 = @intCast(@divFloor(block_offset, fs.BLOCK_SIZE));
        const block_addr = self.mapBlock(block_num);
        var block_buffer = BufferCache.read(self.device, @intCast(block_addr));
        defer BufferCache.release(block_buffer);
        const block_offset_in_block = block_offset % fs.BLOCK_SIZE;
        const bytes_left_in_block = fs.BLOCK_SIZE - block_offset_in_block;
        const bytes_to_write = @min(size - bytes_written, bytes_left_in_block);

        var dest_ptr: *[fs.BLOCK_SIZE]u8 = @ptrCast(@alignCast(&block_buffer.data[block_offset_in_block]));
        if (user_space) {
            try Process.currentOrPanic().pagetable.copyFrom(src, @ptrCast(dest_ptr), bytes_to_write);
        } else {
            const src_bytes: [*]u8 = @ptrFromInt(src + bytes_written);
            @memcpy(dest_ptr[0..bytes_to_write], src_bytes[0..bytes_to_write]);
        }

        Log.write(block_buffer);
        bytes_written += bytes_to_write;
    }
    if (bytes_written + offset > self.disk_inode.size) {
        self.disk_inode.size = (bytes_written + offset);
    }
    INodeTable.update(self);
    return bytes_written;
}

// TODO: SWITCH TO LL
pub fn truncate(self: *Self) void {
    for (0..fs.DIRECT_ADDRESS_SIZE) |i| {
        if (self.disk_inode.direct[i] != 0) {
            BufferCache.free(self.device, @intCast(self.disk_inode.direct[i]));
            self.disk_inode.direct[i] = 0;
        }
    }

    if (self.disk_inode.addr_block != 0) {
        const indirect_address_block_num: u16 = @intCast(self.disk_inode.addr_block);
        const indirect_buffer = BufferCache.read(self.device, indirect_address_block_num);
        defer BufferCache.release(indirect_buffer);
        defer BufferCache.free(self.device, indirect_address_block_num);

        const indirect_addresses: *[fs.INDIRECT_ADDRESS_SIZE]u32 = @ptrCast(&indirect_buffer.data);
        for (0..fs.INDIRECT_ADDRESS_SIZE) |j| {
            if (indirect_addresses[j] != 0) {
                BufferCache.free(self.device, @intCast(indirect_addresses[j]));
            }
        }
        self.disk_inode.addr_block = 0;
    }

    self.disk_inode.size = 0;
    INodeTable.update(self);
}

pub fn getStat(self: *Self, stat: *Stat) void {
    stat.device = @intCast(self.device);
    stat.inum = @intCast(self.inum);
    stat.typ = self.disk_inode.typ;
    stat.reference_count = self.reference_count;
    stat.size = @intCast(self.disk_inode.size);
}

pub fn isDirEmpty(self: *Self) !bool {
    var current_offset: u32 = 2 * @sizeOf(fs.DirEntry);
    var current_dirent: fs.DirEntry = undefined;
    while (current_offset < self.disk_inode.size) : (current_offset += @sizeOf(fs.DirEntry)) {
        const read_bytes = try self.readToAddress(@intFromPtr(&current_dirent), @intCast(current_offset), @sizeOf(fs.DirEntry), false);
        if (read_bytes != @sizeOf(fs.DirEntry)) {
            lib.kpanic("Dirent misaligned bytes");
        }
        if (current_dirent.inum != 0) {
            return false;
        }
    }
    return true;
}
