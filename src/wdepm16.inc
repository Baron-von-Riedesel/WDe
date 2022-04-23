
;*** WDe specific protected-mode initialization

?TR217302 equ 1 ; 1=translate int 21h, ax=7302h ( for NTVDM only )

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
if ?TR217302 or ?LFN
oldint21 dd 0
endif

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
    pushd 0
    sub sp, sizeof RMCS-(32+4+2)
    pushf
    pushad
    mov di, sp
    push ss
    pop es
    mov [di].RMCS.rDS, DGROUP       ; request ptr is in DS:SI
    push ax
    mov bx, 0013h
    xor cx, cx
    mov ax, 0300h
    int 31h
    pop ax
    cmp ah, 48h
    jz @F
    mov [si].DAP.wBufferSeg, ds     ; restore transfer buffer (for 42/43)
@@:
    mov al, byte ptr [di].RMCS.rFlags
    mov byte ptr [di+sizeof RMCS].IRETS.wFlags, al
    popad
    add sp, sizeof RMCS-32
    iret
myint13 endp

if ?TR217302 or ?LFN
myint21 proc
 if ?LFN
    cmp ah, 71h
    jz is71
 endif
 if ?TR217302
    cmp ax, 7302h
    jz is7302
 endif
    jmp dword ptr [oldint21]
is71:
is7302:
    pushd 0
    sub sp, sizeof RMCS - (32+4+2)
    pushf
    pushad
    mov di, sp
    push ss
    pop es
    mov [di].RMCS.rES, DGROUP
    mov [di].RMCS.rDS, DGROUP
    mov bx, 0021h
    xor cx, cx
    mov ax, 0300h
    int 31h
    mov al, byte ptr [di].RMCS.rFlags
    mov byte ptr [di+sizeof RMCS].IRETS.wFlags, al
    popad
    add sp, sizeof RMCS-32
    iret
myint21 endp

endif

;--- translate int 2Fh, ax=1510h (CD-ROM access)
;--- here also the segment part of the transfer buffer is to be set.

myint2f proc
    cmp ax, 1510h
    jz is1510
    jmp dword ptr [oldint2f]
is1510:
    mov [bx].CDREQ.bufseg, DGROUP  ; set transfer buffer segment part
    pushd 0
    sub sp, sizeof RMCS-(32+4+2)
    pushf
    pushad
    mov di, sp
    push ss
    pop es
    mov [di].RMCS.rES, DGROUP
    mov bx, 002Fh
    xor cx, cx
    mov ax, 0300h
    int 31h
    mov al, byte ptr [di].RMCS.rFlags
    mov byte ptr [di+sizeof RMCS].IRETS.wFlags, al
    popad
    add sp, sizeof RMCS-32
    mov [bx].CDREQ.bufseg, ds      ; restore selector of transfer buffer
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
    jnz skip132f
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
skip132f:
if ?TR217302 or ?LFN
    mov ax, 3306h                 ; running in NTVDM?
    int 21h
    cmp bx, 3205h
    jnz @F
    mov bl,21h                    ; intercept int 21h
    mov al, 4
    int 31h
    mov word ptr [oldint21+0], dx
    mov word ptr [oldint21+2], cx
    mov cx, cs
    mov dx, offset myint21
    mov al, 5
    int 31h
@@:
endif
done:
    ret
error:
    mov ax,4cffh
    int 21h
wdepm16 endp

