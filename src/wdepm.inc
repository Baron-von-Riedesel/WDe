
;*** WDe specific protected-mode initialization.
;--- it's mostly to translate int 13h and int 2fh.
;--- also, for NTVDM, the LFN functions must be translated.
;--- translation itself is simple, since WDe runs in
;--- conventional memory, no copy operations are needed.

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

if ?32BIT

    .486        ; make jwasm generate "MOV SP, BP" "POP BP" instead of LEAVE in procs
IRETS struct    ; IRETD struct on stack in INT
wIP    dd ?
wCS    dd ?
wFlags dd ?
IRETS ends

@fp     equ <df>
@iret   equ <iretd>

@movr macro dst, src
	mov e&dst, e&src
endm
@storevec macro addr
	mov dword ptr addr[0], edx
	mov word ptr addr[4], cx
endm
@loadvec macro addr
	mov edx, dword ptr addr[0]
	mov cx, word ptr addr[4]
endm
@movofs macro dst, src
	mov e&dst, src
endm

else

IRETS struct    ; IRETW struct on stack in INT
wIP    dw ?
wCS    dw ?
wFlags dw ?
IRETS ends

@fp     equ <dd>
@iret   equ <iret>

@movr macro dst, src
	mov dst, src
endm
@storevec macro addr
	mov word ptr addr[0], dx
	mov word ptr addr[2], cx
endm
@loadvec macro addr
	mov dx, word ptr addr[0]
	mov cx, word ptr addr[2]
endm
@movofs macro dst, src
	mov dst, src
endm

endif


    .data

oldint13 @fp 0
oldint2f @fp 0
oldint21 @fp 0

    .code

;--- int 13h interception.
;--- There's usually no translation for extended int 13h in DPMI hosts.
;--- ah=42h/43h have a far16 buffer address in their "request package"
;--- that must be converted. Since WDE runs in small memory model,
;--- there's only one data segment: DGROUP.

myint13 proc
    cmp ah, 42h
    jz is42
    cmp ah, 43h
    jz is43
    cmp ah, 48h
    jz is48
    jmp [oldint13]
is42:
is43:
    mov [si].DAP.wBufferSeg, DGROUP ; set segment of transfer buffer
is48:
    pushd 0
    sub sp, sizeof RMCS-(32+4+2)
    pushf
    pushad
    @movr di, sp
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
    @iret
myint13 endp

;--- int 21h interception

myint21 proc
    cmp ax, 7305h
    jz is7305
 if ?LFN
    cmp ah, 71h
    jz is71
 endif
 if ?TR217302
    cmp ax, 7302h
    jz is7302
 endif
 if ?32BIT
    cmp ah, 4Ch
    jnz is71
 endif
    jmp [oldint21]
is7305:
    mov [bx].DISKIO.buffseg, DGROUP  ; set segment of buffer
is71:
is7302:
    pushd 0
    sub sp, sizeof RMCS - (32+4+2)
    pushf
    pushad
    @movr di, sp
    push ss
    pop es
    mov [di].RMCS.rES, DGROUP
    mov [di].RMCS.rDS, DGROUP
    mov bx, 0021h
    xor cx, cx
    push ax
    mov ax, 0300h
    int 31h
    mov al, byte ptr [di].RMCS.rFlags
    mov byte ptr [di+sizeof RMCS].IRETS.wFlags, al
    pop ax
    cmp ax, 7305h
    popad
    jnz @F
    mov [bx].DISKIO.buffseg, ds
@@:
    add sp, sizeof RMCS-32
    @iret
myint21 endp

;--- translate int 2Fh, ax=1510h (CD-ROM access)
;--- here also the segment part of the transfer buffer is to be set.

myint2f proc
    cmp ax, 1510h
    jz is1510
    jmp [oldint2f]
is1510:
    mov [bx].CDREQ.bufseg, DGROUP  ; set transfer buffer segment part
    pushd 0
    sub sp, sizeof RMCS-(32+4+2)
    pushf
    pushad
    @movr di, sp
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
    @iret
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

wdepm proc
    mov [_psp], es                ; update PSP to a selector
    call getdescriptors           ; get descriptors for _0000H & vidseg
    jc error
if ?VDD
    cmp [hVdd], -1                ; wdevdd.dll can handle protected-mode
    jnz skip132f
endif
    mov bl, 13h                   ; intercept int 13h
    mov ax, 204h
    int 31h
    @storevec [oldint13]
    mov cx, cs
    @movofs dx, myint13
    mov al, 5
    int 31h

    mov bl, 2Fh                   ; intercept int 2Fh
    mov al, 4
    int 31h
    @storevec [oldint2f]
    mov cx, cs
    @movofs dx, myint2f
    mov al, 5
    int 31h
skip132f:
    mov bl, 21h                   ; intercept int 21h
    mov ax, 204h
    int 31h
    @storevec [oldint21]
    mov cx, cs
    @movofs dx, myint21
    mov al, 5
    int 31h
done:
    ret
error:
    mov ax,4cffh
    int 21h
wdepm endp

