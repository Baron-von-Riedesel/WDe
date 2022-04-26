@echo off

rem use jwasm to build debug versions of wde.com, wdex.com

jwasm -mz -nologo -D?DEBUG=1 -Fl=debug\wde.lst -Fo=debug\WDE.COM src\wde.asm
jwasm -mz -nologo -D?DEBUG=1 -D?PM=1 -Fl=debug\wdex.lst -Fo=debug\WDEX.COM src\wde.asm
