const mem = @import("mem.zig");
usingnamespace mem;

const riscv = @import("../riscv.zig");
const lib = @import("../lib.zig");

const PageTable = @import("PageTable.zig");
const Spinlock = @import("../locks/spinlock.zig");

const run = struct {
    next: ?*run,
};

extern const end: u64;
extern const etext: u64;
extern const trampoline: u64;

var lock: Spinlock = undefined;
var freed: ?*run = undefined;

var pagetable: PageTable = undefined;

pub fn init() void {
    lock = Spinlock.init("KMem");
    freed = @ptrFromInt(riscv.PHYSTOP);
    freeRange(@intFromPtr(&end), riscv.PHYSTOP);
    pagetable = PageTable.init();
    lib.printInt(etext - riscv.KERNBASE);
    lib.printInt(end);
    lib.printInt(trampoline);

    mapPages(riscv.UART0, riscv.UART0, riscv.PGSIZE, mem.PTE_R | mem.PTE_W) catch unreachable;
    mapPages(riscv.VIRTIO0, riscv.VIRTIO0, riscv.PGSIZE, mem.PTE_R | mem.PTE_W) catch unreachable;
    mapPages(riscv.PLIC, riscv.PLIC, riscv.PLIC_SIZE, mem.PTE_R | mem.PTE_W) catch unreachable;
    mapPages(riscv.KERNBASE, riscv.KERNBASE, etext - riscv.KERNBASE, mem.PTE_R | mem.PTE_W) catch unreachable;
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

pub fn mapPages(virtual_address: u64, physical_address: u64, size: u64, flags: u16) !void {
    pagetable.mapPages(virtual_address, physical_address, size, flags) catch |e| {
        lib.println("kernel map pages");
        lib.kpanic(@errorName(e));
    };
}
