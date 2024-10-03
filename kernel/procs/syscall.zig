const std = @import("std");

const fs = @import("../fs/fs.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");

const Process = @import("proc.zig");
const Timer = @import("../timer.zig");

const KMem = @import("../mem/kmem.zig");

const File = @import("../fs/file.zig");
const Pipe = @import("../fs/pipe.zig");
const INodeTable = @import("../fs/inodetable.zig");
const FileTable = @import("../fs/filetable.zig");
const Log = @import("../fs/log.zig");
const Traps = @import("../trap.zig");

const exec = @import("exec.zig").exec;

pub const SYSCALL_FORK = 1;
pub const SYSCALL_EXIT = 2;
pub const SYSCALL_WAIT = 3;
pub const SYSCALL_PIPE = 4;
pub const SYSCALL_READ = 5;
pub const SYSCALL_EXEC = 7;
pub const SYSCALL_STAT = 8;
pub const SYSCALL_CHDIR = 9;
pub const SYSCALL_DUP = 10;
pub const SYSCALL_GETPID = 11;
pub const SYSCALL_SBRK = 12;
pub const SYSCALL_SLEEP = 13;
pub const SYSCALL_UPTIME = 14;
pub const SYSCALL_OPEN = 15;
pub const SYSCALL_WRITE = 16;
pub const SYSCALL_MAKE_NODE = 17;
pub const SYSCALL_UNLINK = 18;
pub const SYSCALL_LINK = 19;
pub const SYSCALL_MKDIR = 20;
pub const SYSCALL_CLOSE = 21;

pub fn doSyscall() void {
    const proc = Process.currentOrPanic();
    const syscall_num = proc.trapframe.?.a7;
    switch (syscall_num) {
        SYSCALL_FORK => proc.trapframe.?.a0 = proc.fork() catch {
            @panic("Failed to fork");
        },
        SYSCALL_EXIT => proc.exit(@intCast(proc.trapframe.?.a0)),
        SYSCALL_WAIT => {
            proc.trapframe.?.a0 = @bitCast(waitSys(proc));
        },
        SYSCALL_READ => {
            proc.trapframe.?.a0 = @bitCast(readSys(proc));
        },
        SYSCALL_PIPE => {
            const res = pipeSys(proc) catch |e| out: {
                lib.printf("error: {}\n", .{e});
                break :out -1;
            };

            proc.trapframe.?.a0 = @bitCast(res);
        },
        SYSCALL_EXEC => {
            const result = execSys(proc) catch |e| out: {
                lib.printf("error: {}\n", .{e});
                break :out -1;
            };
            proc.trapframe.?.a0 = @bitCast(result);
        },
        SYSCALL_STAT => {
            proc.trapframe.?.a0 = @bitCast(statSys(proc));
        },
        SYSCALL_CHDIR => {
            proc.trapframe.?.a0 = @bitCast(chdirSys(proc) catch -1);
        },
        SYSCALL_DUP => {
            proc.trapframe.?.a0 = @bitCast(dupSys(proc));
        },
        SYSCALL_GETPID => {
            proc.trapframe.?.a0 = proc.getPid();
        },
        SYSCALL_UPTIME => {
            proc.trapframe.?.a0 = Timer.getTick();
        },
        SYSCALL_SBRK => {
            proc.trapframe.?.a0 = @bitCast(sbrkSys(proc));
        },
        SYSCALL_SLEEP => {
            proc.trapframe.?.a0 = @bitCast(sleepSys(proc));
        },
        SYSCALL_WRITE => {
            proc.trapframe.?.a0 = @bitCast(writeSys(proc));
        },
        SYSCALL_OPEN => {
            proc.trapframe.?.a0 = @bitCast(openSys(proc) catch -1);
        },
        SYSCALL_MAKE_NODE => {
            proc.trapframe.?.a0 = @bitCast(makedNodeSys(proc));
        },
        SYSCALL_UNLINK => {
            proc.trapframe.?.a0 = @bitCast(unlinkSys(proc) catch -1);
        },
        SYSCALL_LINK => {
            proc.trapframe.?.a0 = @bitCast(linkSys(proc) catch -1);
        },
        SYSCALL_MKDIR => {
            proc.trapframe.?.a0 = @bitCast(mkdirSys(proc) catch -1);
        },
        SYSCALL_CLOSE => {
            proc.trapframe.?.a0 = @bitCast(closeSys(proc));
        },
        else => {
            lib.printf("address: 0x{x}\nsyscall_num: {}\n", .{ proc.trapframe.?.epc, syscall_num });
            lib.kpanic("Unknown syscall");
        },
    }
}

