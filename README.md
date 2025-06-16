xv6 port written fully in zig
additional features:
- introspection during unknown traps, as well as a syscall to stop programs at any point and observe:
  - kernel/user memory
  - inode blocks directly
  - file tables
  - coming soon: kernel stacks and user stack tracing
- blockdump

stay zesty
