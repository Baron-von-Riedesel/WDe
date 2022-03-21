
;--- this tool sets 100x43 lines text mode 
;--- how is this done?
;--- 1. set vesa gfx mode 0x102 (800x600x4)
;--- 2. change some CRT registers (max scan line, cursor start/end, mode control)
;--- 3. change some sequencer registers (set odd/even mode)
;--- 4. change some graphics controller registers (set odd/even mode, text mode, ...)
;--- 5. change some attribute controller registers
;--- 6. load VGA ROM font 14x8 into plane 2

;--- possible problems:
;--- VESA mode 0x102 not supported
;--- mouse driver doesn't expect a non-80 columns resolution
;--- when running in a DOS Box, windows might not be able to save/restore video settings

;--- to create the binary, run: jwasm -mz setm43.asm

	.286
	.model small,stdcall

ROWS	equ 43				;600/14 ( actually, 43*14 is 602 )
?DRIVER	equ 1				;insert code to generate a DOS driver + .EXE

	.stack 200h
	.code

	ASSUME DS: _TEXT

if ?DRIVER

IODAT   struct				;structure for dos device drivers
cmdlen  db      ?
unit    db      ?
cmd     db      ?
status  dw      ?
        db      8 dup (?)
media   db      ?
trans   dd      ?
count   dw      ?
start   dw      ?
drive   db      ?
IODAT   ends

	dw 0ffffh
	dw 0ffffh
	dw 8000h				;attribute
	dw offset devstrat		;device strategy
	dw offset devint		;device interrupt
	db 'SETM37$1'			;device name 8 chars (use carefully)

saveptr dd 1 dup(?)

devstrat proc far
	mov cs:word ptr[saveptr],bx
	mov cs:word ptr[saveptr+2],es
	ret
devstrat endp

devint proc far
	pusha
	push ds
	push es
	lds bx,cs:[saveptr]
	mov [bx.IODAT.status],8103h
	cmp [bx.IODAT.cmd],00
	jnz devi1
	mov [bx.IODAT.status],0100h
	mov word ptr [bx+0eh],0000
	mov word ptr [bx+10h],cs
	xor dx,dx
	call main
devi1:
	pop ds
	pop es
	popa
	ret
devint endp

endif

;--- clear write protection for CRT register 0-7

disablewp proc
	mov al,11h			;vertikal retrace end register bit 7 reset
	out dx,al
	inc dx
	in al,dx
	and al,7fh
	out dx,al
	dec dx
	ret
disablewp endp

;--- restore write protection for CRT register 0-7

enablewp proc
	mov al,11h
	out dx,al
	inc dx
	in al,dx
	or al,80h
	out dx,al
	dec dx
	ret
enablewp endp

;--- get input status register 1

getinpst1 proc
	mov dx,3cch
	in al,dx
	mov dx,3dah
	test al,1
	jnz @F
	mov dx,3bah
@@:
	ret
getinpst1 endp

;--- clear text screen

clearscreen proc uses ds
	push 40h
	pop ds
	mov dx,0b800h
	mov ax,ds:[63h]
	cmp ax,3d4h
	jz @F
	mov dh,0b0h
@@:
	mov es,dx
	mov di,ds:[4eh]
	mov cx,ds:[4ch]
	shr cx,1
	mov ax,0720h
	rep stosw
	mov bh,ds:[62h]
	mov ah,02
	mov dx,0000
	int 10h
	ret
clearscreen endp

;--- set a plane to read/write 

setplane0:
	mov ah,0
	jmp setplane
setplane1:
	mov ah,1
	jmp setplane
setplane2:
	mov ah,2
setplane::
	mov cl,ah
	mov dx,3ceh
	mov al,4		;"read map select"
	out dx,ax
	mov dx,3c4h
	mov ah,1
	shl ah,cl
	mov al,2		;"map mask" register:select map to write to
	out dx,ax
	ret

;--- setevenmode: changes dx, ax
;--- sets register: 3CE: 1, 5, 6, 8
;--- sets register: 3C4: 4

setevenmode proc
	mov dx,3ceh
	mov ax,1		;"enable set/reset" register
    out dx,ax

	mov al,5		;"graphics mode" register
	out dx,al
	inc dx
	in al,dx
	and al,084h 	;reset "odd/even mode", set "read mode 0"
	out dx,al		;set "write mode" 0

	mov dx,3ceh
	mov al,6		;"miscellaneous" register
	out dx,al
	inc dx
	in al,dx
	and al,0F0h 	;reset "odd/even"
	or al,1+4+8		;set addr=B800h,32K, graphics mode
	out dx,al

	mov dx,3ceh
	mov al,8		;"bit mask" register: all bits to change 
	mov ah,0FFh
	out dx,ax

	mov dl,0c4h
	mov al,4
	out dx,al
	inc dx
	in al,dx
	and al,not 8 	;reset "chain 4"
	or al,4+2		;set odd/even=4, set extended memory=2	
	out dx,al
	ret
setevenmode endp

;--- table of values to save/restore

savetab label word
	dw 3CEh
	db 4,5,6,8,-1
	dw 3C4h
	db 2,4,-1
	dw -1

;--- save regs of graphics controller + sequencer

saveregs proc
	push ss
	pop es
	mov si,offset savetab
devdone:
	lodsw
	cmp ax,-1
	jz done
	mov dx,ax
nextindex:
	lodsb
	cmp al,-1
	jz devdone
	out dx,al
	inc dx
	in al,dx
	stosb
	dec dx
	jmp nextindex
done:
	ret
saveregs endp

;--- restore regs of graphics controller + sequencer