fn waitSys(proc: *Process) i64 {
    const dummy = 0;
    const status = proc.wait(dummy) catch {
        return -1;
    };
    return @intCast(status);
}

fn readSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    const buffer_user_address = proc.trapframe.?.a1;
    const size = proc.trapframe.?.a2;
    const file = proc.open_files[fd].?;
    return file.read(buffer_user_address, size) catch |e| {
        lib.printf("error: {}\n", .{e});
        return -1;
    };
}

fn pipeSys(proc: *Process) !i64 {
    var read_file: *File = undefined;
    var write_file: *File = undefined;
    try Pipe.alloc(&read_file, &write_file);

    errdefer FileTable.free(read_file);
    errdefer FileTable.free(write_file);

    const fd_array_user_ptr = proc.trapframe.?.a0;

    var file_descriptors: [2]u32 = undefined;

    file_descriptors[0] = @truncate(try proc.fileDescriptorAlloc(read_file));
    errdefer proc.fileDescriptorFree(file_descriptors[0]) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };

    file_descriptors[1] = @truncate(try proc.fileDescriptorAlloc(write_file));
    errdefer proc.fileDescriptorFree(file_descriptors[1]) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };

    try proc.pagetable.copyInto(
        fd_array_user_ptr,
        @ptrCast(&file_descriptors),
        @sizeOf(@TypeOf(file_descriptors)),
    );
    return 0;
}

fn execSys(proc: *Process) !i64 {
    const path_user_address = proc.trapframe.?.a0;
    const argv_user_address = proc.trapframe.?.a1;
    const S = struct {
        var path_buff = [_]u8{0} ** fs.MAX_PATH;
    };

    proc.pagetable.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), fs.MAX_PATH) catch return -1;

    var argv = [_]?[*:0]u8{null} ** Process.MAX_ARGS;

    for (0..Process.MAX_ARGS) |i| {
        var cur_arg: u64 = undefined;
        try proc.pagetable.copyFrom(argv_user_address + @sizeOf(u64) * i, @ptrCast(&cur_arg), @sizeOf(u64));
        if (cur_arg == 0) {
            argv[i] = null;
            break;
        }

        const arg_ptr: [*:0]u8 = @ptrCast(try KMem.alloc());
        try proc.pagetable.copyStringFromUser(cur_arg, @ptrCast(arg_ptr), riscv.PGSIZE);
        argv[i] = arg_ptr;
    }

    defer {
        for (argv) |arg| if (arg) |ptr| {
            KMem.free(@intFromPtr(ptr));
        };
    }

    return exec(@ptrCast(&S.path_buff), argv) catch -1;
}

fn openSys(proc: *Process) !i64 {
    const S = struct {
        var path_buff = [_]u8{0} ** fs.MAX_PATH;
    };
    Log.beginTx();
    defer Log.endTx();

    const path_user_address = proc.trapframe.?.a0;

    proc.pagetable.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), fs.MAX_PATH) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };

    const mode = proc.trapframe.?.a1;
    const inode = if (mode & File.O_CREATE != 0)
        try INodeTable.create(@ptrCast(&S.path_buff), fs.INODE_FILE, 0, 0)
    else inode: {
        const file_inode = try INodeTable.getNamedInode(@ptrCast(&S.path_buff));
        errdefer INodeTable.removeRefAndRelease(file_inode);
        file_inode.lock();
        if (file_inode.disk_inode.typ == fs.INODE_DIR and mode != File.O_RDONLY) {
            return error.NotDirectory;
        }
        break :inode file_inode;
    };

    errdefer INodeTable.removeRefAndRelease(inode);
    if (inode.disk_inode.typ == fs.INODE_DEVICE and inode.disk_inode.major >= fs.NUM_DEVICES) {
        return error.DeviceNotFound;
    }
    const file = FileTable.alloc();
    const fd = try proc.fileDescriptorAlloc(file);

    file.readable = (mode & File.O_WRONLY) == 0;
    file.writable = (mode & File.O_WRONLY) != 0 or (mode & File.O_RDWR) != 0;
    file.reference_count = 1;

    file.data = if (inode.disk_inode.typ == fs.INODE_DEVICE) .{
        .device = .{
            .major = inode.disk_inode.major,
            .inode = inode,
        },
    } else data: {
        if (mode & File.O_TRUNC != 0) {
            inode.truncate();
        }
        break :data .{
            .inode_file = .{
                .inode = inode,
                .offset = 0,
            },
        };
    };

    inode.release();
    return @intCast(fd);
}

