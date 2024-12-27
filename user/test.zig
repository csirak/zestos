const syscalls = @import("./lib/syscalls.zig");
const io = @import("./lib/io.zig");

export fn _start(argc: u64, argv_ptr: [*][*:0]const u8) void {
    const argv = argv_ptr[0..argc];
    for (argv) |arg| {
        io.printf("{s}\n", .{arg});
    }
    syscalls.exit(0);
}
