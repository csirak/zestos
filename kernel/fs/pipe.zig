const Spinlock = @import("../locks/spinlock.zig");

const File = @import("../fs/file.zig");
const FileTable = @import("../fs/filetable.zig");

const KMem = @import("../mem/kmem.zig");

const Process = @import("../procs/proc.zig");
const Console = @import("../io/console.zig");

pub const PIPE_SIZE = 512;

const Self = @This();

lock: Spinlock,
data: [PIPE_SIZE]u8,
read_bytes: u32,
write_bytes: u32,
read_open: bool,
write_open: bool,

pub fn alloc(read_file: **File, write_file: **File) !void {
    const read_file_ptr = FileTable.alloc();
    const write_file_ptr = FileTable.alloc();

    errdefer FileTable.free(read_file.*);
    errdefer FileTable.free(write_file.*);

    const pipe: *Self = @ptrCast(try KMem.alloc());
    errdefer KMem.free(@intFromPtr(pipe));

    pipe.read_open = true;
    pipe.write_open = true;
    pipe.read_bytes = 0;
    pipe.write_bytes = 0;

    pipe.lock = Spinlock.init("pipe");

    read_file_ptr.data = .{ .pipe = pipe };
    read_file_ptr.readable = true;
    read_file_ptr.writable = false;

    write_file_ptr.data = .{ .pipe = pipe };
    write_file_ptr.readable = false;
    write_file_ptr.writable = true;

    read_file.* = read_file_ptr;
    write_file.* = write_file_ptr;
}

pub fn close(self: *Self, writeable: bool) void {
    self.lock.acquire();
    defer self.lock.release();

    if (writeable) {
        self.write_open = false;
        Process.wakeup(&self.read_bytes);
    } else {
        self.read_open = false;
        Process.wakeup(&self.write_bytes);
    }

    if (self.read_open and self.write_open) {
        KMem.free(@intFromPtr(self));
    }
}

pub fn write(self: *Self, address: u64, size: u64) i64 {
    const proc = Process.currentOrPanic();
    self.lock.acquire();
    defer self.lock.release();

    var bytes_written: u32 = 0;

    while (bytes_written < size) {
        if (!self.read_open or proc.isKilled()) {
            return -1;
        }

        if (self.write_bytes - self.read_bytes == PIPE_SIZE) {
            Process.wakeup(&self.read_bytes);
            proc.sleep(&self.write_bytes, &self.lock);
            continue; // make sure pipe is still open
        }

        const write_byte_location = &self.data[self.write_bytes % PIPE_SIZE];
        proc.pagetable.?.copyFrom(address + bytes_written, @ptrCast(write_byte_location), 1) catch return bytes_written;
        self.write_bytes += 1;
        bytes_written += 1;
    }

    return bytes_written;
}

pub fn read(self: *Self, address: u64, size: u64) i64 {
    const proc = Process.currentOrPanic();

    self.lock.acquire();
    defer self.lock.release();

    while (self.read_bytes == self.write_bytes and self.write_open) {
        if (proc.isKilled()) {
            return -1;
        }
        proc.sleep(&self.read_bytes, &self.lock);
    }

    defer Process.wakeup(&self.write_bytes);
    for (0..size) |i| {
        if (self.read_bytes == self.write_bytes) {
            return @intCast(i);
        }

        const byte = self.data[self.read_bytes % PIPE_SIZE];
        self.read_bytes += 1;
        proc.pagetable.?.copyInto(address + i, @ptrCast(&byte), 1) catch return @intCast(i);
    }
    return @intCast(size);
}
