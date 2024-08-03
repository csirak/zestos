const fs = @import("fs.zig");
const lib = @import("../lib.zig");

const Spinlock = @import("../locks/spinlock.zig");
const File = @import("file.zig");

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
