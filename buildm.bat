@echo off
rem build WDE.COM with Masm and jwlink
if not exist "build\NUL" mkdir build
ml -c -nologo -Flbuild\wde.lst -Fo build\wde.obj src\wde.asm
jwlink format dos file build\wde.obj name build\WDE.COM op m=build\wde.map,q
