const std = @import("std");

comptime {
    asm (
        \\.globl putChar
        \\putChar:
        \\.equ     UART_REG_TXFIFO, 0
        \\.equ     UART_BASE, 0x10000000
        \\li       t0, UART_BASE           # load UART base address
        \\
        \\.Lputchar_loop:
        \\lw       t1, UART_REG_TXFIFO(t0) # read UART TX FIFO status
        \\li       t2, 0x80000000
        \\and      t1, t1, t2
        \\bnez     t1, .Lputchar_loop      # if TX FIFO is full, wait
        \\
        \\sw       a0, UART_REG_TXFIFO(t0) # write character to TX FIFO
        \\ret
    );
}

extern fn putChar(c: u8) void;

pub fn print(s: []const u8) void {
    for (s) |c| {
        putChar(c);
    }
}

pub fn println(s: []const u8) void {
    print(s);
    putChar('\n');
}

pub fn printInt(n: u64) void {
    var buf: [20]u8 = undefined;
    println(intToString(n, &buf));
}

pub fn printPtr(ptr: anytype) void {
    printInt(@intFromPtr(ptr));
}

fn intToString(int: u64, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "0x{x}", .{int}) catch "";
}

pub fn kpanic(msg: []const u8) noreturn {
    print("kernel panic: ");
    println(msg);
    while (true) {}
}
