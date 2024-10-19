@echo off
rem use jwasm -coff & jwlink
jwasm -nologo -coff -D?PUREFLAT -Fl compress.asm
jwlink format win pe hx f compress.obj op m,q,stub=loadpe.bin,stack=0x4000,heap=0x1000
rem
rem use jwasm -pe; needs jwasm v2.19+
rem jwasm -nologo -pe -DFMTPE -D?STUB=\hx\bin\loadpe.bin -D?PUREFLAT -Fl compress.asm
rem patchpe -s:0x2000 -x compress.exe
