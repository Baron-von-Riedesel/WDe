@echo off

rem release version
jwasm -mz -nologo -Fl=build\wde.lst -Fo=build\wde.com src\wde.asm
jwasm -mz -nologo -Fl=build\setm43.lst -Fo=build\setm43.exe src\setm43.asm
jwasm -pe -nologo -zze -I src\INCLUDE -Fl=build\wdevdd.lst -Fo build\wdevdd.dll src\wdevdd.asm
jwasm -mz -nologo -D?PM=1 -Fl=build\wdex.lst -Fo=build\wdex.com src\wde.asm

rem link step for wdevdd.dll, now obsolete - here are 2 examples for MS link and jwlink.
rem   The linkers need import libraries, though, that aren't supplied anymore.
rem   One might get them from the HX development package.
rem link /DLL build\wdevdd.obj /out:build\wdevdd.dll lib\Kernel32.lib lib\ntvdm.lib
rem jwlink format windows nt dll file build\wdevdd.obj name build\wdevdd.dll lib lib\Kernel32.lib, lib\User32.lib, lib\ntvdm.lib export Init='_Init@0', Dispatch='_Dispatch@0'
