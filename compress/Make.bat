@echo off
jwasm -nologo -coff -D?PUREFLAT compress.asm
jwlink format win pe hx f compress.obj op m,q,stub=loadpe.bin,stack=0x4000,heap=0x1000