fn dupSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    const file = proc.open_files[fd].?;
    const new_fd = proc.fileDescriptorAlloc(file) catch {
        return -1;
    };
    _ = FileTable.duplicate(file);
    return @intCast(new_fd);
}

fn statSys(proc: *Process) i64 {
    const file_descriptor = proc.trapframe.?.a0;
    const address = proc.trapframe.?.a1;
    if (proc.open_files[file_descriptor]) |file| {
        return file.getStat(address) catch -1;
    }
    return -1;
}

fn chdirSys(proc: *Process) !i64 {
    const S = struct {
        var path_buff = [_]u8{0} ** fs.MAX_PATH;
    };
    Log.beginTx();
    errdefer Log.endTx();

    const path_user_address = proc.trapframe.?.a0;

    try proc.pagetable.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), fs.MAX_PATH);

    const inode = try INodeTable.getNamedInode(@ptrCast(&S.path_buff));

    inode.lock();
    errdefer INodeTable.removeRefAndRelease(inode);
    if (inode.disk_inode.typ != fs.INODE_DIR) {
        return error.PathNotDir;
    }

    inode.release();
    INodeTable.removeRef(proc.cwd);
    Log.endTx();

    proc.cwd = inode;
    return 0;
}

fn sbrkSys(proc: *Process) i64 {
    const size: i64 = @bitCast(proc.trapframe.?.a0);
    const old_brk = proc.mem_size;
    proc.resizeMem(size) catch |e| {
        lib.printf("error: {}\n", .{e});
        return -1;
    };
    return @intCast(old_brk);
}

fn sleepSys(proc: *Process) i64 {
    const time = proc.trapframe.?.a0;
    const ticks0 = Timer.getTick();
    Timer.lock.acquire();
    defer Timer.lock.release();

    while (Timer.getTick() - ticks0 < time) {
        if (proc.isKilled()) {
            return -1;
        }
        proc.sleep(&Timer.ticks, &Timer.lock);
    }
    return 0;
}

fn writeSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    const file = proc.open_files[fd].?;
    const buff_user_address = proc.trapframe.?.a1;
    const size = proc.trapframe.?.a2;
    return file.write(buff_user_address, size) catch return -1;
}

fn makedNodeSys(proc: *Process) i64 {
    const S = struct {
        var path_buff = [_]u8{0} ** fs.MAX_PATH;
    };
    const path_user_address = proc.trapframe.?.a0;
    proc.pagetable.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), fs.MAX_PATH) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };
    const major: u16 = @intCast(proc.trapframe.?.a1);
    const minor: u16 = @intCast(proc.trapframe.?.a2);
    Log.beginTx();
    defer Log.endTx();
    const inode = INodeTable.create(@ptrCast(&S.path_buff), fs.INODE_DEVICE, major, minor) catch |e| {
        lib.printf("error: {}\n", .{e});
        return -1;
    };
    INodeTable.removeRefAndRelease(inode);
    return 0;
}

