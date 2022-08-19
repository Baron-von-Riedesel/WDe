@echo off
rem
rem build WDE.COM with MS tools Masm/Link
rem
if not exist "build\NUL" mkdir build
rem
ml -c -nologo -Flbuild\wde.lst -Fobuild\wde.obj src\wde.asm
\msvc\bin\link /NOLOGO/MAP:FULL build\WDe.obj, build\WDe.exe, build\WDe.map;
