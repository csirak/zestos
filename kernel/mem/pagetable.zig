const riscv = @import("../riscv.zig");
const mem = @import("mem.zig");
const KMem = @import("kmem.zig");
const lib = @import("../lib.zig");

const PAGETABLE_SIZE = @divExact(riscv.PGSIZE, @sizeOf(u64));
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
        const num_pages = @divExact(mem.pageAlignUp(size), riscv.PGSIZE);
        try self.unMapPages(0, num_pages, true);
    }
    try freeTable(self.table);
}

pub fn getPageTableEntry(self: *Self, virtual_address: u64, alloc: bool) !*u64 {
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

    const last_page = mem.pageAlignDown(virtual_address + size - 1);

    if ((last_page - virtual_address_page_aligned) % riscv.PGSIZE != 0) {
        lib.kpanic("not page align");
    }

    var va = virtual_address_page_aligned;
    var pa = physical_address;
    while (va <= last_page) {
        const pte = try self.getPageTableEntry(va, true);
        if (pte.* & mem.PTE_V != 0) {
            return error.MappedPageAlreadyAllocated;
        }
        pte.* = physAddrToPTE(@ptrFromInt(pa)) | flags | mem.PTE_V;
        va += riscv.PGSIZE;
        pa += riscv.PGSIZE;
    }
}

pub fn unMapPages(self: *Self, virtual_address: u64, num_pages: u64, freePages: bool) !void {
    if (virtual_address % riscv.PGSIZE != 0) {
        return error.NotPageAligned;
    }

    var cur_virtual_address = virtual_address;

    while (cur_virtual_address < virtual_address + num_pages * riscv.PGSIZE) : (cur_virtual_address += riscv.PGSIZE) {
        const pte = try self.getPageTableEntry(cur_virtual_address, false);
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

pub fn copy(self: *Self, dest: *Self, size: u64) !void {
    var i: u64 = 0;
    while (i < size) : (i += riscv.PGSIZE) {
        const pte = try self.getPageTableEntry(i, false);
        if (pte.* & mem.PTE_V != 0) {
            lib.kpanic("page table entry is not valid\n");
        }

        const phys_address_page: Table = @ptrCast(pageTableEntryToPhysAddr(pte.*));
        const flags = pageTableEntryFlags(pte.*);
        const page: Table = @ptrCast(try KMem.alloc());

        @memcpy(page, phys_address_page);
        try dest.mapPages(i, @intFromPtr(page), riscv.PGSIZE, @intCast(flags));
    }
}

pub fn userAlloc(self: *Self, old_size: u64, new_size: u64, flags: u16) !u64 {
    if (new_size < old_size) {
        return new_size;
    }

    var aligned_cur_virtual_address = mem.pageAlignDown(old_size);

    while (aligned_cur_virtual_address < new_size) : (aligned_cur_virtual_address += riscv.PGSIZE) {
        const page = KMem.allocZeroed() catch |e| {
            _ = try self.userDeAlloc(aligned_cur_virtual_address, old_size);
            return e;
        };

        self.mapPages(aligned_cur_virtual_address, @intFromPtr(page), riscv.PGSIZE, mem.PTE_R | mem.PTE_U | flags) catch |e| {
            KMem.free(@intFromPtr(page));
            _ = try self.userDeAlloc(aligned_cur_virtual_address, old_size);
            return e;
        };
    }
    return new_size;
}

pub fn revokeUserPage(self: *Self, virtual_address: u64) !void {
    const pte = try self.getPageTableEntry(virtual_address, false);
    pte.* &= ~(mem.PTE_U);
}

pub fn userDeAlloc(self: *Self, old_size: u64, new_size: u64) !u64 {
    if (new_size >= old_size) {
        return new_size;
    }

    const new_page_aligned_addr = mem.pageAlignUp(new_size);
    const num_pages = @divExact((mem.pageAlignUp(old_size) - new_page_aligned_addr), riscv.PGSIZE);
    if (num_pages == 0) {
        return new_size;
    }

    try self.unMapPages(new_page_aligned_addr, num_pages, true);
    return new_size;
}

pub fn copyInto(self: *Self, dest: u64, src: *[]u8, size: u64) !void {
    lib.kpanic("not Implemented copyInto");

    _ = self;
    _ = dest;
    _ = src;
    _ = size;
    // var bytes_left = size;
    // var cur_dest_addr = dest;
    // while (bytes_left > 0) {
    //     const virtual_address = mem.pageAlignDown(cur_dest_addr);
    //     const kernel_mem_addr = self.getPhysAddrFromVa(virtual_address);
    // }
}

pub fn getUserPhysAddrFromVa(self: *Self, virtual_address: u64) !*u64 {
    if (virtual_address > riscv.MAXVA) {
        return error.VirtualAddressOutOfBounds;
    }
    const pte = try self.getPageTableEntry(virtual_address, false);
    if (pte.* == 0) {
        return error.PageNotMapped;
    }
    if (pte.* & mem.PTE_V == 0) {
        return error.PageTableEntryNotValid;
    }
    if (pte.* & mem.PTE_U == 0) {
        return error.PageTableEntryNotUser;
    }
    return pageTableEntryToPhysAddr(pte.*);
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

pub inline fn pageTableEntryToPhysAddr(pte: u64) *u64 {
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
    const table: Table = @ptrCast(try KMem.allocZeroed());
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
