target extended-remote localhost:1234
layout asm
shell clear
winheight asm -5
refresh
wh asm -10
set can-use-hw-watchpoints 0

file ./zig-out/bin/kernel
