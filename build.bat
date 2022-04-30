@echo off
rem use jwasm to build release versions of wde.com, wdex.com, setm43.exe and wdevdd.dll
if not exist "build\NUL" mkdir build
jwasm -mz -nologo -Fl=build\wde.lst -Fo=build\WDE.COM src\wde.asm
jwasm -mz -nologo -D?PM=1 -Fl=build\wdex.lst -Fo=build\WDEX.COM src\wde.asm
jwasm -mz -nologo -Fl=build\setm43.lst -Fo=build\setm43.exe src\setm43.asm
jwasm -pe -nologo -zze -I src\INCLUDE -Fl=build\wdevdd.lst -Fo build\wdevdd.dll src\wdevdd.asm
