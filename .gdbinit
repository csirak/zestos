target extended-remote localhost:1234
file zig-out/bin/kernel -o 0x80000000
layout asm
shell clear
winheight asm -5
refresh
wh asm -10
