const fs = @import("../fs/fs.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");
const Process = @import("proc.zig");

const KMem = @import("../mem/kmem.zig");

const File = @import("../fs/file.zig");
const Pipe = @import("../fs/pipe.zig");
const INodeTable = @import("../fs/inodetable.zig");
const FileTable = @import("../fs/filetable.zig");
const Log = @import("../fs/log.zig");

const exec = @import("exec.zig").exec;

pub const SYSCALL_FORK = 1;
pub const SYSCALL_EXIT = 2;
pub const SYSCALL_WAIT = 3;
pub const SYSCALL_PIPE = 4;
pub const SYSCALL_READ = 5;
pub const SYSCALL_EXEC = 7;
pub const SYSCALL_STAT = 8;
pub const SYSCALL_DUP = 10;
pub const SYSCALL_SBRK = 12;
pub const SYSCALL_OPEN = 15;
pub const SYSCALL_WRITE = 16;
pub const SYSCALL_MAKE_NODE = 17;
pub const SYSCALL_CLOSE = 21;

const MAX_PATH = 128;

pub fn doSyscall() void {
    const proc = Process.currentOrPanic();
    const syscall_num = proc.trapframe.?.a7;
    switch (syscall_num) {
        SYSCALL_FORK => proc.trapframe.?.a0 = proc.fork() catch {
            lib.kpanic("Failed to fork");
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
        SYSCALL_DUP => {
            proc.trapframe.?.a0 = @bitCast(dupSys(proc));
        },
        SYSCALL_SBRK => {
            proc.trapframe.?.a0 = @bitCast(sbrkSys(proc));
        },
        SYSCALL_WRITE => {
            proc.trapframe.?.a0 = @bitCast(writeSys(proc));
        },
        SYSCALL_OPEN => {
            proc.trapframe.?.a0 = @bitCast(openSys(proc));
        },
        SYSCALL_MAKE_NODE => {
            proc.trapframe.?.a0 = @bitCast(makedNodeSys(proc));
        },
        SYSCALL_CLOSE => closeSys(proc),
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

    try proc.pagetable.?.copyInto(
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
        var path_buff = [_]u8{0} ** MAX_PATH;
    };

    proc.pagetable.?.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), MAX_PATH) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };

    var argv = [_]?[*:0]u8{null} ** Process.MAX_ARGS;

    for (0..Process.MAX_ARGS) |i| {
        var cur_arg: u64 = undefined;
        try proc.pagetable.?.copyFrom(argv_user_address + @sizeOf(u64) * i, @ptrCast(&cur_arg), @sizeOf(u64));
        if (cur_arg == 0) {
            argv[i] = null;
            break;
        }

        const arg_ptr: [*:0]u8 = @ptrCast(try KMem.alloc());
        try proc.pagetable.?.copyStringFromUser(cur_arg, @ptrCast(arg_ptr), riscv.PGSIZE);
        argv[i] = arg_ptr;
    }

    defer {
        for (argv) |arg| if (arg) |ptr| {
            KMem.free(@intFromPtr(ptr));
        };
    }

    return exec(@ptrCast(&S.path_buff), argv) catch -1;
}

fn openSys(proc: *Process) i64 {
    const S = struct {
        var path_buff = [_]u8{0} ** MAX_PATH;
    };
    Log.beginTx();
    defer Log.endTx();

    const path_user_address = proc.trapframe.?.a0;

    proc.pagetable.?.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), MAX_PATH) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };

    const mode = proc.trapframe.?.a1;
    const inode = inode: {
        if (mode & File.O_CREATE != 0) {
            break :inode INodeTable.create(@ptrCast(&S.path_buff), fs.INODE_FILE, 0, 0) catch {
                return -1;
            };
        } else {
            const file_inode = INodeTable.getNamedInode(@ptrCast(&S.path_buff)) catch {
                return -1;
            };
            file_inode.lock();
            if (file_inode.disk_inode.typ == fs.INODE_DIR and mode != File.O_RDONLY) {
                INodeTable.removeRefAndRelease(file_inode);
                return -1;
            }
            break :inode file_inode;
        }
    };
    if (inode.disk_inode.typ == fs.INODE_DEVICE and inode.disk_inode.major >= fs.NUM_DEVICES) {
        INodeTable.removeRefAndRelease(inode);
        return -1;
    }
    const file = FileTable.alloc();
    const fd = proc.fileDescriptorAlloc(file) catch {
        INodeTable.removeRefAndRelease(inode);
        lib.println("No file descriptor available");
        return -1;
    };

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
fn sbrkSys(proc: *Process) i64 {
    const size: i64 = @bitCast(proc.trapframe.?.a0);
    const old_brk = proc.mem_size;
    proc.resizeMem(size) catch |e| {
        lib.printf("error: {}\n", .{e});
        return -1;
    };
    return @intCast(old_brk);
}

fn writeSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    const file = proc.open_files[fd].?;
    const buff_user_address = proc.trapframe.?.a1;
    const size = proc.trapframe.?.a2;
    return file.write(buff_user_address, size) catch |e| {
        lib.printf("error: {}\n", .{e});
        return -1;
    };
}

fn makedNodeSys(proc: *Process) i64 {
    const S = struct {
        var path_buff = [_]u8{0} ** MAX_PATH;
    };
    const path_user_address = proc.trapframe.?.a0;
    proc.pagetable.?.copyStringFromUser(path_user_address, @ptrCast(&S.path_buff), MAX_PATH) catch |e| {
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

fn closeSys(proc: *Process) void {
    const fd = proc.trapframe.?.a0;
    if (proc.open_files[fd]) |file| {
        FileTable.free(file);
    }
    proc.open_files[fd] = null;
}
