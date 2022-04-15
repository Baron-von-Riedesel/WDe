

odir=build
idir=src

all: $(odir)\wde.com $(odir)\setm43.exe $(odir)\wdevdd.dll

$(odir)\wde.com: $(idir)\wde.asm
	jwasm -mz -nologo -Sg -Fl=$(odir)\wde.lst -Fo=$(odir)\wde.com $(idir)\wde.asm

$(odir)\setm43.exe: $(idir)\setm43.asm
	jwasm -mz -nologo -Sg -Fl=$(odir)\setm43.lst -Fo=$(odir)\setm43.exe $(idir)\setm43.asm

$(odir)\wdevdd.dll: $(idir)\wdevdd.asm
	jwasm -pe -nologo -zze -I $(idir)\INCLUDE -Fl=$(odir)\wdevdd.lst -Fo $(odir)\wdevdd.dll $(idir)\wdevdd.asm
