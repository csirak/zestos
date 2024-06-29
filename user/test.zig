// inline fn ecall(number: u64) void {}

export fn _start() void {
    putChar('a');
}

pub fn putChar(c: u8) void {
    const number = 64;
    asm volatile ("ecall"
        :
        : [number] "{a7}" (number),
          [arg1] "{a0}" (c),
    );
}
