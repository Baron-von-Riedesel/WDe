@echo off

rem This .BAT builds "debug" versions of wde.com and wdex.com;
rem "debug" means, these versions display a log (may be redirected to a file).
rem To create binaries that contain debug info, see buildd2.bat.

if not exist "Debug\NUL" mkdir debug
jwasm -mz -nologo -D?DEBUG=1 -Fl=Debug\wde.lst -Fo=Debug\WDE.COM src\wde.asm
jwasm -mz -nologo -D?DEBUG=1 -D?PM=1 -Fl=Debug\wdex.lst -Fo=Debug\WDEX.COM src\wde.asm
