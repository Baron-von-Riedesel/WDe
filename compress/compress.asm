
;--- compress - a little "bonus" tool for WDe.
;--- it "compresses" a directory stored in a file by
;--- removing all "deleted" entries ( first byte == E5h ).
;--- Public Domain.

	.386
	.model flat, c
	option casemap:none

BUFFSIZE equ 256  ;buffer size in kB

lf equ 10

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

ifdef FMTPE
	option dotname
.hdr$1 segment use16
%	incbin <?STUB>
.hdr$1 ends
.drectve segment info
	db "-fixed:no"
.drectve ends
endif

	.data?

buffer	db BUFFSIZE * 1024 dup (?)

	.code

	include printf.inc

;--- remove all entries containing E5 at pos 0
;--- dwItem: # of directory entries

compress proc uses esi edi pBuffer:ptr, dwItems:dword
	cld
	mov esi, pBuffer
	mov edi, pBuffer
	mov ecx, dwItems
	xor edx, edx
nextentry:
	mov al, [esi]
	cmp al, 0E5h
	jz skipentry
	push ecx
	mov ecx, 32/4
	rep movsd
	pop ecx
	loop nextentry
	jmp done
skipentry:
	inc edx
	add esi, 32
	loop nextentry
done:
	and edx, edx
	jz @F
	mov ecx, edx
	shl ecx, 5
	xor eax, eax
	rep stosd
@@:
	ret
compress endp

;--- open file
;--- first try LFN function, then SFN

openfile proc uses esi edi pszName:ptr
	mov esi, pszName
	mov cx, 0			; normal file
	mov di, 0
	mov dl, 1h			; fail if file not exists
	mov dh, 0
	mov bx, 2			; read+write
	mov ax, 716Ch		; open file
	int 21h
	jnc @F
	cmp ax, 7100h
	stc
	jnz @F
	mov ax, 6C00h		; try SFN variant
	int 21h
@@:
	ret
openfile endp

;--- set abs/rel file position

setfilepos proc hFile:dword, dwPos:dword, bType:byte
	mov ebx, hFile
	mov dx, word ptr dwPos+0
	mov cx, word ptr dwPos+2
	mov al, bType
	mov ah, 42h
	int 21h
	ret
setfilepos endp

getfilesize proc hFile:dword
	invoke setfilepos, hFile, 0, 2	; set file pos to EOF
	jc @F
	push dx				; returns abs position (=size) in DX:AX
	push ax
	invoke setfilepos, hFile, 0, 0
	pop eax
@@:
	ret
getfilesize endp

readfile proc hFile:dword, pBuffer:ptr, dwSize:dword
	mov ebx, hFile
	mov edx, pBuffer
	mov ecx, dwSize
	mov ah, 3Fh
	int 21h
	ret
readfile endp

writefile proc hFile:dword, pBuffer:ptr, dwSize:dword
	mov ebx, hFile
	mov edx, pBuffer
	mov ecx, dwSize
	mov ah, 40h
	int 21h
	ret
writefile endp

main proc c argc:dword, argv:ptr ptr 

local	hFile:dword
local	dwSize:dword

	mov hFile, -1

	mov eax,argc
	cmp eax, 2
	jb error            ; no argument given
	mov ebx,argv
@@:
	mov esi,[ebx+4]

	invoke openfile, esi
	jc openerr
	mov hFile, eax

	invoke getfilesize, eax
	jc seekerr
	mov dwSize, eax
	test al, 11111b		; size must be a multiple of 32
	jnz invalidfile
	cmp eax, sizeof buffer
	ja buffertoosmall

	invoke readfile, hFile, offset buffer, dwSize
	jc readerr
	mov eax, dwSize
	shr eax, 5			; divide by 32
	invoke compress, offset buffer, eax
	jc exiterr

	invoke setfilepos, hFile, 0, 0
	invoke writefile, hFile, offset buffer, dwSize
	jc writeerr
	invoke printf, CStr("done",lf)
	mov al,0
	jmp exit

openerr:
	invoke printf, CStr("file '%s' open error [%X]",lf), esi, eax
	jmp exiterr
buffertoosmall:
	test ax, 3FFh
	setnz cl
	shr eax, 10
	movzx ecx, cl
	add eax, ecx
	invoke printf, CStr(<"file size (%u kB) exceeds buffer size (%u kB)",lf>), eax, BUFFSIZE
	jmp exiterr
invalidfile:
	invoke printf, CStr(<"file size not a multiple of 32",lf>)
	jmp exiterr
seekerr:
	invoke printf, CStr(<"seek error [%X]",lf>), eax
	jmp exiterr
readerr:
	invoke printf, CStr(<"read error [%X]",lf>), eax
	jmp exiterr
writeerr:
	invoke printf, CStr(<"write error [%X]",lf>), eax
	jmp exiterr
error:
	invoke printf, CStr(<"compress - removes 'deleted' entries of a FAT directory stored in a file.",lf>)
	invoke printf, CStr(<"usage: compress filename",lf>)
exiterr:
	mov al,1
exit:
	call closefiles
	ret

closefiles:
	mov ebx,hFile
	.if (ebx != -1)
		push eax
		mov ah,3Eh
		int 21h
		pop eax
	.endif
	retn

main endp

	include setargv.inc

_start:
	call _setargv
	invoke main, [_argc], [_argv]
	mov ah,4ch
	int 21h

	END _start
