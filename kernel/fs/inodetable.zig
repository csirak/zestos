const fs = @import("fs.zig");
const lib = @import("../lib.zig");

const Process = @import("../procs/proc.zig");
const BufferCache = @import("../fs/buffercache.zig");
const Spinlock = @import("../locks/spinlock.zig");
const Sleeplock = @import("../locks/sleeplock.zig");
const INode = @import("inode.zig");

var lock: Spinlock = undefined;
var inodes: [fs.NUM_INODES]INode = undefined;

pub fn init() void {
    lock = Spinlock.init("inode table");
    for (&inodes, 0..) |*inode, i| {
        inode.sleeplock = Sleeplock.initId("inode", @intCast(i));
    }
}

pub fn get(device: u16, inum: u16) *INode {
    lock.acquire();
    defer lock.release();

    for (&inodes) |*inode| {
        if (inode.device == device and inode.inum == inum) {
            inode.reference_count += 1;
            return inode;
        }
    }

    // If we're here, we didn't find a matching inode. Let's find an empty one.
    for (&inodes) |*inode| {
        if (inode.reference_count == 0) {
            inode.reference_count = 1;
            inode.device = device;
            inode.inum = inum;
            inode.valid = false;
            return inode;
        }
    }

    lib.kpanic("No empty inode");
}

pub fn getWithPath(path: [*:0]const u8, get_parent: bool, name: [*:0]u8) !*INode {
    var current = if (path[0] == '/') get(fs.ROOT_DEVICE, fs.ROOT_INODE) else duplicate(Process.currentOrPanic().cwd);
    if (path[0] == '/' and path[1] == 0) {
        current.release();
        return current;
    }
    var rest: u16 = getNextPathElem(path, name, 0);
    while (rest < fs.DIR_NAME_SIZE) {
        current.lock();
        if (current.disk_inode.typ != fs.INODE_DIR) {
            removeRef(current);
            current.release();
            return error.NotDirectory;
        }

        if (get_parent and rest == 0xFFFF) {
            return current;
        }
        const new_inode = dirLookUp(current, name, null) orelse {
            removeRef(current);
            current.release();
            return error.NotFound1;
        };

        current.release();
        current = new_inode;
        if (path[rest] == 0) {
            break;
        }
        rest = getNextPathElem(path[rest..], name, rest);
    }

    if (get_parent) {
        removeRef(current);
        current.release();
        return error.NotFound;
    }
    return current;
}

pub fn namedInode(path: [*:0]const u8) !*INode {
    var name: [fs.DIR_NAME_SIZE:0]u8 = undefined;
    return try getWithPath(path, false, &name);
}

pub fn duplicate(inode: *INode) *INode {
    lock.acquire();
    defer lock.release();
    inode.reference_count += 1;
    return inode;
}

pub fn removeRef(inode: *INode) void {
    lock.acquire();
    defer lock.release();
    inode.reference_count -= 1;
}

fn getNextPathElem(path: [*:0]const u8, name: [*:0]u8, cur_offset: u16) u16 {
    var i: u16 = cur_offset;
    while (path[i] == '/') : (i += 1) {}

    if (path[i] == 0) {
        return 0xFFFF;
    }

    const start = i;

    while (path[i] != '/' and path[i] != 0) {
        i += 1;
    }

    const size = if (i - start > fs.DIR_NAME_SIZE) fs.DIR_NAME_SIZE else i - start;
    @memcpy(name[0..size], path[start..(start + size)]);
    name[size] = 0;
    return i;
}

fn dirLookUp(dir: *INode, name: [*:0]const u8, put_offset: ?*u16) ?*INode {
    if (dir.disk_inode.typ != fs.INODE_DIR) {
        return null;
    }
    var offset: u64 = 0;
    var entry: fs.DirEntry = undefined;

    while (offset < dir.disk_inode.size) : (offset += @sizeOf(fs.DirEntry)) {
        _ = dir.readToAddress(@intFromPtr(&entry), offset, @sizeOf(fs.DirEntry), false) catch |e| {
            lib.printErr(e);
            return null;
        };
        if (entry.inum == 0) {
            continue;
        }

        if (lib.strEq(&entry.name, name, fs.DIR_NAME_SIZE)) {
            if (put_offset) |po| {
                po.* = @intCast(offset);
            }
            return get(dir.device, entry.inum);
        }
    }
    return null;
}
