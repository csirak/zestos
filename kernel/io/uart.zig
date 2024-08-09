const riscv = @import("../riscv.zig");
const SpinLock = @import("../locks/spinlock.zig");
const Console = @import("console.zig");
const lib = @import("../lib.zig");
const Cpu = @import("../cpu.zig");
const Process = @import("../procs/proc.zig");

const RHR = 0; // receive holding register (for input bytes)
const THR = 0; // transmit holding register (for output bytes)
const IER = 1; // interrupt enable register
const FCR = 2; // FIFO control register
const ISR = 2; // interrupt status register
const LCR = 3; // line control register
const MCR = 4; // modem control register
const LSR = 5; // line status register

const IER_RX_ENABLE: u8 = 1 << 0;
const IER_TX_ENABLE: u8 = 1 << 1;
const IER_LCR_ENABLE: u8 = 1 << 2;

const FCR_FIFO_ENABLE: u8 = 1 << 0;
const FCR_FIFO_CLEAR: u8 = 3 << 1; // clear the content of the two FIFOs

const LCR_EIGHT_BITS: u8 = 3 << 0;
const LCR_BAUD_LATCH: u8 = 1 << 7; // special mode to set baud rate

const LSR_RX_READY: u8 = 1 << 0; // input is waiting to be read from RHR
const LSR_TX_IDLE: u8 = 1 << 5; // THR can accept another character to send

const BAUD_RATE_DIVISOR_LSB: u8 = 0;
const BAUD_RATE_DIVISOR_MSB: u8 = 1;

inline fn uartRegister(reg: u32) *volatile u8 {
    return @ptrFromInt(riscv.UART0 + reg);
}

const UART_BUF_SIZE = 32;
const UartBuf = struct {
    var lock: SpinLock = undefined;
    var read_ptr: u64 = 0;
    var write_ptr: u64 = 0;
    var buffer: [UART_BUF_SIZE]u8 = undefined;
};

pub fn init() void {
    uartRegister(IER).* = 0; // disable interrupts initially
    uartRegister(LCR).* = LCR_BAUD_LATCH; // set baud rate mode
    uartRegister(BAUD_RATE_DIVISOR_LSB).* = 0x3;
    uartRegister(BAUD_RATE_DIVISOR_MSB).* = 0;

    uartRegister(LCR).* = LCR_EIGHT_BITS; // set word length to 8 bits

    uartRegister(FCR).* = FCR_FIFO_ENABLE | FCR_FIFO_CLEAR;
    uartRegister(IER).* = IER_TX_ENABLE | IER_RX_ENABLE; // enable RX and TX interrupts

    UartBuf.lock = SpinLock.init("uart");
}

pub fn putc(c: u8) void {
    Cpu.current().pushInterrupt();
    while (uartRegister(LSR).* & LSR_TX_IDLE == 0) {}
    uartRegister(THR).* = c;
    Cpu.current().popInterrupt();
}

pub fn bufPutc(c: u8) void {
    UartBuf.lock.acquire();
    defer UartBuf.lock.release();
    const proc = Process.currentOrPanic();
    while (UartBuf.write_ptr == UartBuf.read_ptr + UART_BUF_SIZE) {
        proc.sleep(&UartBuf.read_ptr, &UartBuf.lock);
    }
    UartBuf.buffer[UartBuf.write_ptr % UART_BUF_SIZE] = c;
    UartBuf.write_ptr += 1;
    uartStart();
}

pub fn handleInterrupt() void {
    while (getChar()) |c| {
        Console.handleInterrupt(c);
    }

    UartBuf.lock.acquire();
    defer UartBuf.lock.release();
    uartStart();
}

fn getChar() ?u8 {
    if (uartRegister(LSR).* & LSR_RX_READY == 0) {
        return null;
    }
    return uartRegister(RHR).*;
}

/// Must Hold UartBuf.lock
fn uartStart() void {
    while (true) {
        if (UartBuf.read_ptr == UartBuf.write_ptr) {
            _ = uartRegister(ISR).*;
            return;
        }
        if (uartRegister(LSR).* & LSR_TX_IDLE == 0) {
            // its full will interrupt when ready
            return;
        }
        const char = UartBuf.buffer[UartBuf.read_ptr % UART_BUF_SIZE];
        UartBuf.read_ptr += 1;

        // wake up if putc is waiting
        Process.wakeup(&UartBuf.read_ptr);
        uartRegister(THR).* = char;
    }
}
