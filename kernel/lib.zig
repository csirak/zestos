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
    var i: usize = 0;
    while (s[i] != 0 and i < s.len) : (i += 1) {
        putChar(s[i]);
    }
}

pub fn println(s: []const u8) void {
    print(s);
    putChar('y');
    putChar('\n');
}

pub fn printErr(e: anyerror) void {
    println(@errorName(e));
}

pub fn printInt(n: u64) void {
    println(intToString(n));
}

pub fn printPtr(ptr: anytype) void {
    printInt(@intFromPtr(ptr));
}

pub fn intToString(int: u64) []const u8 {
    var buf: [20]u8 = undefined;
    return std.fmt.bufPrint(&buf, "0x{x}", .{int}) catch "";
}

pub fn kpanic(msg: []const u8) noreturn {
    print("kernel panic: ");
    println(msg);
    while (true) {}
}
