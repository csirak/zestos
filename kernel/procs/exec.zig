const elf = @import("../fs/elf.zig");

const Process = @import("proc.zig");
const Log = @import("../fs/log.zig");
const INodeTable = @import("../fs/inodetable.zig");

pub fn exec(path: [*:0]const u8, _: [*:0][*:0]const u8) !void {
    // const process = Process.currentOrPanic();

    Log.beginTx();
    defer Log.endTx();

    const inode = try INodeTable.namedInode(path);
    inode.lock();
    defer inode.unlock();

    var elf_header: elf.ElfHeader = undefined;

    _ = try inode.readToAddress(@intFromPtr(&elf_header), 0, @sizeOf(elf.ElfHeader), false);
}
