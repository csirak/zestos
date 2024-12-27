const syscalls = @import("./lib/syscalls.zig");
const io = @import("./lib/io.zig");

export fn _start(argc: u64, argv_ptr: [*][*:0]const u8) void {
    const argv = argv_ptr[0..argc];
    for (argv[1..]) |arg| {
        const fd = syscalls.open(arg, 0) orelse @panic("OPEN FAILED");
        cat(fd) catch |e| {
            io.printf("cat: {}\n", .{e});
            syscalls.exit(1);
        };
        _ = syscalls.close(fd);
    }
    syscalls.exit(0);
}

// bss
// block size
var buffer = [_]u8{0} ** 1024;

const CatError = error{ ReadError, WriteError };

fn cat(fd: u64) CatError!void {
    while (syscalls.read_slice(fd, buffer[0..])) |n| {
        if (n < 1) return;
        const written = syscalls.write_slice(1, buffer[0..n]) orelse return CatError.WriteError;
        if (written < n) return CatError.WriteError;
    } else return CatError.ReadError;
}
