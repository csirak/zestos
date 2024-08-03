const elf = @import("../fs/elf.zig");
const riscv = @import("../riscv.zig");
const lib = @import("../lib.zig");

const mem = @import("../mem/mem.zig");

const Process = @import("proc.zig");
const INode = @import("../fs/inode.zig");

const Pagetable = @import("../mem/pagetable.zig");
const Log = @import("../fs/log.zig");
const INodeTable = @import("../fs/inodetable.zig");

pub fn exec(path: [*:0]u8) !void {
    Log.beginTx();
    defer Log.endTx();

    const inode = try INodeTable.getNamedInode(path);
    inode.lock();
    defer inode.release();

    var elf_header: elf.ElfHeader = undefined;

    const read_size = try inode.readToAddress(@intFromPtr(&elf_header), 0, @sizeOf(elf.ElfHeader), false);

    if (read_size != @sizeOf(elf.ElfHeader)) {
        return error.InvalidElfHeader;
    }

    if (elf_header.magic != elf.MAGIC) {
        return error.InvalidElfHeader;
    }

    var cur_program_header: usize = 0;
    var user_space_size: u64 = 0;

    const proc = Process.currentOrPanic();

    const old_mem_size = proc.mem_size;
    var pagetable = try proc.getTrapFrameMappedPageTable();

    // TODO: Make sure this var is value is not copied directly
    errdefer pagetable.userFree(user_space_size) catch unreachable;

    while (cur_program_header < elf_header.program_header_count) : (cur_program_header += 1) {
        var program_header: elf.ProgramHeader = undefined;
        const cur_program_header_file_offset = elf_header.program_header_offset + cur_program_header * @sizeOf(elf.ProgramHeader);
        const ph_read_size = try inode.readToAddress(@intFromPtr(&program_header), cur_program_header_file_offset, @sizeOf(elf.ProgramHeader), false);
        if (ph_read_size != @sizeOf(elf.ProgramHeader)) {
            return error.InvalidElfProgramHeader;
        }
        if (program_header.typ != .LOAD) {
            continue;
        }
        if (program_header.memory_size < program_header.file_size) {
            return error.InvalidElfProgramHeaderMemoryToSmall;
        }
        if (program_header.memory_size + program_header.virtual_addr < program_header.virtual_addr) {
            return error.ProgramHeaderVirtualAddressOverflow;
        }
        if (program_header.virtual_addr % riscv.PGSIZE != 0) {
            return error.ProgramHeaderVirtualAddressNotAligned;
        }

        const flags = programHeaderFlagsToPagetableFlags(program_header.flags);
        user_space_size = try pagetable.userAlloc(user_space_size, program_header.virtual_addr + program_header.memory_size, flags);
        try loadSegment(&pagetable, program_header.virtual_addr, inode, program_header.offset, program_header.file_size);
    }

    // TODO: check page alignment
    const page_aligned_size = mem.pageAlignUp(user_space_size);
    const stack_top = page_aligned_size + 2 * riscv.PGSIZE;
    proc.mem_size = try pagetable.userAlloc(user_space_size, stack_top, mem.PTE_W);

    // add guard page before top
    try pagetable.revokeUserPage(page_aligned_size);

    // const stack_base = stack_top - riscv.PGSIZE;
    var last_back_slash: u16 = 0;
    var i: u16 = 0;
    while (path[i] != 0) : (i += 1) {
        if (path[i] == '/') {
            last_back_slash = i;
        }
    }

    lib.strCopyNullTerm(&proc.name, path[last_back_slash + 1 ..], Process.NAME_SIZE);

    var old_pagetable = proc.pagetable.?;
    proc.pagetable = pagetable;
    proc.mem_size = stack_top;
    proc.trapframe.?.epc = elf_header.entry;
    proc.trapframe.?.sp = stack_top;

    try old_pagetable.userFree(old_mem_size);
    // TODO: set up stack
}

inline fn programHeaderFlagsToPagetableFlags(flags: elf.ProgramHeaderFlag) u16 {
    var perm: u16 = 0;
    const int_flags = @intFromEnum(flags);
    if (int_flags & 0x1 != 0)
        perm = mem.PTE_X;
    if (int_flags & 0x2 != 0)
        perm |= mem.PTE_W;
    return perm;
}

fn loadSegment(pagetable: *Pagetable, virtual_addr: u64, inode: *INode, file_offset: u64, size: u64) !void {
    var cur_offset: u64 = 0;

    while (cur_offset < size) : (cur_offset += riscv.PGSIZE) {
        const page = try pagetable.getUserPhysAddrFromVa(virtual_addr + cur_offset);
        const page_offset: u64 = @intFromPtr(page) + virtual_addr % riscv.PGSIZE;
        const bytes_to_read = if (size - cur_offset < riscv.PGSIZE) size - cur_offset else riscv.PGSIZE;
        const bytes_read = try inode.readToAddress(page_offset, file_offset + cur_offset, bytes_to_read, false);
        if (bytes_read != bytes_to_read) {
            return error.InodeReadError;
        }
    }
}
