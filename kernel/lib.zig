const std = @import("std");
const riscv = @import("riscv.zig");
const Cpu = @import("cpu.zig");

var print_buffer = [_]u8{0} ** 4096;
var print_fba = std.heap.FixedBufferAllocator.init(&print_buffer);
const print_allocator = print_fba.allocator();

comptime {
    asm (
        \\.globl putchar_asm
        \\putchar_asm:
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
extern fn putchar_asm(c: u8) void;

pub fn put_char(c: u8) void {
    Cpu.current().pushInterrupt();
    putchar_asm(c);
    Cpu.current().popInterrupt();
}

pub fn print(s: []const u8) void {
    for (s) |c| {
        put_char(c);
    }
}

pub fn putChar(c: u8) void {
    put_char(c);
}

pub fn println(s: []const u8) void {
    print(s);
    put_char('\n');
}

pub fn printNullTerm(ptr: [*]const u8) void {
    var i: u16 = 0;
    while (ptr[i] != 0) : (i += 1) {}
    print(ptr[0..i]);
}

pub fn printlnNullTerm(ptr: [*]const u8) void {
    printNullTerm(ptr);
    put_char('\n');
}

pub fn printlnNullTermWrapped(ptr: [*]const u8) void {
    put_char('{');
    printNullTerm(ptr);
    put_char('}');
    put_char('\n');
}

pub fn printErr(e: anyerror) void {
    println(@errorName(e));
}
var buf: [20]u8 = undefined;

pub fn printInt(n: u64) void {
    printIntHex(n);
    put_char('\n');
}

pub fn printByte(b: u8) void {
    var out = [_]u8{0} ** 3;
    out[0] = intToAsciiHex(@intCast((b >> 4) & 0xF));
    out[1] = intToAsciiHex(@intCast(b & 0xF));
    print(out[0..3]);
}

pub fn printIntDec(n: u64) void {
    // 0 x (8 chars) \0
    var out = [_]u8{'0'} ** 20;
    out[19] = 0;

    var cur = n;
    var i: u8 = 1;
    while (cur > 0) {
        const num = cur % 10;
        out[19 - i] = @intCast(num + 48);
        cur /= 10;
        i += 1;
    }
    const bound = 20 - i;

    print(out[bound..20]);
}

pub fn printIntHex(n: u64) void {
    // 0 x (8 chars) \0
    var out = [_:0]u8{'0'} ** 18;
    out[1] = 'x';

    var cur = n;
    var i: u8 = 0;
    while (cur > 0) {
        const num: u8 = @intCast(cur & 0xF);
        out[17 - i] = intToAsciiHex(num);
        cur = cur >> 4;
        i += 1;
    }

    printNullTerm(&out);
}

pub fn intToAsciiHex(n: u8) u8 {
    if (n < 10) {
        return n + '0';
    } else {
        return n + 'a' - 10;
    }
}

pub inline fn printAndInt(s: []const u8, n: u64) void {
    print(s);
    printInt(n);
}

pub fn printAndDec(s: []const u8, n: u64) void {
    print(s);
    printIntDec(n);
    put_char('\n');
}

pub fn printPtr(ptr: anytype) void {
    printInt(@intFromPtr(ptr));
}

pub fn kpanic(msg: []const u8) noreturn {
    print("kernel panic: ");
    println(msg);
    while (true) {}
    unreachable;
}

pub fn kpanicInt(msg: []const u8, n: u64) noreturn {
    print("kernel panic: ");
    print(msg);
    print(": ");
    printInt(n);
    while (true) {}
    unreachable;
}

pub fn strCopy(dst: []u8, src: []const u8, size: u64) void {
    const len = @min(src.len, size);
    for (0..len) |i| {
        dst[i] = src[i];
    }
}

pub fn strCopyNullTerm(dst: []u8, src: [*:0]u8, size: u64) void {
    for (0..size) |i| {
        dst[i] = src[i];
    }
}

pub fn strEq(a: [*]u8, b: [*]const u8, size: u64) bool {
    for (0..size) |i| {
        if (a[i] & b[i] == 0) {
            return true;
        }
        if (a[i] != b[i]) {
            return false;
        }
    }
    return true;
}

pub fn coreLog(comptime s: []const u8) void {
    const id = riscv.cpuid();
    const idchar = [_]u8{ @intCast(id + 48), ' ' };
    const out = "zest core: " ++ idchar ++ s;
    println(out);
}

pub fn printCpuInfo() void {
    print("cpu depth: ");
    printByte(@intCast(Cpu.current().disabled_depth));
    println("");
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    const out = std.fmt.allocPrint(print_allocator, fmt, args) catch unreachable;
    print(out);
}
