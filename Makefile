
# this makefile creates
# - wde.com      : the standard WDe
# - setm43.exe   : helper tool to set a 43x100 text resolution with 14x8 font.
# - wdevdd.dll   : helper tool to allow direct disk access in WinXP/Vista
# - wdex.com     : WDe running as 16-bit DPMI client

odir=build
idir=src

incfiles=$(idir)\undelete.inc $(idir)\unformat.inc $(idir)\fatfs.inc $(idir)\getstrng.inc

all: $(odir) $(odir)\wde.com $(odir)\setm43.exe $(odir)\wdevdd.dll $(odir)\wdex.com

$(odir):
	@mkdir $(odir)

$(odir)\wde.com: $(idir)\wde.asm  $(incfiles)
	@jwasm -mz -nologo -Sg -Fl=$(odir)\wde.lst -Fo=$(odir)\WDE.COM $(idir)\wde.asm

$(odir)\setm43.exe: $(idir)\setm43.asm
	@jwasm -mz -nologo -Sg -Fl=$(odir)\setm43.lst -Fo=$(odir)\SETM43.EXE $(idir)\setm43.asm

$(odir)\wdevdd.dll: $(idir)\wdevdd.asm
	@jwasm -pe -nologo -zze -I $(idir)\INCLUDE -Fl=$(odir)\wdevdd.lst -Fo $(odir)\wdevdd.dll $(idir)\wdevdd.asm

$(odir)\wdex.com: $(idir)\wde.asm  $(incfiles) $(idir)\wdepm16.inc $(idir)\initpm16.inc
	@jwasm -mz -nologo -Sg -D?PM=1 -Fl=$(odir)\wdex.lst -Fo=$(odir)\WDEX.COM $(idir)\wde.asm

