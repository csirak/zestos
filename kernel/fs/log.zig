const fs = @import("fs.zig");
const lib = @import("../lib.zig");

const Spinlock = @import("../locks/spinlock.zig");
const Buffer = @import("buffer.zig");
const BufferCache = @import("buffercache.zig");
const Process = @import("../procs/proc.zig");

const Header = struct {
    num_entries: u16,
    blocks: [fs.NUM_LOG_BLOCKS]u16,
};

var lock: Spinlock = undefined;
var size: u16 = 0;
var active_operations: u16 = 0;
var committing: u16 = 0;
var start_block: u16 = 0;
var device: u16 = 0;

var log_header: Header = undefined;

pub fn init(dev: u16, super_block: *fs.SuperBlock) !void {
    lock = Spinlock.init("log");
    device = dev;
    start_block = super_block.log_start;
    size = super_block.num_log_blocks;

    recoverFromLog();
}

pub fn recoverFromLog() !void {
    readHeader();
    writeLogToDisk(true);
    log_header.num_entries = 0;
    writeHeader();
}

fn readHeader() void {
    const buffer = BufferCache.read(device, start_block);
    defer BufferCache.release(buffer);

    const header: *Header = @ptrCast(@alignCast(&buffer.data));
    log_header.num_entries = header.num_entries;

    for (0..log_header.num_entries) |i| {
        log_header.blocks[i] = header.blocks[i];
    }
}

fn writeHeader() void {
    const buffer = BufferCache.read(device, start_block);
    defer BufferCache.release(buffer);

    // ptr to the header == buffer
    var buffer_header: *Header = @ptrCast(@alignCast(&buffer.data));
    buffer_header.num_entries = log_header.num_entries;

    for (0..log_header.num_entries) |i| {
        buffer_header.blocks[i] = log_header.blocks[i];
    }

    BufferCache.write(buffer);
}

fn writeCacheToLog() !void {
    for (0..log_header.num_entries) |log_index| {
        const log_block_index = start_block + log_index + 1;
        const cache_block_num = log_header.blocks[log_index];

        const log_block_buffer = BufferCache.read(device, log_block_index);
        const cache_block_buffer = BufferCache.readFromCache(device, cache_block_num);

        defer BufferCache.release(log_block_buffer);
        defer BufferCache.release(cache_block_buffer);

        @memcpy(log_block_buffer.data, cache_block_buffer.data);
        BufferCache.write(log_block_buffer);
    }
}

fn writeLogToDisk(recovering: bool) void {
    for (0..log_header.num_entries) |log_index| {
        // offset 1 for header block
        const log_block_index = start_block + log_index + 1;
        const block_num = log_header.blocks[log_index];

        const log_block_buffer = BufferCache.read(device, log_block_index);
        const disk_block_buffer = BufferCache.read(device, block_num);

        defer BufferCache.release(log_block_buffer);
        defer BufferCache.release(disk_block_buffer);

        @memcpy(disk_block_buffer.data, log_block_buffer.data);
        if (recovering) {
            BufferCache.removeRef(disk_block_buffer);
        }
        BufferCache.write(disk_block_buffer);
    }
}

pub fn beginTx() void {
    lock.acquire();
    defer lock.release();

    const proc = Process.currentOrPanic();

    while (true) {
        if (committing) {
            proc.sleep(&@This(), &lock);
        }
        const blocks_in_use = log_header.num_entries + (active_operations + 1) * fs.MAX_BLOCKS_PER_OP;
        if (blocks_in_use > fs.NUM_LOG_BLOCKS) {
            proc.sleep(&@This(), &lock);
        } else {
            break;
        }
    }
    active_operations += 1;
}

pub fn endTx() void {
    lock.acquire();
    defer lock.release();

    active_operations -= 1;

    if (committing) {
        lib.kpanic("commit already in progress");
    }

    if (active_operations == 0) {
        lock.release();
        committing = true;
        commitToLog();
        lock.acquire();
        committing = false;
    } else {
        Process.wakeup(&@This());
    }
}

pub fn commitToLog() void {
    if (log_header.num_entries == 0) {
        return;
    }
    writeCacheToLog();
    writeHeader();
    writeLogToDisk(false);
    log_header.num_entries = 0;
    writeHeader();
}

pub fn write(buffer: *Buffer) void {
    lock.acquire();
    defer lock.release();

    if (log_header.num_entries >= fs.NUM_LOG_BLOCKS or log_header.num_entries >= size - 1) {
        lib.kpanic("outside log bounds");
    }

    if (active_operations < 1) {
        lib.kpanic("no active operations");
    }

    var i: u16 = 0;
    while (i < log_header.num_entries) : (i += 1) {
        // if already in log
        if (log_header.blocks[i] == buffer.block_num) {
            break;
        }
    }

    log_header.blocks[i] = buffer.block_num;
    if (i == log_header.num_entries) {
        BufferCache.addRef(buffer);
        log_header.num_entries += 1;
    }
}
