const fs = @import("../fs/fs.zig");
const lib = @import("../lib.zig");

pub fn bytesDump(bytes: *[]u8, row_width: comptime_int, total_bytes: comptime_int, address_offset: u64) void {
    if (total_bytes % row_width != 0) {
        lib.kpanic("Row width is not a multiple of block size\n");
    }
    logHeader(row_width);
    const row_nums = @divExact(total_bytes, row_width);
    const row_aligned_block: *const [row_nums][row_width]u8 = @ptrCast(bytes);
    for (row_aligned_block, 0..) |row, i| {
        lib.printIntHex(@intCast(address_offset + i * row_width));
        tab();
        lib.put_char('|');

        for (row) |byte| {
            lib.printByte((byte));
            space();
        }
        tab();
        lib.put_char('|');

        for (row) |byte| {
            lib.put_char(filterChar(byte));
            space();
            space();
        }
        newline();
    }
    newline();
}

pub fn blockDump(block_num: u16, block: *fs.Block, row_width: comptime_int) void {
    logBlockInfo(block_num);
    bytesDump(@alignCast(@ptrCast(block)), row_width, fs.BLOCK_SIZE, block_num * fs.BLOCK_SIZE);
}

fn filterChar(c: u8) u8 {
    if (c < 40) {
        return ' ';
    }
    return c;
}

pub fn bufferDump(inum: u16, block: *fs.Block, row_width: comptime_int) void {
    blockDump(fs.inodeBlockNum(inum), block, row_width);
}

const BlockType = enum {
    boot,
    superblock,
    log,
    inode,
    bitmap,
    data,
    unknown,
};

fn blockType(block_num: u16) BlockType {
    return switch (block_num) {
        0 => .boot,
        1 => .superblock,
        fs.SUPER_BLOCK.log_start...fs.SUPER_BLOCK.inode_start - 1 => .log,
        fs.SUPER_BLOCK.inode_start...fs.SUPER_BLOCK.bmap_start - 1 => .inode,
        fs.SUPER_BLOCK.bmap_start...fs.NUM_META_BLOCKS - 1 => .bitmap,
        fs.NUM_META_BLOCKS...fs.TOTAL_BLOCKS => .data,
        else => .unknown,
    };
}

fn logBlockInfo(block_num: u16) void {
    const block_type = blockType(block_num);
    newline();

    switch (block_type) {
        .log => lib.print("Log "),
        .inode => lib.print("Inode "),
        .bitmap => lib.print("Bitmap "),
        .data => lib.print("Data "),
        else => lib.print("Unknown "),
    }
    lib.print("Block: ");
    lib.printIntDec(@intCast(block_num));
    newline();
}

fn logHeader(row_width: comptime_int) void {
    const placeholder = "0x00000000";
    newline();

    for (placeholder) |_| {
        space();
    }
    tab();
    lib.put_char('|');

    for (0..row_width) |i| {
        lib.printByte(@intCast(i));
        lib.put_char('|');
    }

    tab();
    lib.put_char('|');

    for (0..row_width) |i| {
        lib.printByte(@intCast(i));
        lib.put_char('|');
    }

    newline();
    newline();
}

fn space() void {
    lib.put_char(' ');
}

fn tab() void {
    space();
    space();
}

fn newline() void {
    lib.put_char('\n');
}
