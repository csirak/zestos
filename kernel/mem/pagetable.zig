const riscv = @import("../riscv.zig");
const mem = @import("mem.zig");
const KMem = @import("kmem.zig");
const lib = @import("../lib.zig");

const PAGETABLE_SIZE = riscv.PGSIZE / @sizeOf(u64);
// 9 bit mask
const PX_MASK = 0x1ff;
const PTE_FLAGS_MASK = 0x3ff;
const PG_OFFSET_SIZE = 12;
const PT_INDEX_SIZE = 9;
const PTE_FLAGS_SIZE = 10;

const Table = *[PAGETABLE_SIZE]u64;

const Self = @This();
table: Table,

pub fn init() !Self {
    return Self{
        .table = makeTable() catch |e| return e,
    };
}

pub fn userFree(self: *Self, size: u64) !void {
    try self.unMapPages(riscv.TRAMPOLINE, 1, false);
    try self.unMapPages(riscv.TRAPFRAME, 1, false);
    if (size > 0) {
        try self.unMapPages(0, mem.pageAlignUp(size), true);
    }
    try freeTable(self.table);
}

pub fn getPhysAddrFromVa(self: *Self, virtual_address: u64, alloc: bool) !*u64 {
    if (virtual_address > riscv.MAXVA) {
        lib.kpanic("va overflow");
    }
    var cur_pagetable = self.table;
    for (0..2) |offset| {
        const level = 2 - offset;
        const pte = &cur_pagetable[pageTableLevelIndex(virtual_address, @intCast(level))];

        if (pte.* & mem.PTE_V != 0) {
            cur_pagetable = @ptrCast(pageTableEntryToPhysAddr(pte.*));
        } else if (alloc) {
            const table = try makeTable();
            pte.* = physAddrToPTE(&table[0]) | mem.PTE_V;
            cur_pagetable = table;
        } else {
            return error.PageTableLevelNotDeepEnough;
        }
    }
    return &cur_pagetable[pageTableLevelIndex(virtual_address, 0)];
}

pub fn mapPages(self: *Self, virtual_address: u64, physical_address: u64, size: u64, flags: u16) !void {
    const virtual_address_page_aligned = mem.pageAlignDown(virtual_address);

    var page_offset: u64 = 0;
    const last_page = mem.pageAlignDown(virtual_address + size - 1);

    if ((last_page - virtual_address_page_aligned) % riscv.PGSIZE != 0) {
        lib.kpanic("not page align");
    }

    while (virtual_address_page_aligned + page_offset <= last_page) : (page_offset += riscv.PGSIZE) {
        const pte = try self.getPhysAddrFromVa(virtual_address_page_aligned + page_offset, true);
        if (pte.* & mem.PTE_V != 0) {
            return error.MappedPageAlreadyAllocated;
        }
        pte.* = physAddrToPTE(@ptrFromInt(physical_address + page_offset)) | flags | mem.PTE_V;
    }
}

pub fn unMapPages(self: *Self, virtual_address: u64, num_pages: u64, freePages: bool) !void {
    if (virtual_address % riscv.PGSIZE != 0) {
        return error.NotPageAligned;
    }

    var cur_virtual_address = virtual_address;

    while (cur_virtual_address <= virtual_address + num_pages * riscv.PGSIZE) : (cur_virtual_address += riscv.PGSIZE) {
        const pte = try self.getPhysAddrFromVa(cur_virtual_address, false);
        if (pte.* & mem.PTE_V == 0) {
            return error.PageNotMapped;
        }
        if (pageTableEntryFlags(pte.*) == mem.PTE_V) {
            return error.NotPageTableLeaf;
        }
        if (freePages) {
            KMem.free(@intFromPtr(pageTableEntryToPhysAddr(pte.*)));
        }
        pte.* = 0;
    }
}

pub inline fn setSatp(self: *Self) void {
    riscv.w_satp(self.getAsSatp());
}

pub inline fn getAsSatp(self: *Self) u64 {
    return mem.MAKE_SATP(@intFromPtr(self.table));
}

inline fn pageTableLevelIndex(address: u64, level: u6) u64 {
    const shift_depth: u6 = PT_INDEX_SIZE * level + PG_OFFSET_SIZE;
    return (address >> shift_depth) & PX_MASK;
}

inline fn pageTableEntryToPhysAddr(pte: u64) *u64 {
    return @ptrFromInt((pte >> PTE_FLAGS_SIZE) << PG_OFFSET_SIZE);
}

inline fn pageTableEntryFlags(pte: u64) u64 {
    return pte & PTE_FLAGS_MASK;
}

inline fn physAddrToPTE(address: *u64) u64 {
    const pa = @intFromPtr(address);
    return (pa >> PG_OFFSET_SIZE) << PTE_FLAGS_SIZE;
}

fn makeTable() !Table {
    const table: Table = @ptrCast(try KMem.alloc());
    @memset(table, 0);
    return table;
}

fn freeTable(table: Table) !void {
    for (0..PAGETABLE_SIZE) |i| {
        const pte = table[i];
        // is parent node?
        if ((pte & mem.PTE_V) != 0 and (pte & (mem.PTE_R | mem.PTE_W | mem.PTE_X) == 0)) {
            const child = pageTableEntryToPhysAddr(pte);
            try freeTable(@ptrCast(child));
            table[i] = 0;
        } else if (pte & mem.PTE_V != 0) {
            return error.NotFreedLeafNodesExist;
        }
    }

    KMem.free(@intFromPtr(table));
}
