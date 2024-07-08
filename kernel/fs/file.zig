const INode = @import("inode.zig");
const Pipe = @import("pipe.zig").Pipe;
const Device = @import("../device.zig");
const lib = @import("../lib.zig");

const Self = @This();

pub const FileType = enum(u16) { pipe = 1, inode_file, device };

pub const FileInfo = struct {
    inode: *INode,
    offset: u32,
};

pub const DevInfo = struct {
    inode: *INode,
    major: u16,
};

pub const FileData = union(FileType) {
    pipe: *Pipe,
    inode_file: FileInfo,
    device: DevInfo,

    pub fn getType(self: FileData) FileType {
        return @enumFromInt(@intFromEnum(self));
    }
};

pub fn write(self: *Self, buffer_ptr: u64, size: u64) !void {
    if (!self.writable) {
        return error.PermissionDenied;
    }
    switch (self.data) {
        .pipe => {},
        .inode_file => {},
        .device => |device| {
            try Device.getDevice(device.major).?.write(buffer_ptr, size);
        },
    }
}

reference_count: u16,
readable: bool,
writable: bool,
data: FileData,

pub const O_RDONLY = 0x000;
pub const O_WRONLY = 0x001;
pub const O_RDWR = 0x002;
pub const O_CREATE = 0x200;
pub const O_TRUNC = 0x400;
