const fs = @import("fs.zig");
const lib = @import("../lib.zig");

const Spinlock = @import("../locks/spinlock.zig");
const File = @import("file.zig");
const Log = @import("log.zig");
const INodeTable = @import("inodetable.zig");

var lock: Spinlock = undefined;
var files: [fs.NUM_FILES]File = undefined;

pub fn init() void {
    lock = Spinlock.init("file table");
}

pub fn alloc() *File {
    lock.acquire();
    defer lock.release();

    for (&files) |*file| {
        if (file.reference_count == 0) {
            file.reference_count += 1;
            return file;
        }
    }

    @panic("buffer cache is full");
}

pub fn free(file: *File) void {
    var file_data = file.*;
    // so we release lock before io
    {
        lock.acquire();
        defer lock.release();
        switch (file.reference_count) {
            1 => {
                file.reference_count = 0;
            },
            0 => @panic("file closed"),
            else => {
                file.reference_count = file.reference_count - 1;
                return;
            },
        }
        file.data = .none;
    }

    switch (file_data.data) {
        .pipe => {},
        .inode_file, .device => {
            Log.beginTx();
            defer Log.endTx();
            INodeTable.removeRef(file_data.getInode());
        },
        else => {
            @panic("invalid file data");
        },
    }
}

pub fn duplicate(file: *File) *File {
    lock.acquire();
    defer lock.release();
    if (file.reference_count < 1) {
        @panic("filedup doesnt exist");
    }
    file.reference_count += 1;
    return file;
}
