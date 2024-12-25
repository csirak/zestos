const fs = @import("fs.zig");

const Sleeplock = @import("../locks/sleeplock.zig");
const Virtio = @import("virtio.zig");

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

pub fn loadFromDisk(self: *Self, device: u16, block_num: u16) void {
    self.block_num = block_num;
    self.device = device;
    Virtio.readTo(self);
}
