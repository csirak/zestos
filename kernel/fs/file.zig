const std = @import("std");
const fs = @import("fs.zig");
const lib = @import("../lib.zig");

const INode = @import("inode.zig");
const Log = @import("log.zig");
const Pipe = @import("pipe.zig");
const INodeTable = @import("inode.zig");

const Process = @import("../procs/proc.zig");
const Device = @import("../device.zig");

const Self = @This();

pub const FileType = enum(u16) { none, pipe, inode_file, device };

pub const FileInfo = struct {
    inode: *INode,
    offset: u32,
};

pub const DevInfo = struct {
    inode: *INode,
    major: u16,
};

pub const FileData = union(FileType) {
    none: void,
    pipe: *Pipe,
    inode_file: FileInfo,
    device: DevInfo,

    pub fn getType(self: FileData) FileType {
        return @enumFromInt(@intFromEnum(self));
    }
};

reference_count: u16,
readable: bool,
writable: bool,
data: FileData,

pub const O_RDONLY = 0x000;
pub const O_WRONLY = 0x001;
pub const O_RDWR = 0x002;
pub const O_CREATE = 0x200;
pub const O_TRUNC = 0x400;

pub fn read(self: *Self, buffer_ptr: u64, size: u64) !i64 {
    if (!self.readable) {
        return error.PermissionDenied;
    }

    switch (self.data) {
        .pipe => |pipe| {
            return pipe.read(buffer_ptr, size);
        },
        .inode_file => |*info| {
            info.inode.lock();
            defer info.inode.release();
            const ret = try info.inode.readToAddress(
                buffer_ptr,
                info.offset,
                size,
                true,
            );
            info.offset += ret;
            return ret;
        },
        .device => |info| if (Device.getDevice(info.major)) |dev| return try dev.read(
            true,
            buffer_ptr,
            size,
        ),
        else => @panic("invalid file type read"),
    }
    return 0;
}

pub fn write(self: *Self, buffer_ptr: u64, size: u64) !i64 {
    if (!self.writable) {
        return error.PermissionDenied;
    }

    switch (self.data) {
        .pipe => |pipe| {
            return pipe.write(buffer_ptr, size);
        },
        .inode_file => |*file| {
            const max_bytes = (fs.MAX_BLOCKS_PER_OP - 1 - 1 - 2) * fs.BLOCK_SIZE / 2;
            var bytes_written: u64 = 0;
            while (bytes_written < size) {
                const to_write = @min(size - bytes_written, max_bytes);
                Log.beginTx();
                defer Log.endTx();
                file.inode.lock();
                const written = try file.inode.writeToAddress(buffer_ptr + bytes_written, file.offset, to_write, true);
                if (written != to_write) {
                    return error.WriteError;
                }
                file.offset += @truncate(written);
                bytes_written += written;
                file.inode.release();
            }
            return @intCast(bytes_written);
        },
        .device => |info| if (Device.getDevice(info.major)) |dev| return try dev.write(true, buffer_ptr, size),
        else => {
            return error.InvalidFileRead;
        },
    }
    return 0;
}

pub fn getInode(self: *Self) *INode {
    return switch (self.data) {
        .inode_file => |info| info.inode,
        .device => |info| info.inode,
        else => @panic("invalid file type getInode"),
    };
}

pub fn getStat(self: *Self, addr: u64) !i64 {
    const proc = Process.currentOrPanic();
    var stat = std.mem.zeroes(INode.Stat);
    switch (self.data) {
        .inode_file, .device => {},
        else => @panic("invalid file type getStat"),
    }
    const inode = self.getInode();
    inode.lock();
    defer inode.release();
    inode.getStat(&stat);
    try proc.pagetable.copyInto(addr, @ptrCast(&stat), @sizeOf(INode.Stat));
    return 0;
}
