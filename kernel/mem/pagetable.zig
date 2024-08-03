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

const PTE_V = (1 << 0);
const PTE_R = (1 << 1);
const PTE_W = (1 << 2);
const PTE_X = (1 << 3);
const PTE_U = (1 << 4);

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

const Table = *[PAGETABLE_SIZE]u64;

fn makeTable() !Table {
    const page = KMem.alloc() catch |e| return e;
    const table: Table = @ptrCast(page);
    @memset(table, 0);
    return table;
}

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

        if (pte.* & PTE_V != 0) {
            cur_pagetable = @ptrCast(pageTableEntryToPhysAddr(pte.*));
        } else if (alloc) {
            const table = makeTable() catch |e| return e;
            pte.* = physAddrToPTE(&table[0]) | PTE_V;
            cur_pagetable = table;
        } else {
            return error.NoAllocation;
        }
    }
    return &cur_pagetable[pageTableLevelIndex(virtual_address, 0)];
}

pub fn mapPages(self: *Self, virtual_address: u64, size: u64, physical_address: u64, flags: u16) !void {
    var cur_page = mem.pageAlignDown(virtual_address);
    const last_page = mem.pageAlignDown(virtual_address + size - 1);

    if ((last_page - cur_page) % riscv.PGSIZE != 0) {
        lib.kpanic("not page align");
    }

    while (cur_page <= last_page) {
        const pte = self.getPhysAddrFromVa(cur_page, true) catch |e| return e;
        if (pte.* & PTE_V != 0) {
            return error.MappedPageAlreadyAllocated;
        }
        pte.* = physAddrToPTE(physical_address) | flags | PTE_V;
        cur_page += riscv.PGSIZE;
        physical_address += riscv.PGSIZE;
    }
}
