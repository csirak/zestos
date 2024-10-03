const std = @import("std");
const riscv = @import("riscv.zig");
const Cpu = @import("cpu.zig");
const Uart = @import("io/Uart.zig");

var print_buffer = [_]u8{0} ** 4096;
var print_fba = std.heap.FixedBufferAllocator.init(&print_buffer);
const print_allocator = print_fba.allocator();

pub fn print(s: []const u8) void {
    for (s) |c| {
        Uart.putc(c);
    }
}

pub fn putChar(c: u8) void {
    Uart.putc(c);
}

pub fn println(s: []const u8) void {
    print(s);
    Uart.putc('\n');
}

pub fn printNullTerm(ptr: [*]const u8) void {
    var i: u16 = 0;
    while (ptr[i] != 0) : (i += 1) {}
    print(ptr[0..i]);
}

pub fn printlnNullTerm(ptr: [*]const u8) void {
    printNullTerm(ptr);
    Uart.putc('\n');
}

pub fn printlnNullTermWrapped(ptr: [*]const u8) void {
    Uart.putc('{');
    printNullTerm(ptr);
    Uart.putc('}');
    Uart.putc('\n');
}

pub fn kpanic(msg: []const u8) noreturn {
    print("kernel panic: ");
    println(msg);
    while (true) {}
    unreachable;
}

pub fn strLen(s: []u8) u64 {
    var i: u64 = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

pub fn strCopy(dst: []u8, src: []const u8, size: u64) void {
    const len = @min(src.len, size);
    for (0..len) |i| {
        dst[i] = src[i];
    }
}

pub fn strCopyNullTerm(dst: [*]u8, src: [*]u8, size: u64) void {
    for (0..size) |i| {
        dst[i] = src[i];
    }
}

pub fn strEq(a: [*]const u8, b: [*]const u8, size: u64) bool {
    for (0..size) |i| {
        if (a[i] == 0 and b[i] == 0) {
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
    printf("0x{x}", @intCast(Cpu.current().disabled_depth));
    println("");
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    const out = std.fmt.allocPrint(print_allocator, fmt, args) catch unreachable;
    print(out);
}

pub fn intToAsciiHex(n: u8) u8 {
    if (n < 10) {
        return n + '0';
    } else {
        return n + 'a' - 10;
    }
}

pub fn printByte(b: u8) void {
    var out = [_]u8{0} ** 3;
    out[0] = intToAsciiHex(@intCast((b >> 4) & 0xF));
    out[1] = intToAsciiHex(@intCast(b & 0xF));
    print(out[0..3]);
}
