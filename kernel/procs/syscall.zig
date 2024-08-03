const fs = @import("../fs/fs.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");
const Process = @import("proc.zig");

const File = @import("../fs/file.zig");
const INodeTable = @import("../fs/inodetable.zig");
const FileTable = @import("../fs/filetable.zig");
const Log = @import("../fs/log.zig");

const exec = @import("exec.zig").exec;

pub const SYSCALL_FORK = 1;
pub const SYSCALL_EXIT = 2;
pub const SYSCALL_EXEC = 7;
pub const SYSCALL_DUP = 10;
pub const SYSCALL_OPEN = 15;
pub const SYSCALL_WRITE = 16;
pub const SYSCALL_MAKE_NODE = 17;
pub const SYSCALL_PUT_CHAR = 64;

const MAX_PATH = 128;

const Static = struct {
    var exec_path_buff: [MAX_PATH]u8 = undefined;
    var open_path_buff: [MAX_PATH]u8 = undefined;
    var makenode_path_buff: [MAX_PATH]u8 = undefined;
};

pub fn doSyscall() void {
    const proc = Process.currentOrPanic();
    const syscall_num = proc.trapframe.?.a7;

    if (syscall_num == SYSCALL_FORK) {
        const pid = proc.fork() catch {
            lib.kpanic("Failed to fork");
        };
        proc.trapframe.?.a0 = pid;
        return;
    }
    if (syscall_num == SYSCALL_EXIT) {
        exitSys(proc);
        return;
    }
    if (syscall_num == SYSCALL_EXEC) {
        execSys(proc);

        return;
    }
    if (syscall_num == SYSCALL_DUP) {
        const result = dupSys(proc);
        proc.trapframe.?.a0 = @bitCast(result);
        return;
    }
    if (syscall_num == SYSCALL_WRITE) {
        const result = writeSys(proc);
        proc.trapframe.?.a0 = @bitCast(result);
        return;
    }
    if (syscall_num == SYSCALL_OPEN) {
        const result = openSys(proc);
        proc.trapframe.?.a0 = @bitCast(result);
        return;
    }
    if (syscall_num == SYSCALL_MAKE_NODE) {
        const result = makedNodeSys(proc);
        proc.trapframe.?.a0 = @bitCast(result);
        return;
    }
    lib.printAndInt("address: ", proc.trapframe.?.epc);
    lib.printAndDec("syscall_num: ", syscall_num);
    lib.kpanic("Unknown syscall");
}

fn execSys(proc: *Process) void {
    const path_user_address = proc.trapframe.?.a0;
    proc.pagetable.?.copyFrom(path_user_address, @ptrCast(&Static.exec_path_buff), MAX_PATH) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };
    exec(@ptrCast(&Static.exec_path_buff)) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to exec /init");
    };
}
fn dupSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    const file = proc.open_files[fd].?;
    const new_fd = proc.fileDescriptorAlloc(file) catch {
        return -1;
    };
    return @intCast(new_fd);
}

fn exitSys(proc: *Process) void {
    const status = proc.trapframe.?.a0;
    proc.exit(@intCast(status));
}

fn openSys(proc: *Process) i64 {
    Log.beginTx();
    defer Log.endTx();

    const path_user_address = proc.trapframe.?.a0;
    proc.pagetable.?.copyFrom(path_user_address, @ptrCast(&Static.open_path_buff), MAX_PATH) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };

    const mode = proc.trapframe.?.a1;
    const inode = inode: {
        if (mode & File.O_CREATE != 0) {
            break :inode INodeTable.create(@ptrCast(&Static.open_path_buff), fs.INODE_FILE, 0, 0) catch {
                return -1;
            };
        } else {
            const file_inode = INodeTable.getNamedInode(@ptrCast(&Static.open_path_buff)) catch {
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

fn writeSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    const file = proc.open_files[fd].?;
    const buff_user_address = proc.trapframe.?.a1;
    const size = proc.trapframe.?.a2;
    file.write(buff_user_address, size) catch |e| {
        lib.printf("error: {}\n", .{e});
        return -1;
    };
    return 0;
}

fn makedNodeSys(proc: *Process) i64 {
    const path_user_address = proc.trapframe.?.a0;
    proc.pagetable.?.copyFrom(path_user_address, @ptrCast(&Static.makenode_path_buff), MAX_PATH) catch |e| {
        lib.printf("error: {}\n", .{e});
        lib.kpanic("Failed to copy path from user to kernel");
    };
    const major: u16 = @intCast(proc.trapframe.?.a1);
    const minor: u16 = @intCast(proc.trapframe.?.a2);
    Log.beginTx();
    defer Log.endTx();
    const inode = INodeTable.create(@ptrCast(&Static.makenode_path_buff), fs.INODE_DEVICE, major, minor) catch |e| {
        lib.printf("error: {}\n", .{e});
        return -1;
    };
    INodeTable.removeRefAndRelease(inode);
    return 0;
}

fn writeSys(proc: *Process) i64 {
    const fd = proc.trapframe.?.a0;
    const file = proc.open_files[fd].?;
    const buff_user_address = proc.trapframe.?.a1;
    const size = proc.trapframe.?.a2;
    file.write(buff_user_address, size) catch |e| {
        lib.printErr(e);
        return -1;
    };
    return 0;
}
