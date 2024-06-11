static const unsigned long long NCPU = 4;
static const unsigned long long PGSIZE = 4096; // bytes per page
static const unsigned long long MAXVA = (1 << (9 + 9 + 9 + 12 - 1));
// the kernel expects there to be RAM
// for use by the kernel and user pages
// from physical address 0x80000000 to PHYSTOP.
static const unsigned long long KERNBASE = 0x80000000;
static const unsigned long long PHYSTOP = (KERNBASE + 128 * 1024 * 1024);

// map the trampoline page to the highest address,
// in both user and kernel space.
static const unsigned long long TRAMPOLINE = (MAXVA - PGSIZE);

// map kernel stacks beneath the trampoline,
// each surrounded by invalid guard pages.
#define KSTACK(p) (TRAMPOLINE - ((p) + 1) * 2 * PGSIZE)

// User memory layout.
// Address zero first:
//   text
//   original data and bss
//   fixed-size stack
//   expandable heap
//   ...
//   TRAPFRAME (p->trapframe, used by the trampoline)
//   TRAMPOLINE (the same page as in the kernel)
static const unsigned long long TRAPFRAME = (TRAMPOLINE - PGSIZE);

// Machine Status Register, mstatus

#define MSTATUS_MPP_MASK (3L << 11) // previous mode.
#define MSTATUS_MPP_M (3L << 11)
#define MSTATUS_MPP_S (1L << 11)
#define MSTATUS_MPP_U (0L << 11)
#define MSTATUS_MIE (1L << 3) // machine-mode interrupt enable.
