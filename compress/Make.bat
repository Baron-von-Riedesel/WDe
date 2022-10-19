@echo off
jwasm -nologo -coff compress.asm
jwlink format win pe hx f compress.obj op m,q,stub=loadpe.bin
