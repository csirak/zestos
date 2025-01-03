const fs = @import("../fs/fs.zig");
const lib = @import("../lib.zig");
const Uart = @import("../io/uart.zig");

pub fn bytesDump(bytes: [*]const u8, row_width: comptime_int, total_bytes: comptime_int, address_offset: u64) void {
    if (total_bytes % row_width != 0) {
        lib.kpanic("Row width is not a multiple of block size\n");
    }
    const addr_width = @max(numHexDigits(address_offset), numHexDigits(address_offset + total_bytes));
    // spacing
    logHeader(addr_width + 3, row_width);
    const row_nums = @divExact(total_bytes, row_width);
    const row_aligned_block: *const [row_nums][row_width]u8 = @ptrCast(bytes);
    for (row_aligned_block, 0..) |row, i| {
        const line = address_offset + i * row_width;
        const digs = numHexDigits(line);
        for (0..(addr_width - digs)) |_| {
            space();
        }

        lib.printf(" 0x{x}", .{line});

        tab();
        Uart.putc('|');

        for (row, 0..) |byte, c| {
            lib.printByte(byte);
            if (c < row.len - 1) {
                space();
            } else {
                Uart.putc('|');
            }
        }
        tab();
        Uart.putc('|');

        for (row, 0..) |byte, c| {
            Uart.putc(filterChar(byte));
            if (c < row.len - 1) {
                tab();
            } else {
                space();
                Uart.putc('|');
            }
        }
        newline();
    }
    newline();
}

pub fn blockDump(block_num: u16, block: *const fs.Block, row_width: comptime_int) void {
    const block_large: u64 = @intCast(block_num);
    bytesDump(@alignCast(@ptrCast(block)), row_width, fs.BLOCK_SIZE, block_large * fs.BLOCK_SIZE);
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
    lib.printf("{}", .{block_num});
    newline();
}

fn numHexDigits(n: u64) u8 {
    if (n == 0) return 1;
    var x = n;
    var i: u8 = 0;
    while (x > 0) : (i += 1) x >>= 4;
    return i;
}

fn logHeader(addr_width: u8, row_width: comptime_int) void {
    newline();

    for (0..addr_width) |_| {
        space();
    }
    tab();
    Uart.putc('|');

    for (0..row_width) |i| {
        lib.printByte(@intCast(i));
        Uart.putc('|');
    }

    tab();
    Uart.putc('|');

    for (0..row_width) |i| {
        lib.printByte(@intCast(i));
        Uart.putc('|');
    }

    newline();
    newline();
}

fn space() void {
    Uart.putc(' ');
}

fn tab() void {
    space();
    space();
}

fn newline() void {
    Uart.putc('\n');
}
