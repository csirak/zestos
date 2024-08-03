const fs = @import("fs/fs.zig");
const Self = @This();

ptr: *anyopaque,
major: u16,
writeAllFn: *const fn (ptr: *anyopaque, buffer_ptr: u64, size: u64) anyerror!void,

pub fn write(self: *Self, buffer_ptr: u64, size: u64) !void {
    return self.writeAllFn(self.ptr, buffer_ptr, size);
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
