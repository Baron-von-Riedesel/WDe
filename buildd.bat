@echo off
rem use jwasm to build debug versions of wde.com, wdex.com
if not exist "debug\NUL" mkdir debug
jwasm -mz -nologo -D?DEBUG=1 -Fl=debug\wde.lst -Fo=debug\WDE.COM src\wde.asm
jwasm -mz -nologo -D?DEBUG=1 -D?PM=1 -Fl=debug\wdex.lst -Fo=debug\WDEX.COM src\wde.asm
