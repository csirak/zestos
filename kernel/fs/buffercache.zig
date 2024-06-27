const fs = @import("fs.zig");
const lib = @import("../lib.zig");
const tools = @import("../tools/blockdump.zig");

const Buffer = @import("buffer.zig");
const BufferCache = @import("buffercache.zig");
const Virtio = @import("virtio.zig");
const Log = @import("log.zig");
const Spinlock = @import("../locks/spinlock.zig");
const Sleeplock = @import("../locks/sleeplock.zig");

var cache_lock: Spinlock = undefined;
var buffers: [fs.BUFFER_CACHE_SIZE]Buffer = undefined;
var head: Buffer = undefined;

pub fn init() void {
    cache_lock = Spinlock.init("buffer cache");
    head.next = &head;
    head.prev = &head;

    for (&buffers, 0..) |*buffer, i| {
        buffer.next = head.next;
        buffer.prev = &head;

        buffer.sleeplock = Sleeplock.initId("buffer: ", @intCast(i));
        head.next.prev = buffer;
        head.next = buffer;
    }
}
/// returns with sleeplock
pub fn alloc(device: u16, block_num: u16) *Buffer {
    cache_lock.acquire();

    // if already cached
    for (&buffers) |*buffer| {
        if (buffer.device == device and buffer.block_num == block_num) {
            buffer.reference_count += 1;
            buffer.sleeplock.acquire();
            cache_lock.release();
            return buffer;
        }
    }

    var buffer = head.prev;
    while (buffer != &head) : (buffer = buffer.prev) {
        if (buffer.reference_count == 0) {
            buffer.device = device;
            buffer.valid = false;
            buffer.block_num = block_num;
            buffer.reference_count = 1;
            buffer.sleeplock.acquire();
            cache_lock.release();
            return buffer;
        }
    }
    lib.kpanic("buffer cache is full");
}

/// returns with sleeplock
pub fn read(dev: u16, block_num: u16) *Buffer {
    const buffer = alloc(dev, block_num);
    if (!buffer.valid) {
        Virtio.readTo(buffer);
        buffer.valid = true;
    }
    return buffer;
}

pub fn zeroBlock(dev: u16, block_num: u16) void {
    const buffer = read(dev, block_num);
    defer release(buffer);
    @memset(&buffer.data, 0);
    write(buffer);
}

pub fn readFromCache(dev: u16, block_num: u16) *Buffer {
    const buffer = alloc(dev, block_num);
    if (!buffer.valid) {
        lib.kpanic("readFromCache: block not in cache");
    }
    return buffer;
}

pub fn write(buffer: *Buffer) void {
    if (!buffer.sleeplock.isHolding()) {
        lib.kpanic("write: buffer not held");
    }
    Virtio.writeFrom(buffer);
}

pub fn release(buffer: *Buffer) void {
    if (!buffer.sleeplock.isHolding()) {
        lib.kpanic("release: buffer not held");
    }
    buffer.sleeplock.release();

    cache_lock.acquire();
    buffer.reference_count -= 1;

    if (buffer.reference_count == 0) {
        buffer.next.prev = buffer.prev;
        buffer.prev.next = buffer.next;

        buffer.next = head.next;
        buffer.prev = &head;

        head.next.prev = buffer;
        head.next = buffer;
    }
    cache_lock.release();
}

pub fn addRef(buffer: *Buffer) void {
    cache_lock.acquire();
    buffer.reference_count += 1;
    cache_lock.release();
}

pub fn removeRef(buffer: *Buffer) void {
    cache_lock.acquire();
    buffer.reference_count -= 1;
    cache_lock.release();
}

pub fn allocDiskBlock(device: u16) u16 {
    var bitmap_block: u16 = 0;
    while (bitmap_block < fs.SUPER_BLOCK.size) : (bitmap_block += fs.BITS_PER_BLOCK) {
        const bitmap_buffer = BufferCache.read(device, fs.bitMapBlockNum(bitmap_block));
        defer BufferCache.release(bitmap_buffer);
        for (0..fs.BITS_PER_BLOCK) |bi| {
            const block_index: u16 = @intCast(bi);
            const block_num = bitmap_block + block_index;
            const mask = @as(u8, 1) << @intCast(block_num % 8);
            const byte_ptr = &bitmap_buffer.data[block_index / 8];

            if (byte_ptr.* & mask == 0) {
                byte_ptr.* |= mask;
                Log.write(bitmap_buffer);
                zeroBlock(device, block_num);
                return block_num;
            }
        }
    }
    lib.kpanic("out of disk blocks");
}
