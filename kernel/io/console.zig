const lib = @import("../lib.zig");
const Spinlock = @import("../locks/spinlock.zig");
const Process = @import("../procs/proc.zig");
const Device = @import("../device.zig");
const UART = @import("uart.zig");

const Self = @This();

var lock: Spinlock = Spinlock.init("console");

pub fn init() void {
    UART.init();
    Device.registerDevice(getDevice());
}

pub fn println(s: []const u8) void {
    lock.acquire();
    lib.println(s);
    lock.release();
}

pub fn print(s: []const u8) void {
    lock.acquire();
    lib.print(s);
    lock.release();
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    lock.acquire();
    lib.printf(fmt, args);
    lock.release();
}

pub fn coreLog(comptime s: []const u8) void {
    lock.acquire();
    lib.coreLog(s);
    lock.release();
}

pub fn kpanic(comptime s: []const u8) void {
    lock.acquire();
    lib.kpanic(s);
    lock.release();
}

pub fn write(user_addr: bool, buffer_ptr: u64, size: u64) !u64 {
    const proc = Process.currentOrPanic();

    for (0..size) |i| {
        var byte: [1]u8 = undefined;
        if (user_addr) try proc.pagetable.?.copyFrom(buffer_ptr + i, &byte, 1) else {
            byte[0] = @as(*u8, @ptrFromInt(buffer_ptr + i)).*;
        }
        UART.bufPutc(byte[0]);
    }
    return size;
}

const CONSOLE_BUF_SIZE = 128;
pub const ConsoleBuf = struct {
    var lock = Spinlock.init("console");
    var read_ptr: u64 = 0;
    var write_ptr: u64 = 0;
    var edit_ptr: u64 = 0;
    var buffer: [CONSOLE_BUF_SIZE]u8 = undefined;
};

pub inline fn CTRL(c: u8) u8 {
    comptime {
        return c - '@';
    }
}

var count: u8 = 0;
pub fn read(user_addr: bool, buffer_ptr: u64, size: u64) !u64 {
    const proc = Process.currentOrPanic();
    var cur_read: u64 = 0;
    ConsoleBuf.lock.acquire();
    defer ConsoleBuf.lock.release();

    while (cur_read < size) {
        while (ConsoleBuf.read_ptr == ConsoleBuf.write_ptr) {
            if (proc.isKilled()) return error.Interrupted;
            proc.sleep(&ConsoleBuf.read_ptr, &ConsoleBuf.lock);
        }
        var char = ConsoleBuf.buffer[ConsoleBuf.read_ptr % CONSOLE_BUF_SIZE];
        ConsoleBuf.read_ptr += 1;

        if (char == CTRL('D')) {
            // if we have read something, return that, wait then EOF
            if (cur_read > 0) {
                ConsoleBuf.read_ptr -= 1;
            }
            break;
        }

        if (user_addr) {
            try proc.pagetable.?.copyInto(buffer_ptr + cur_read, @ptrCast(&char), 1);
        } else {
            @as(*u8, @ptrFromInt(buffer_ptr + cur_read)).* = char;
        }
        cur_read += 1;

        if (char == '\n') {
            break;
        }
    }

    return cur_read;
}

pub fn getDevice() Device {
    return .{
        .ptr = undefined,
        .writeFn = @ptrCast(&write),
        .readFn = @ptrCast(&read),
        .major = 1,
    };
}

const BACKSPACE = CTRL('H');
const DELETE = 0x7f;

pub fn handleInterrupt(char: u8) void {
    // if we have no space left, discard the character
    if (char == 0 or ConsoleBuf.edit_ptr - ConsoleBuf.read_ptr > CONSOLE_BUF_SIZE) return;
    ConsoleBuf.lock.acquire();
    defer ConsoleBuf.lock.release();

    switch (char) {
        0 => return,
        DELETE, BACKSPACE => if (ConsoleBuf.edit_ptr != ConsoleBuf.write_ptr) {
            ConsoleBuf.edit_ptr -= 1;
            putc(BACKSPACE);
        },
        else => {
            if (ConsoleBuf.edit_ptr - ConsoleBuf.read_ptr >= CONSOLE_BUF_SIZE) {
                return;
            }
            const screen_char = if (char == '\r') '\n' else char;
            putc(screen_char);

            ConsoleBuf.buffer[ConsoleBuf.edit_ptr % CONSOLE_BUF_SIZE] = char;
            ConsoleBuf.edit_ptr += 1;

            if (screen_char == '\n' or screen_char == CTRL('D') or ConsoleBuf.edit_ptr - ConsoleBuf.read_ptr == CONSOLE_BUF_SIZE) {
                ConsoleBuf.write_ptr = ConsoleBuf.edit_ptr;
                Process.wakeup(&ConsoleBuf.read_ptr);
            }
        },
    }
}

fn putc(c: u8) void {
    if (c == BACKSPACE) {
        UART.putc(8);
        UART.putc(' ');
        UART.putc(8);
    } else {
        UART.putc(c);
    }
}
