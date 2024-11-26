const syscalls = @import("./lib/syscalls.zig");
const io = @import("./lib/io.zig");

export fn _start(argc: u64, argv: [*]u8) void {
    const message = "Hello World!\n";
    _ = argc;
    _ = argv;

    io.printf("{s}", .{message});
    // io.printf("{}, {*}", .{ argc, argv });
    _ = syscalls.exit(0);
}
