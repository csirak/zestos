const std = @import("std");
const riscv = @import("riscv.zig");

comptime {
    asm (
        \\.globl put_char
        \\put_char:
        \\.equ     UART_REG_TXFIFO, 0
        \\.equ     UART_BASE, 0x10000000
        \\li       t0, UART_BASE           # load UART base address
        \\
        \\.Lput_char_loop:
        \\lw       t1, UART_REG_TXFIFO(t0) # read UART TX FIFO status
        \\li       t2, 0x80000000
        \\and      t1, t1, t2
        \\bnez     t1, .Lput_char_loop      # if TX FIFO is full, wait
        \\
        \\sw       a0, UART_REG_TXFIFO(t0) # write character to TX FIFO
        \\ret
    );
}

extern fn put_char(c: u8) void;

pub fn print(s: []const u8) void {
    for (s) |c| {
        put_char(c);
    }
}

pub fn println(s: []const u8) void {
    print(s);
    put_char('\n');
}

pub fn printErr(e: anyerror) void {
    println(@errorName(e));
}

pub fn printInt(n: u64) void {
    var buf: [20]u8 = undefined;
    println(intToString(n, &buf));
}

pub fn printPtr(ptr: anytype) void {
    printInt(@intFromPtr(ptr));
}

pub fn intToString(int: u64, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "0x{x}", .{int}) catch "";
}

pub fn kpanic(msg: []const u8) noreturn {
    print("kernel panic: ");
    println(msg);
    while (true) {}
}

pub fn strCopy(dst: []u8, src: []const u8, size: u64) void {
    for (0..size) |i| {
        dst[i] = src[i];
    }
}

pub fn coreLog(comptime s: []const u8) void {
    const id = riscv.cpuid();
    const idchar = [_]u8{ @intCast(id + 48), ' ' };
    const out = "zest core: " ++ idchar ++ s;
    println(out);
}
