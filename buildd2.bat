@echo off

rem build debug versions of WDe
rem this version contains "codeview" debug info that is understood by WD.
rem WD should be launched with the /SWAP option.

if not exist "Debug\NUL" mkdir Debug

rem build the standard version
jwasm -Zi -nologo -Fl=Debug\wde.lst -Fo=Debug\WDE.obj src\wde.asm
jwlink debug c format dos f Debug\wde.obj n Debug\wde.exe op q,m=Debug\wde.map,cvp

rem build the DPMI version
rem jwasm -Zi -nologo -D?PM=1 -Fl=Debug\wdex.lst -Fo=Debug\WDEx.obj src\wde.asm
rem jwlink debug c format dos f Debug\wdex.obj n Debug\wdex.exe op q,m=Debug\wdex.map,cvp

rem using MS tools - might work better with CodeView.
rem ml -c -Zi -nologo -FlDebug\wde.lst -FoDebug\WDE.obj src\wde.asm
rem link16 /CO/NOLOGO/MAP Debug\WDe.obj, Debug\WDe.exe, Debug\WDe.map;

