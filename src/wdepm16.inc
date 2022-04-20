
;*** WDe specific protected-mode initialization

RMCS    struct  ; dpmi real-mode call struct
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

IRETS struct    ; structure of registered saved by INT
wIP    dw ?
wCS    dw ?
wFlags dw ?
IRETS ends


    .data

oldint13 dd 0
oldint2f dd 0

    .code

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
    mov [si].DAP.wBufferSeg, DGROUP ; set segment of transfer buffer
is48:
    push di
    sub sp, sizeof RMCS
    mov di, sp
    push ss
    pop es
    mov [di].RMCS.rAX, ax           ; ah=function code, al=write flags
    mov [di].RMCS.rDX, dx           ; dl=drive
    mov [di].RMCS.rSI, si
    mov [di].RMCS.rFlags, 202h
    mov [di].RMCS.rDS, DGROUP       ; request ptr is in DS:SI
    mov [di].RMCS.rSSSP, 0
    push ax
    push bx
    push cx
    mov bx, 0013h
    xor cx, cx
    mov ax, 0300h
    int 31h
    pop cx
    pop bx
    pop ax
    cmp ah, 48h
    jz @F
    mov [si].DAP.wBufferSeg, ds     ; restore transfer buffer (for 42/43)
@@:
    mov al, byte ptr [di].RMCS.rFlags
    mov byte ptr [di+sizeof RMCS+2].IRETS.wFlags, al
    mov ax, [di].RMCS.rAX
    add sp, sizeof RMCS
    pop di
    iret
myint13 endp

;--- translate int 2Fh, ax=1510h (CD-ROM access)
;--- here also the segment part of the transfer buffer is to be set.

myint2f proc
    cmp ax, 1510h
    jz is1510
    jmp dword ptr [oldint2f]
is1510:
    mov [bx].CDREQ.bufseg, DGROUP  ; set transfer buffer segment part
    push di
    sub sp, sizeof RMCS
    mov di, sp
    push ss
    pop es
    mov [di].RMCS.rAX, ax          ; AX=function cod
    mov [di].RMCS.rBX, bx          ; ES:BX -> device driver request
    mov [di].RMCS.rCX, cx          ; CX=drive#
    mov [di].RMCS.rFlags, 202h
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
    mov [bx].CDREQ.bufseg, ds      ; restore selector of transfer buffer
    add sp, sizeof RMCS
    pop di
    iret
myint2f endp

;--- alloc descriptors for _0000H and vidseg

getdescriptors proc

    mov cx, 2       ; alloc 2 descriptors
    xor ax, ax
    int 31h
    jc done
    mov _0000H, ax
    mov bx, ax      ; set bases ( 00000000h, 000Bx000h )
    xor dx, dx
    xor cx, cx
    mov ax, 7
    int 31h
    add bx, 8
    movzx ecx, word ptr [vidaddr+2]
    mov word ptr [vidaddr+2], bx
    shl ecx, 4
    mov dx, cx
    shr ecx, 16
    int 31h
    mov dx, 7fffh   ; set limits to 07FFFh
    xor cx, cx
    mov ax, 8
    int 31h
    sub bx, 8
    int 31h
done:
    ret
getdescriptors endp

;--- WDe protected-mode init
;--- in: DS=SS=DGROUP, ES=PSP, CS=_TEXT

wdepm16 proc
    mov [_psp], es                ; update PSP to a selector
    call getdescriptors           ; get descriptors for _0000H & vidseg
    jc error
if ?VDD
    cmp [hVdd], -1                ; wdevdd.dll can handle protected-mode
    jnz done
endif
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
    mov al, 4
    int 31h
    mov word ptr [oldint2f+0], dx
    mov word ptr [oldint2f+2], cx
    mov cx, cs
    mov dx, offset myint2f
    mov al, 5
    int 31h
done:
    ret
error:
    mov ax,4cffh
    int 21h
wdepm16 endp

