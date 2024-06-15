const riscv = @import("../riscv.zig");
const mem = @import("mem.zig");
const KMem = @import("kmem.zig");
const lib = @import("../lib.zig");

const PAGETABLE_SIZE = riscv.PGSIZE / @sizeOf(u64);
// 9 bit mask
const PX_MASK = 0x1ff;
const PG_OFFSET_SIZE = 12;
const PT_INDEX_SIZE = 9;
const PTE_FLAGS_SIZE = 10;

const Table = *[PAGETABLE_SIZE]u64;

const Self = @This();
table: Table,

pub fn init() Self {
    return Self{
        .table = makeTable() catch unreachable,
    };
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
            const table = makeTable() catch |e| return e;
            pte.* = physAddrToPTE(&table[0]) | mem.PTE_V;
            cur_pagetable = table;
        } else {
            return error.NoAllocation;
        }
    }
    return &cur_pagetable[pageTableLevelIndex(virtual_address, 0)];
}

pub fn setSatp(self: *Self) void {
    riscv.w_satp(mem.MAKE_SATP(@intFromPtr(self.table)));
}

pub fn mapPages(self: *Self, virtual_address: u64, physical_address: u64, size: u64, flags: u16) !void {
    var cur_page = mem.pageAlignDown(virtual_address);
    var cur_physical_address = physical_address;
    const last_page = mem.pageAlignDown(virtual_address + size - 1);

    if ((last_page - cur_page) % riscv.PGSIZE != 0) {
        lib.kpanic("not page align");
    }

    while (cur_page <= last_page) {
        const pte = self.getPhysAddrFromVa(cur_page, true) catch |e| return e;
        if (pte.* & mem.PTE_V != 0) {
            return error.MappedPageAlreadyAllocated;
        }
        pte.* = physAddrToPTE(@ptrFromInt(cur_physical_address)) | flags | mem.PTE_V;
        cur_page += riscv.PGSIZE;
        cur_physical_address += riscv.PGSIZE;
    }
}

inline fn pageTableLevelIndex(address: u64, level: u6) u64 {
    const shift_depth: u6 = PT_INDEX_SIZE * level + PG_OFFSET_SIZE;
    return (address >> shift_depth) & PX_MASK;
}

inline fn pageTableEntryToPhysAddr(pte: u64) *u64 {
    return @ptrFromInt((pte >> PTE_FLAGS_SIZE) << PG_OFFSET_SIZE);
}

inline fn physAddrToPTE(address: *u64) u64 {
    const pa = @intFromPtr(address);
    return (pa >> PG_OFFSET_SIZE) << PTE_FLAGS_SIZE;
}
fn makeTable() !Table {
    const page = KMem.alloc() catch |e| return e;
    const table: Table = @ptrCast(page);
    @memset(table, 0);
    return table;
}
