@echo off

rem release version
jwasm -Zm -bin -Fl=build\wde.lst -Fo=build\wde.com src\wde.asm
jwasm -mz -Fl=build\setm43.lst -Fo=build\setm43.exe src\setm43.asm
jwasm -coff -I src\INCLUDE -Fo build\wdevdd.obj src\wdevdd.asm
jwlink format windows pe dll file build\wdevdd.obj name build\wdevdd.dll lib lib\Kernel32.lib, lib\ntvdm.lib export Init='_Init@0', Dispatch='_Dispatch@0'

rem debug version
rem jwasm -Zm -bin -D_DEBUG -Fl=build\wde.lst -Fo=build\wde.com src\wde.asm
rem jwasm -coff -D_DEBUG -Fl=build\wdevdd.lst -Sg -I src\Include src\wdevdd.asm
rem jwlink format windows nt dll file build\wdevdd.obj name build\wdevdd.dll lib lib\Kernel32.lib, lib\User32.lib, lib\ntvdm.lib export Init='_Init@0', Dispatch='_Dispatch@0'
