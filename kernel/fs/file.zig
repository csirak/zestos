const fs = @import("fs.zig");
const Pipe = @import("pipe.zig").Pipe;

pub const FileType = enum(u16) { pipe = 1, inode_file, device };

pub const FileInfo = struct {
    inode: *fs.INode,
    offset: u32,
};

pub const DevInfo = struct {
    inode: *fs.INode,
    major: u16,
};

pub const FileData = union(FileType) {
    pipe: *Pipe,
    inode_file: FileInfo,
    device: DevInfo,
};

reference_count: u16,
readable: bool,
writable: bool,
data: FileData,