restregs proc

	mov bx,si
	mov si,offset savetab
devdone:
	lodsw
	cmp ax,-1
	jz done
	mov dx,ax
nextindex:
	lodsb
	cmp al,-1
	jz devdone
	mov ah,ss:[bx]
	inc bx
	out dx,ax
	jmp nextindex
done:
	ret
restregs endp

;--- load a 14 pixel font (256 * 32 == 8 kB)

LoadFontInPlane2 proc stdcall uses si di dwFnt:dword

local	savebuff[12]:byte

	cld
	lea di,savebuff
	call saveregs

	call setevenmode

	call setplane2
	mov ax,0B800h
	mov es,ax
	mov di,0000h		;use charset 0
	mov dl,00h
	mov dh,14			;char size
	push ds
	lds si,[dwFnt]
	mov ch,0
nextchar:
	inc si
	mov cl,dh
	lea bx, [di+20h]
	rep movsb
	inc si
	mov di, bx
	inc dl
	jnz nextchar
	pop ds
	lea si,savebuff
	call restregs
	ret
LoadFontInPlane2 endp

main proc c

local	bFlags:word
local	dwFnt14:dword

	mov bFlags,dx
	push cs
	pop ds
	assume ds:_TEXT

	push bp
	mov ax,1130h		;get ROM VGA font (14 pixel)
	mov bh,2
	int 10h
	mov dx,bp
	pop bp
	mov word ptr [dwFnt14+0],dx
	mov word ptr [dwFnt14+2],es

;--- set vesa gfx mode 102h (800x600x4)

	mov ax,4F02h
	mov bx,102h
	int 10h
	cmp ax,004Fh
	jnz notsupported

;--- set BIOS variables to match the new resolution

	push 0
	pop es
	mov byte ptr es:[449h],3		;video mode
	mov word ptr es:[44Eh],0		;page start
	mov word ptr es:[460h],0C0Dh	;cursor form
	and byte ptr es:[465h],0fdh     ;reset bit 1 ("graphics" mode)
	or byte ptr es:[465h],1         ;set bit 0 ("text" mode)
	mov byte ptr es:[484h],ROWS-1	;max line#
	mov byte ptr es:[485h],14		;scan lines
	mov al,es:[044Ah]				;columns
	mov cl,ROWS*2
	mul cl
	mov word ptr es:[44ch],ax		;page size (ROWS * CULUMNS * size WORD)

;--- reprogram CRT controller

	cli
	mov  dx,es:[463h]	;get crt address
	call disablewp
	mov al,9
	out dx,al
	inc dx
	in al,dx
	and al,0E0h			;clear bits 0-4
	or al,0Dh			;set max scan line to 13
	out dx,al
	dec dx

	mov ax,0C0Ah		;set cursor start/end
	out dx,ax
	mov ax,0D0Bh
	out dx,ax
if 1
	mov ax,5B10h		;vertical retrace start at line 603
	out dx,ax
	mov ax,5912h		;vertical display end at line 601
	out dx,ax
	mov ax,5915h		;vertical blank start at line 601
	out dx,ax
endif
	mov al,17h			;mode control register
	out dx,al
	inc dx
	in al,dx
	and al,not 40h		;set byte mode
	out dx,al
	dec dx

	call enablewp

;--- write sequencer

;--- make planes 2+3 write protected
	mov dx,3c4h
	mov al,2
	mov ah,3
	out dx,ax

;--- set odd/even mode, reset chain 4, more than 64 kB
	mov dx,3c4h
	mov al,4
	mov ah,2
	out dx,ax

;--- write graphics controller

	mov dx,3ceh
	mov ax,1005h	;set write mode 0, read mode 0, odd/even addressing
	out dx,ax

	mov dx,3ceh
	mov al,6
	out dx,al
	inc dx
	in al,dx
	and al,0F0h
	or al,0Eh		;set B800h as base, set text mode, set odd/even
	out dx,al

;--- write attribute controller

	call getinpst1
	in al,dx			;reset attribute controller
	mov dx,3c0h

	mov al,10h			;select mode register
	out dx,al
	mov al,0			;set text mode [bit 0=0]
	out dx,al

	mov al,20h			;turn screen on again
	out dx,al

	push word ptr [dwFnt14+2]
	push word ptr [dwFnt14+0]
	call LoadFontinPlane2

	sti

	.if (bFlags & 1)
		call clearscreen
	.else
		push 40h
		pop ds
		mov cx,ds:[4Ch]
		mov si,ds:[4Eh]
		mov ax,0B800h
		cmp byte ptr ds:[63h],0D4h
		jz @F
		mov ax,0B000h
@@:
		shr cx,1
		mov ds,ax
nextchar:
		lodsw
		cmp ah,0
		jnz @F
		mov ax,0720h
		mov [si-2],ax
@@:
		loop nextchar
	.endif
notsupported:
	mov al,00
	ret
main endp


start:
;--- get cmdline parameter

	mov bx,80h
	mov cl,es:[bx]
	inc bx
	xor ax,ax
	xor dx,dx
	.while (cl)
		mov ah,al
		mov al,es:[bx]
		or al,20h
		.if ((ah == '/') || (ah == '-'))
			.if (al == 'c')
				or dl,1
			.elseif (al == '?')
				push cs
				pop ds
				mov dx,offset help
				mov ah,9
				int 21h
				jmp exit
			.endif
		.endif
		inc bx
		dec cl
	.endw
	call main
exit:
	mov ah,4ch
	int 21h

help db "usage: SETM43 [option]",13,10
     db "option: -c  clear screen",13,10
     db "        -?  this text",13,10,'$'

	END start
