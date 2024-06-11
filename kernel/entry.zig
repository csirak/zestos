const mem = @cImport(@cInclude("memlayout.h"));

export const stack0 align(16) = [_]u8{0} ** (mem.PGSIZE * mem.NCPU);
export const timer_scratch align(16) = [_]u64{0} ** (mem.NCPU * 5);

comptime {
    asm (
        \\# qemu -kernel loads the kernel at 0x80000000
        \\# and causes each hart (i.e. CPU) to jump there.
        \\# kernel.ld causes the following code to
        \\# be placed at 0x80000000.
        \\.section .text.entry
        \\.global  _entry
        \\_entry:
        \\# set up a stack for C.
        \\# stack0 is declared in start.c,
        \\# with a 4096-byte stack per CPU.
        \\      la       sp, stack0
        \\      li       a0, 1024*4
        \\      csrr     a1, mhartid
        \\      addi     a1, a1, 1
        \\      mul      a0, a0, a1
        \\      add      sp, sp, a0
        \\# jump to start() in start.c
        \\      call     start
        \\spin:
        \\      j        spin
    );
}
