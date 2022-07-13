@echo off

rem build debug versions of WDe
rem this version contains "codeview" debug info that is understood by WD.
rem WD should be launched with the /SWAP option.

if not exist "debug\NUL" mkdir debug

rem build the standard version
jwasm -Zi -nologo -Fl=debug\wde.lst -Fo=debug\WDE.obj src\wde.asm
jwlink debug c format dos f debug\wde.obj n debug\wde.exe op q,m=debug\wde.map,cvp

rem build the DPMI version
rem jwasm -Zi -nologo -D?PM=1 -Fl=debug\wdex.lst -Fo=debug\WDEx.obj src\wde.asm
rem jwlink debug c format dos f debug\wdex.obj n debug\wdex.exe op q,m=debug\wdex.map,cvp

rem MS tools
rem ml -c -Zi -nologo -FlDebug\wde.lst -FoDebug\WDE.obj src\wde.asm
rem link16 /CO/NOLOGO/MAP Debug\WDe.obj, Debug\WDe.exe, Debug\WDe.map;

