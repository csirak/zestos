const Sleeplock = @import("../locks/sleeplock.zig");

pub const INODE_DIR = 1;
pub const INODE_FILE = 2;
pub const INODE_DEVICE = 3;
pub const INODE_SYMLINK = 4;

pub const INode = struct {
    device: u32,
    inum: u16,
    reference_count: u16,
    sleeplock: Sleeplock,
    valid: bool,
    disk_inode: DiskINode,
};

pub const DiskINode = extern struct {
    typ: u16,
    // debug by searching bin files
    major: u16 = 0x6969,
    minor: u16 = 0,
    num_links: u16 = 1,
    size: u32 = 0,
    direct: [DIRECT_ADDRESS_SIZE + 1]u32 = [_]u32{0} ** (DIRECT_ADDRESS_SIZE + 1),
};

pub const DirEntry = extern struct {
    inum: u16,
    name: [DIR_NAME_SIZE]u8,
};

pub const SuperBlock = extern struct {
    magic: u32,
    size: u32,
    num_blocks: u32,
    num_inodes: u32,
    num_log_blocks: u32,
    log_start: u32,
    inode_start: u32,
    bmap_start: u32,
};

pub const IndirectAddressBlock = [INDIRECT_ADDRESS_SIZE]u32;

pub const Block = [BLOCK_SIZE]u8;

pub const MAGIC = 0x10203040;
pub const TOTAL_BLOCKS = 2000;
pub const INODES_NUM = 200;
pub const ROOT_INODE = 1;
pub const BLOCK_SIZE = 1024;
pub const DIR_NAME_SIZE = 14;
pub const BITS_PER_BLOCK = 8 * BLOCK_SIZE;
pub const MAX_BLOCKS_PER_OP = 10;
pub const NUM_LOG_BLOCKS = 3 * MAX_BLOCKS_PER_OP;
pub const BUFFER_CACHE_SIZE = 3 * MAX_BLOCKS_PER_OP;

pub const DIRECT_ADDRESS_SIZE = 12;
pub const INDIRECT_ADDRESS_SIZE = @divExact(BLOCK_SIZE, @sizeOf(u32));
pub const MAX_ADDRESS_SIZE = DIRECT_ADDRESS_SIZE + INDIRECT_ADDRESS_SIZE;

pub const SUPER_BLOCK_INDEX = 1;
pub const BOOT_AND_SUPER_BLOCK_OFFSET = 2;

pub const INODES_PER_BLOCK = @divExact(BLOCK_SIZE, @sizeOf(DiskINode));
pub const NUM_BITMAP_BLOCKS = @divFloor(TOTAL_BLOCKS, BITS_PER_BLOCK) + 1;
pub const NUM_INODE_BLOCKS = @divFloor(INODES_NUM, INODES_PER_BLOCK) + 1;
pub const NUM_META_BLOCKS = 2 + NUM_LOG_BLOCKS + NUM_INODE_BLOCKS + NUM_BITMAP_BLOCKS;
pub const NUM_DATA_BLOCKS = TOTAL_BLOCKS - NUM_META_BLOCKS;

pub const NUM_FILES = 100; // open files per system
pub const MAX_OPEN_FILES = 16; // open files per process
pub const NUM_INODES = 50; // maximum number of active i-nodes
pub const NUM_DEVICES = 10; // maximum major device number
pub const ROOT_DEVICE = 1; // device number of file system root disk

pub const SUPER_BLOCK: SuperBlock = .{
    .magic = MAGIC,
    .size = TOTAL_BLOCKS,
    .num_blocks = NUM_DATA_BLOCKS,
    .num_inodes = INODES_NUM,
    .num_log_blocks = NUM_LOG_BLOCKS,
    .log_start = BOOT_AND_SUPER_BLOCK_OFFSET,
    .inode_start = BOOT_AND_SUPER_BLOCK_OFFSET + NUM_LOG_BLOCKS,
    .bmap_start = BOOT_AND_SUPER_BLOCK_OFFSET + NUM_LOG_BLOCKS + NUM_INODE_BLOCKS,
};

pub inline fn inodeBlockNum(inum: u16) u16 {
    return @intCast((@divFloor(inum, INODES_PER_BLOCK)) + SUPER_BLOCK.inode_start);
}

pub inline fn bitMapBlockNum(block_num: u16) u16 {
    return @intCast((@divFloor(block_num, BITS_PER_BLOCK)) + SUPER_BLOCK.bmap_start);
}

pub inline fn dirEntry(inum: u16, name: []const u8) DirEntry {
    var dir = DirEntry{
        .inum = inum,
        .name = [_]u8{0} ** DIR_NAME_SIZE,
    };

    strCopy(dir.name[0..], name, DIR_NAME_SIZE);
    return dir;
}

fn strCopy(dst: []u8, src: []const u8, size: u64) void {
    const len = @min(src.len, size);
    for (0..len) |i| {
        dst[i] = src[i];
    }
}