fn unlinkSys(proc: *Process) !i64 {
    const S = struct {
        var name_path_buff = [_]u8{0} ** fs.DIR_NAME_SIZE;
        var path_buff = [_]u8{0} ** fs.MAX_PATH;
    };
    try proc.pagetable.copyStringFromUser(proc.trapframe.?.a0, @ptrCast(&S.path_buff), fs.MAX_PATH);

    Log.beginTx();
    defer Log.endTx();

    var parent = try INodeTable.getWithPath(@ptrCast(&S.path_buff), true, @ptrCast(&S.name_path_buff));
    parent.lock();
    defer INodeTable.removeRefAndRelease(parent);

    if (lib.strEq(@ptrCast(&S.name_path_buff), ".", fs.DIR_NAME_SIZE) or lib.strEq(@ptrCast(&S.name_path_buff), "..", fs.DIR_NAME_SIZE)) {
        return error.InvalidUnlink;
    }

    var offset: u16 = 0;
    const target_inode = INodeTable.dirLookUp(parent, &S.name_path_buff, &offset) orelse return error.TargetNotFoundInDir;
    target_inode.lock();
    errdefer INodeTable.removeRefAndRelease(target_inode);

    if (target_inode.reference_count < 1) {
        return error.InvalidReferenceCount;
    }

    if (target_inode.disk_inode.typ == fs.INODE_DIR and !(try target_inode.isDirEmpty())) {
        return error.DirInodeNotEmpty;
    }

    const empty_dirent = std.mem.zeroes(fs.DirEntry);
    const write_bytes = try parent.writeTo(@intFromPtr(&empty_dirent), @intCast(offset), @sizeOf(fs.DirEntry), false);

    if (write_bytes != @sizeOf(fs.DirEntry)) {
        return error.InvalidDirEntDelete;
    }

    if (target_inode.disk_inode.typ == fs.INODE_DIR) {
        parent.disk_inode.num_links -= 1;
        INodeTable.update(parent);
    }
    target_inode.disk_inode.num_links -= 1;
    INodeTable.update(target_inode);

    return 0;
}

fn linkSys(proc: *Process) !i64 {
    const S = struct {
        var name_path_buff = [_]u8{0} ** fs.DIR_NAME_SIZE;
        var new_path_buff = [_]u8{0} ** fs.MAX_PATH;
        var old_path_buff = [_]u8{0} ** fs.MAX_PATH;
    };
    try proc.pagetable.copyStringFromUser(proc.trapframe.?.a0, @ptrCast(&S.old_path_buff), fs.MAX_PATH);
    try proc.pagetable.copyStringFromUser(proc.trapframe.?.a1, @ptrCast(&S.new_path_buff), fs.MAX_PATH);

    Log.beginTx();
    defer Log.endTx();

    const inode = try INodeTable.getNamedInode(@ptrCast(&S.old_path_buff));
    inode.lock();

    if (inode.disk_inode.typ == fs.INODE_DIR) {
        INodeTable.removeRefAndRelease(inode);
        return -1;
    }

    inode.reference_count += 1;
    INodeTable.update(inode);
    inode.release();
    errdefer {
        inode.lock();
        inode.reference_count -= 1;
        INodeTable.update(inode);
        INodeTable.removeRefAndRelease(inode);
    }

    const parent = try INodeTable.getWithPath(@ptrCast(&S.new_path_buff), true, @ptrCast(&S.name_path_buff));
    parent.lock();
    defer INodeTable.removeRefAndRelease(parent);

    if (parent.device != inode.device) {
        return -1;
    }
    try INodeTable.dirLink(parent, &S.name_path_buff, inode.inum);

    // on line 389 only release this closes
    INodeTable.removeRef(inode);

    return 0;
}

fn mkdirSys(proc: *Process) !i64 {
    const S = struct {
        var path_buff = [_]u8{0} ** fs.MAX_PATH;
    };
    Log.beginTx();
    defer Log.endTx();

    const path_user_address = proc.trapframe.?.a0;

    try proc.pagetable.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), fs.MAX_PATH);
    const inode = try INodeTable.create(@ptrCast(&S.path_buff), fs.INODE_DIR, 0, 0);
    INodeTable.removeRefAndRelease(inode);
    return 0;
}

fn closeSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    if (proc.open_files[fd]) |file| {
        FileTable.free(file);
        proc.open_files[fd] = null;
        return 0;
    }
    return -1;
}
