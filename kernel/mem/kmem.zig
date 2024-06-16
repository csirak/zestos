const mem = @import("mem.zig");
const PageTable = @import("PageTable.zig");

const riscv = @import("../riscv.zig");
const lib = @import("../lib.zig");

const Procedure = @import("../procs/proc.zig");
const Spinlock = @import("../locks/spinlock.zig");

const AddressNode = struct {
    next: ?*AddressNode,
};

extern fn end() void;
extern fn kernelend() void;
extern fn trampoline() void;

var lock: Spinlock = undefined;
var freed: ?*AddressNode = undefined;
var pagetable: PageTable = undefined;

pub fn init() void {
    const kernel_code_end_addr = @intFromPtr(&kernelend);
    const trampoline_addr = @intFromPtr(&trampoline);
    const kernel_end_addr = @intFromPtr(&end);

    lock = Spinlock.init("KMem");
    freed = @ptrFromInt(riscv.PHYSTOP);
    freeRange(kernel_end_addr, riscv.PHYSTOP);
    pagetable = PageTable.init() catch unreachable;

    mapKernelPages(riscv.UART0, riscv.UART0, riscv.PGSIZE, mem.PTE_R | mem.PTE_W) catch unreachable;
    mapKernelPages(riscv.VIRTIO0, riscv.VIRTIO0, riscv.PGSIZE, mem.PTE_R | mem.PTE_W) catch unreachable;
    mapKernelPages(riscv.PLIC, riscv.PLIC, riscv.PLIC_SIZE, mem.PTE_R | mem.PTE_W) catch unreachable;
    mapKernelPages(riscv.KERNBASE, riscv.KERNBASE, kernel_code_end_addr - riscv.KERNBASE, mem.PTE_R | mem.PTE_X) catch unreachable;
    mapKernelPages(kernel_code_end_addr, kernel_code_end_addr, riscv.PHYSTOP - kernel_code_end_addr, mem.PTE_R | mem.PTE_W) catch unreachable;
    mapKernelPages(riscv.TRAMPOLINE, trampoline_addr, riscv.PGSIZE, mem.PTE_R | mem.PTE_X) catch unreachable;

    mapProcedureKernelStacks() catch unreachable;
}

pub fn coreInit() void {
    riscv.flush_tlb();
    pagetable.setSatp();
    riscv.flush_tlb();
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
    const p: *AddressNode = @ptrFromInt(pa);
    p.*.next = freed;
    freed = p;
}

pub fn printFreed() void {
    var p: ?*AddressNode = freed;
    while (p) |next| {
        lib.printInt(@intFromPtr(next));
        p = next.*.next;
    }
}

fn mapKernelPages(virtual_address: u64, physical_address: u64, size: u64, flags: u16) !void {
    try pagetable.mapPages(virtual_address, physical_address, size, flags);
}

fn mapProcedureKernelStacks() !void {
    for (0..riscv.MAX_PROCS) |i| {
        const page = try alloc();
        const virtual_address = riscv.KSTACK(i);
        try mapKernelPages(virtual_address, @intFromPtr(page), riscv.PGSIZE, mem.PTE_R | mem.PTE_W);
    }
}
