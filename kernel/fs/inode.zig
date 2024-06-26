const lib = @import("../lib.zig");
const fs = @import("fs.zig");

const Sleeplock = @import("../locks/sleeplock.zig");
const Process = @import("../procs/proc.zig");
const BufferCache = @import("buffercache.zig");
const Log = @import("log.zig");

const Self = @This();

device: u16,
inum: u16,
reference_count: u16,

sleep_lock: Sleeplock,
valid: bool,
disk_inode: fs.DiskINode,

pub fn lock(self: *Self) void {
    if (self.reference_count < 1) {
        lib.kpanic("INode lock failed");
    }
    self.sleep_lock.acquire();

    if (self.valid) {
        return;
    }

    const buffer = BufferCache.read(self.device, fs.inodeBlockNum(self.inum));
    const buffer_index = self.inum % fs.INODES_PER_BLOCK;
    const buffer_offset = buffer_index * @sizeOf(fs.DiskINode);
    const inode_bytes = buffer.data[buffer_offset..][0..@sizeOf(fs.DiskINode)];
    const inode: *const fs.DiskINode = @ptrCast(@alignCast(&inode_bytes));
    self.disk_inode = inode.*;
    self.valid = true;
}

pub fn release(self: *Self) void {
    if (!self.sleep_lock.isHolding() and self.reference_count < 1) {
        lib.kpanic("INode release failed");
    }

    self.sleep_lock.release();
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

    if (self.disk_inode.direct[fs.DIRECT_ADDRESS_SIZE] == 0) {
        self.disk_inode.direct[fs.DIRECT_ADDRESS_SIZE] = BufferCache.allocDiskBlock(self.device);
    }

    const indirect_addr_block_num = self.disk_inode.direct[fs.DIRECT_ADDRESS_SIZE];
    const indirect_addr_block_buffer = BufferCache.read(self.device, @intCast(indirect_addr_block_num));
    defer BufferCache.release(indirect_addr_block_buffer);

    const indirect_addr = indirect_addr_block_buffer.data[indirect_addr_index];
    if (indirect_addr != 0) {
        return indirect_addr;
    }

    const new_indirect_addr = BufferCache.allocDiskBlock(self.device);
    const indirect_addrs: *fs.IndirectAddressBlock = @ptrCast(@alignCast(&indirect_addr_block_buffer.data));
    indirect_addrs[indirect_addr_index] = new_indirect_addr;
    Log.write(indirect_addr_block_buffer);

    return new_indirect_addr;
}

pub fn readToAddress(self: *Self, dest: u64, file_start: u64, req_size: u64, user_addr: bool) !u32 {
    if (self.disk_inode.size > file_start) {
        return error.OutOfBounds;
    }
    const size = @min(req_size, self.disk_inode.size - file_start);
    var file_offset = file_start;
    var cur_dest = dest;

    var bytes_read: u32 = 0;
    while (bytes_read < size) {
        const addr_index: u16 = @intCast(file_offset / fs.BLOCK_SIZE);
        const block_addr = self.mapBlock(addr_index);
        const block_buffer = BufferCache.read(self.device, @intCast(block_addr));
        defer BufferCache.release(block_buffer);
        const bytes_to_write: u32 = @intCast(@min(size - bytes_read, fs.BLOCK_SIZE - (file_offset % fs.BLOCK_SIZE)));
        const bytes_offset = file_offset % fs.BLOCK_SIZE;
        var src = block_buffer.data[bytes_offset..];
        if (user_addr) {
            const user_pagetable = Process.currentOrPanic().pagetable.?;
            try user_pagetable.copyInto(cur_dest, &src, bytes_to_write);
        } else {
            const dest_ptr: *[fs.BLOCK_SIZE]u8 = @ptrFromInt(cur_dest);
            @memcpy(dest_ptr[0..bytes_to_write], src[0..bytes_to_write]);
        }

        bytes_read += bytes_to_write;
        file_offset += bytes_to_write;
        cur_dest += bytes_to_write;
    }

    return 0;
}
