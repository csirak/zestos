const fs = @import("fs.zig");

const Sleeplock = @import("../locks/sleeplock.zig");

const Self = @This();

valid: bool,
disk_owned: bool,
modified: bool,
device: u16,
block_num: u16,
reference_count: u16,
sleeplock: Sleeplock,
next: *Self,
prev: *Self,
data: [fs.BLOCK_SIZE]u8 align(8),
