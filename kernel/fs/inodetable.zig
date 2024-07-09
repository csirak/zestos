const fs = @import("fs.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");

const Process = @import("../procs/proc.zig");
const BufferCache = @import("../fs/buffercache.zig");
const Spinlock = @import("../locks/spinlock.zig");
const Sleeplock = @import("../locks/sleeplock.zig");
const Log = @import("../fs/log.zig");
const INode = @import("inode.zig");

const DOT = ".";
const DOTDOT = "..";

var lock: Spinlock = undefined;
var inodes: [fs.NUM_INODES]INode = undefined;

pub fn init() void {
    lock = Spinlock.init("inode table");
    for (&inodes, 0..) |*inode, i| {
        inode.sleeplock = Sleeplock.initId("inode", @intCast(i));
    }
}

pub fn create(path: [*]u8, typ: u16, major: u16, minor: u16) !*INode {
    var name: [fs.DIR_NAME_SIZE]u8 = undefined;
    const parent = getWithPath(@ptrCast(path), true, @ptrCast(&name)) catch |e| {
        lib.printErr(e);
        return error.ParentDirDoesntExist;
    };
    parent.lock();

    if (dirLookUp(parent, @ptrCast(&name), null)) |target| {
        removeRefAndRelease(parent);
        target.lock();
        if (typ == fs.INODE_FILE and (target.disk_inode.typ == fs.INODE_DEVICE or target.disk_inode.typ == fs.INODE_FILE)) {
            return target;
        }
        removeRefAndRelease(target);
        return error.TargetExists;
    }

    const create_inode = alloc(parent.device, typ) catch |e| {
        lib.printErr(e);
        return error.NoFreeInodesOnDisk;
    };

    create_inode.lock();

    create_inode.disk_inode.major = major;
    create_inode.disk_inode.minor = minor;
    create_inode.disk_inode.num_links = 1;
    update(create_inode);

    if (typ == fs.INODE_DIR) {
        dirLink(create_inode, @constCast(@ptrCast(DOT)), create_inode.inum);
        dirLink(create_inode, @constCast(@ptrCast(DOTDOT)), parent.inum);
    }

    dirLink(parent, @ptrCast(&name), create_inode.inum);

    if (typ == fs.INODE_DIR) {
        // for the .. ref
        parent.disk_inode.num_links += 1;
    }

    parent.release();
    return create_inode;
}

pub fn alloc(device: u16, typ: u16) !*INode {
    for (1..fs.loaded_super_block.num_inodes) |i| {
        const buffer = BufferCache.read(device, fs.inodeBlockNum(@intCast(i)));
        defer BufferCache.release(buffer);
        const buffer_inodes: *[fs.INODES_PER_BLOCK]fs.DiskINode = @ptrCast(@alignCast(&buffer.data));
        const index = i % fs.INODES_PER_BLOCK;
        if (buffer_inodes[index].typ == fs.INODE_FREE) {
            const inode_bytes: *[@sizeOf(fs.DiskINode)]u8 = @ptrCast(@alignCast(&buffer_inodes[index]));
            @memset(inode_bytes, 0);
            buffer_inodes[index].typ = typ;
            Log.write(buffer);
            return get(device, @intCast(i));
        }
    }
    return error.NoFreeInodesOnDisk;
}

pub fn update(inode: *INode) void {
    const buffer = BufferCache.read(inode.device, fs.inodeBlockNum(inode.inum));
    defer BufferCache.release(buffer);
    const buffer_inodes: *[fs.INODES_PER_BLOCK]fs.DiskINode = @ptrCast(@alignCast(&buffer.data));
    const index = inode.inum % fs.INODES_PER_BLOCK;

    const buffer_inode_bytes: *[@sizeOf(fs.DiskINode)]u8 = @ptrCast(@alignCast(&buffer_inodes[index]));
    const inode_bytes: *[@sizeOf(fs.DiskINode)]u8 = @ptrCast(@alignCast(&inode.disk_inode));
    @memcpy(buffer_inode_bytes, inode_bytes);
    Log.write(buffer);
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
    var rest: u16 = getNextPathElem(path, name, 0);

    while (rest < fs.DIR_NAME_SIZE) {
        current.lock();
        if (current.disk_inode.typ != fs.INODE_DIR) {
            removeRef(current);
            current.release();
            return error.NotDirectory;
        }

        if (get_parent and path[rest] == 0) {
            current.release();
            return current;
        }
        const new_inode = dirLookUp(current, name, null) orelse {
            removeRef(current);
            current.release();
            return error.NotFoundInDir;
        };

        current.release();
        current = new_inode;
        if (path[rest] == 0) {
            break;
        }
        rest = getNextPathElem(path[rest..], name, rest);
    } else {
        current.release();
        return current;
    }

    if (get_parent) {
        removeRef(current);
        current.release();
        return error.NotFound;
    }

    return current;
}

pub fn getNamedInode(path: [*:0]const u8) !*INode {
    const Static = struct {
        var name: [fs.DIR_NAME_SIZE:0]u8 = undefined;
    };
    return try getWithPath(path, false, &Static.name);
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

pub fn removeRefAndRelease(inode: *INode) void {
    inode.release();
    removeRef(inode);
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

fn dirLookUp(dir: *INode, name: [*:0]u8, put_offset: ?*u16) ?*INode {
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

pub fn dirLink(dir: *INode, name: [*]u8, inum: u16) void {
    const check_exists = dirLookUp(dir, @ptrCast(name), null);
    if (check_exists) |_| {
        return;
    }
    var offset: u32 = 0;
    var entry: fs.DirEntry = undefined;
    while (offset < dir.disk_inode.size) : (offset += @sizeOf(fs.DirEntry)) {
        const read = dir.readToAddress(@intFromPtr(&entry), offset, @sizeOf(fs.DirEntry), false) catch |e| {
            lib.printErr(e);
            return;
        };
        if (read != @sizeOf(fs.DirEntry)) {
            lib.kpanic("DIDNT READ DIR");
        }
        if (entry.inum == 0) {
            break;
        }
    }
    lib.strCopyNullTerm(&entry.name, @ptrCast(name), fs.DIR_NAME_SIZE);
    entry.inum = inum;
    _ = dir.writeTo(@intFromPtr(&entry), offset, @sizeOf(fs.DirEntry), false) catch |e| {
        lib.printErr(e);
    };
}
