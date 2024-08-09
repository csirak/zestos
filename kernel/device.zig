const fs = @import("fs/fs.zig");
const Self = @This();

ptr: *anyopaque,
major: u16,
readFn: *const fn (user_addr: bool, buffer_ptr: u64, size: u64) anyerror!i64,
writeFn: *const fn (user_addr: bool, buffer_ptr: u64, size: u64) anyerror!i64,

pub fn read(self: *Self, user_addr: bool, buffer_ptr: u64, size: u64) !i64 {
    return self.readFn(user_addr, buffer_ptr, size);
}

pub fn write(self: *Self, user_addr: bool, buffer_ptr: u64, size: u64) !i64 {
    return self.writeFn(user_addr, buffer_ptr, size);
}

var DEVICES: [fs.NUM_DEVICES]?Self = undefined;

pub fn init() void {
    for (0..fs.NUM_DEVICES) |i| {
        DEVICES[i] = null;
    }
}

pub fn getDevice(major: u16) ?*Self {
    if (DEVICES[major]) |*device| {
        return device;
    }
    return null;
}

pub fn registerDevice(device: Self) void {
    DEVICES[device.major] = device;
}
