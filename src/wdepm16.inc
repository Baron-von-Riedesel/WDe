
;*** WDe specific protected-mode initialization

;--- the following segments need translation

_0000H   equ 0054h    ; alloc a specific descriptor to get access to segment 0000h
_B000H   equ 005Ch    ; alloc a specific descriptor to get access to segment B000h
if ?VDD
_CSALIAS equ <[csalias]>
endif

;--- dpmi real-mode call struct

RMCS    struct
rDI     dw ?,?
rSI     dw ?,?
rBP     dw ?,?
rRes    dw ?,?
rBX     dw ?,?
rDX     dw ?,?
rCX     dw ?,?
rAX     dw ?,?
rFlags  dw ?
rES     dw ?
rDS     dw ?
rFS     dw ?
rGS     dw ?
rCSIP   dd ?
rSSSP   dd ?
RMCS    ends

    .data

oldint13 dd 0
oldint2f dd 0
if ?VDD
csalias dw 0
endif

    .code

IRETS struct
wIP    dw ?
wCS    dw ?
wFlags dw ?
IRETS ends

;--- int 13h interception
;--- There's no translation for extended int 13h
;--- in hdpmi. The WDe segments are located in conventional memory,
;--- so the only work to do is to set segment register values for DS/ES.

myint13 proc
    cmp ah, 42h
    jz is42
    cmp ah, 43h
    jz is43
    cmp ah, 48h
    jz is48
    jmp dword ptr [oldint13]

is42:
is43:
    mov word ptr [si+6], DGROUP   ; translate transfer buffer selector to segment
is48:
    push di
    sub sp, sizeof RMCS
    mov di, sp
    push ss
    pop es
    mov [di].RMCS.rAX, ax
    mov [di].RMCS.rBX, bx
    mov [di].RMCS.rCX, cx
    mov [di].RMCS.rDX, dx
    mov [di].RMCS.rSI, si
    mov [di].RMCS.rFlags, 302h
    mov [di].RMCS.rDS, DGROUP     ; request is in DS:SI
    mov [di].RMCS.rSSSP, 0
    push ax
    mov bx, 0013h
    xor cx, cx
    mov ax, 0300h
    int 31h
    pop ax
    cmp ax, 48h
    jz @F
    mov word ptr [si+6], ds
@@:
    mov al, byte ptr [di].RMCS.rFlags
    mov byte ptr [di+sizeof RMCS+2].IRETS.wFlags, al
    mov ax, [di].RMCS.rAX
    mov bx, [di].RMCS.rBX
    mov cx, [di].RMCS.rCX
    add sp, sizeof RMCS
    pop di
    iret
myint13 endp

;--- translate int 2Fh, ax=1510h (CD-ROM access)
;--- what has to be done is to set the segment part of the transfer buffer


myint2f proc
    cmp ax, 1510h
    jz is1510
    jmp dword ptr [oldint2f]
is1510:
    mov word ptr [bx+16], DGROUP   ; set transfer buffer segment part
    push di
    sub sp, sizeof RMCS
    mov di, sp
    push ss
    pop es
    mov [di].RMCS.rAX, ax
    mov [di].RMCS.rBX, bx          ; ES:BX -> device driver request
    mov [di].RMCS.rCX, cx          ; cx holds drive
    mov [di].RMCS.rFlags, 302h
    mov [di].RMCS.rES, DGROUP
    mov [di].RMCS.rSSSP, 0
    mov bx, 002Fh
    xor cx, cx
    mov ax, 0300h
    int 31h
    mov al, byte ptr [di].RMCS.rFlags
    mov byte ptr [di+sizeof RMCS+2].IRETS.wFlags, al
    mov ax, [di].RMCS.rAX
    mov bx, [di].RMCS.rBX
    mov cx, [di].RMCS.rCX
    mov word ptr [bx+16], ds       ; restore selector of transfer buffer
    add sp, sizeof RMCS
    pop di
    iret
myint2f endp

;--- alloc descriptors for _0000H, _B000H ( and optionally _CSALIAS )

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

if ?VDD
    mov ax, 000Ah           ; alloc CS alias
    mov bx, cs
    int 31h
    jc done
    mov [csalias], bx
endif
done:
    ret
getdescriptors endp

;--- WDe protected-mode init
;--- in: DS=SS=DGROUP, ES=PSP, CS=_TEXT

wdepm16 proc
    mov [_psp], es                ; update PSP to a selector
    call getdescriptors           ; get descriptors for _0000H, _B800H, _B000H, _CSALIAS
    jc error
    mov bl,13h                    ; intercept int 13h
    mov ax,0204h
    int 31h
    mov word ptr [oldint13+0], dx
    mov word ptr [oldint13+2], cx
    mov cx, cs
    mov dx, offset myint13
    mov al, 5
    int 31h
    mov bl,2Fh                    ; intercept int 2Fh
    mov ax,0204h
    int 31h
    mov word ptr [oldint2f+0], dx
    mov word ptr [oldint2f+2], cx
    mov cx, cs
    mov dx, offset myint2f
    mov al, 5
    int 31h
    ret
error:
    mov ax,4cffh
    int 21h
wdepm16 endp

