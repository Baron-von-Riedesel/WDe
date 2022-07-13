@echo off

rem This .BAT builds "debug" versions of wde.com and wdex.com;
rem "debug" means, these versions display a log (may be redirected to a file).
rem To create binaries that contain debug info, see buildd2.bat.

if not exist "debug\NUL" mkdir debug
jwasm -mz -nologo -D?DEBUG=1 -Fl=debug\wde.lst -Fo=debug\WDE.COM src\wde.asm
jwasm -mz -nologo -D?DEBUG=1 -D?PM=1 -Fl=debug\wdex.lst -Fo=debug\WDEX.COM src\wde.asm
