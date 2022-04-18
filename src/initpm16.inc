
;*** startup code to run a small model program as 16-bit DPMI client
;*** will try to load HDPMI16.EXE if no DPMI host is active

EXECRM struct
environ dw ?
cmdline dd ?
fcb1    dd ?
fcb2    dd ?
res1    dd ?
res2    dd ?
EXECRM ends

_0000H   equ 0054h
_B800H   equ 005Ch
_B000H   equ 0064h

    .data

csalias dw 0
_CSALIAS equ <[csalias]>

    .const

szPath db 'PATH='

szHDPMI db 'HDPMI16.EXE',00
LHDPMI  equ $ - szHDPMI

errNoHost db "no DPMI host found",13,10,'$'
errInit   db "DPMI initialization failed",13,10,'$'

    .code

;--- alloc descriptors for _0000H, _B800H, _B000H and _CSALIAS

getdescriptors proc

    mov ax, 000Dh           ; alloc specific descriptor
    mov bx,_0000H
    int 31h
    jc done
    xor dx, dx
    xor cx, cx
    mov ax, 7
    int 31h
    mov dx, -1
    xor cx, cx
    mov ax, 8
    int 31h

    mov ax, 000Dh
    mov bx, _B800H
    int 31h
    jc done
    mov dx, lowword  0B8000h
    mov cx, highword 0B8000h
    mov ax, 7
    int 31h
    mov dx, -1
    xor cx, cx
    mov ax, 8
    int 31h

    mov ax, 000Dh
    mov bx, _B000H
    int 31h
    jc done
    mov dx, lowword  0B0000h
    mov cx, highword 0B0000h
    mov ax, 7
    int 31h
    mov dx, -1
    xor cx, cx
    mov ax, 8
    int 31h

    mov ax, 000Ah           ; alloc CS alias
    mov bx, cs
    int 31h
    jc done
    mov [csalias], bx
done:
    ret
getdescriptors endp

;--- DPMI initialization

initpm16 proc

    mov ax, 1687h           ; DPMI host installed?
    int 2fh
    and ax,ax
    jz @F
    call loadserver
    mov ax,1687h            ; try again
    int 2fh
    and ax,ax
    jnz nodpmi              ; still no host, exit
@@:        
    push es
    push di
    and si,si
    jz @F
                            ; alloc memory for dpmi host
    mov ah,48h
    mov bx,si
    int 21h
    jc memerr
    mov es, ax
@@:
    mov bp, sp
    xor ax, ax              ; run as 16-bit client
    call dword ptr [bp]
    jc initerr
    add sp, 4
    mov [_psp], es
    call getdescriptors
    jc initerr2
    ret

nodpmi:
    mov dx,offset errNoHost
    jmp errexit
memerr:
initerr:
initerr2:
    mov dx,offset errInit
errexit:
    mov ah, 9
    int 21h
    mov ax, 4CFFh
    int 21h
initpm16 endp

;*** search and load hdpmi16.exe

loadserver proc

local psp:word
local env:word
local cmdline:word
local parmblock:EXECRM
local pgmname[80]:byte

    mov ah, 51h
    int 21h
    mov psp, bx
    mov es, bx
    mov ax, es:[002Ch]
    mov env, ax

    call searchpath                  ; search PATH= variable -> SI, SI=0000 if error
    call searchpgm                   ; search HDPMI16
    jb error                         ; error "not found"

    mov AX, env
    mov parmblock.environ, ax
    mov cmdline, 0D00h
    lea bx, cmdline
    mov word ptr parmblock.cmdline+0, bx
    mov word ptr parmblock.cmdline+2, ss
    mov AX, psp
    mov word ptr parmblock.fcb1+0, 5Ch
    mov word ptr parmblock.fcb1+2, ax
    mov word ptr parmblock.fcb1+0, 6Ch
    mov word ptr parmblock.fcb2+2, ax

    push ss
    pop es
    lea dx, pgmname
    lea bx, parmblock
    mov ax, 4B00h                    ; execute dpmi host executable
    int 21h
    jb error
    mov ax, 1
    ret
error:
    mov ax, 0
    ret

;*** search HDPMI16 in current directory and directories of PATH
;*** Input: SI=address of PATH Variable or NULL (no PATH defined)
;***      : DI=name of executable (=hdpmi16.exe)

searchpgm:
    push si
    mov si, di
    lea di, pgmname
    push ds
    pop es
    mov dx, di
    push ds
    mov ds, env
nxtc:
    lodsb
    stosb
    cmp al,'\'
    jnz @F
    mov dx,di
@@:
    cmp al,0
    jnz nxtc
    pop ds
    mov di,dx
    pop si
    mov bl,0
nexttry:                             ; <----
    push si
    mov si, offset szHDPMI
    mov cx, LHDPMI
    rep movsb

    lea dx, pgmname
    mov ax, 3d00h
    int 21h
    pop si
    jnb hostfound                    ; found!
    and bl, bl
    jnz @F
    mov bl, 1
    lea di, pgmname                  ; get current directory
    jmp nexttry
@@:
    and si, si
    jz nohost                        ; PATH isnt defined, so were done
    mov di, dx
    push ds
    mov ds, env
@@:
    lodsb
    stosb
    cmp al,';'
    jz @f
    cmp al, 00
    jnz @b
    xor si, si
@@:
    pop ds
    dec di
    cmp byte ptr es:[di-01], '\'
    jz nexttry
    mov byte ptr es:[di], '\'
    inc di
    jmp nexttry

hostfound:
    mov bx, ax
    mov ah, 3eh                      ; close file
    int 21h
    clc
    retn
nohost:
    stc
    retn

;*** search PATH in environment
;*** Out: SI-> behind "PATH=" or 0000
;***      DI-> path of executable in environment

searchpath:
    sub di, di
    xor dx, dx
    mov es, env
nextvar:
    mov SI, offset szPath	; "PATH="
    mov cx, 0005
    repz cmpsb
    jnz @f
    mov dx, di
@@:
    mov al, 00
    or cx, -1
    repnz scasb
    cmp al, es:[di]
    jnz nextvar
    add di, 3               ; so DI points to path of executable now
    mov si, dx
    retn

loadserver endp

