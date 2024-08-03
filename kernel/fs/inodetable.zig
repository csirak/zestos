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
    for (&inodes) |*inode| {
        inode.sleep_lock = Sleeplock.init("inode table");
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
    var rest = getNextPathElem(path, name);
    if (rest.?[0] == 0) {
        return current;
    }
    while (rest != null) : (rest = getNextPathElem(rest.?, name)) {
        current.lock();
        defer current.release();
        if (current.disk_inode.typ != .Directory) {
            removeRef(current);
            return error.NotDirectory;
        }
        if (get_parent and rest.?[0] == 0) {
            return current;
        }

        current = dirLookUp(current, name, null) orelse return error.NotFound;
    }

    if (get_parent) {
        removeRef(current);
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

fn getNextPathElem(path: [*:0]const u8, name: [*:0]u8) ?[*:0]const u8 {
    var i: usize = 0;
    while (path[i] == '/') : (i += 1) {
        if (path[i] == 0) {
            return null;
        }
    }

    const start = i;

    while (path[i] != '/' and path[i] != 0) {
        i += 1;
    }

    const size = if (i - start > fs.DIR_NAME_SIZE) fs.DIR_NAME_SIZE else i - start;
    @memcpy(name[0..size], path[start..(start + size)]);

    return path[i..];
}

fn dirLookUp(dir: *INode, name: [*:0]const u8, put_offset: ?*u16) ?*INode {
    if (dir.disk_inode.typ != .Directory) {
        return null;
    }
    var offset: u64 = 0;
    var entry: fs.DirEntry = undefined;

    while (offset < dir.disk_inode.size) : (offset += @sizeOf(fs.DirEntry)) {
        _ = dir.readToAddress(@intFromPtr(&entry), offset, @sizeOf(fs.DirEntry), false) catch return null;
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
