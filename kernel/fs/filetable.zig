const fs = @import("fs.zig");
const Spinlock = @import("../locks/spinlock.zig");
const File = @import("file.zig");

var lock: Spinlock = undefined;
var files: [fs.NUM_FILES]File = undefined;

pub fn init() void {
    lock = Spinlock.init("file table");
}
