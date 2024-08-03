const mem = @import("mem.zig");

const riscv = @import("../riscv.zig");
const lib = @import("../lib.zig");

const PageTable = @import("PageTable.zig");
const Spinlock = @import("../locks/spinlock.zig");

const run = struct {
    next: ?*run,
};

extern var end: u64;

const Self = @This();

var lock: Spinlock = undefined;
var freed: ?*run = undefined;

var pagetable: PageTable = undefined;

pub fn init() void {
    lock = Spinlock.init("KMem");
    freed = @ptrFromInt(riscv.PHYSTOP);
    freeRange(@intFromPtr(&end), riscv.PHYSTOP);
    pagetable = PageTable.init();
}

pub fn freeRange(pa_start: u64, pa_end: u64) void {
    var page = mem.pageAlignUp(pa_start);
    while (page + riscv.PGSIZE <= pa_end) : (page += riscv.PGSIZE) {
        free(page);
    }
}

pub fn alloc() !*u64 {
    lock.acquire();
    const p = freed orelse undefined;
    if (p == undefined) {
        return error.MemoryUnavailable;
    }
    freed = p.*.next;
    lock.release();
    const page: *[riscv.PGSIZE]u8 = @ptrCast(p);
    @memset(page, 5);
    return @ptrCast(p);
}

pub fn free(pa: u64) void {
    const p: *run = @ptrFromInt(pa);
    p.*.next = freed;
    freed = p;
}

pub fn printFreed() void {
    var p: ?*run = freed;
    while (p) |next| {
        lib.printInt(@intFromPtr(next));
        p = next.*.next;
    }
}

pub fn mapPages(virtual_address: u64, size: u64, physical_address: u64, flags: u16) !void {
    pagetable.mapPages(virtual_address, size, physical_address, flags) catch |e| {
        lib.println("kernel map pages");
        lib.kpanic(@errorName(e));
    };
}
