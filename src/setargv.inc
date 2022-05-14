
;--- ES=PSP, DS=DGROUP, SS=DGROUP
;--- after this function returns,
;--- argc is at [bp+0], argv at [bp+2]

_setargv proc

    pop ax
    sub sp, 128+32
    mov bp, sp
    sub sp, 4

_argc equ <word ptr bp-2>
_argv equ <word ptr bp-4>

    push ax
    xor ax,ax
    push ax                 ; save "filename" address
    xor di,di               ; init argc
    xor dx,dx               ; init size of mem block
    mov si,81H
    push es
    pop ds
    assume ds:nothing
    jmp scanarg

;--- DI = argc
;--- DX = block size (not including null terminators)
nextarg:
    push bx
scanarg:
@@:
    lodsb
    cmp al,' '
    je @B
    cmp al,9
    je @B
    cmp al,13
    jz doneargs             ; exit if eol
    inc di                  ; another argument
    mov bx,0                ; init argument size
    dec si                  ; back up to reload character
    push si                 ; save start of argument
@@:
    lodsb
    cmp al,' '              ; end argument?
    je nextarg
    cmp al,9
    je nextarg              ; white space terminates argument
    cmp al,13
    jz @F                   ; exit if eol
    inc bx
    inc dx
    jmp @B
@@:
    push bx                 ; last argument
doneargs:
;--- address & size of arguments are pushed
    push ss
    pop ds                  ; DS = DGROUP
    assume  ds:DGROUP
    mov [_argc], di         ; Store number of arguments
    add dx, di              ; add in terminator bytes
    inc di                  ; add one for NULL pointer
    inc di                  ; add one for filename
    shl di,1                ; each pointer needs 2 bytes
    add dx,di               ; add space for pointers to space for chars
    mov ax, bp
    mov [_argv],ax
    mov cx,[_argc]
    add di,ax               ; di -> behind vector table (strings)
    lea bx,[di-2]
    mov word ptr [bx],0000
    sub bx,2
    jcxz noargs

    push bp
    mov bp,sp
    add bp,2
    push es
    pop ds
    push ss
    pop es
    assume ds:nothing
@@:
    push cx
    mov cx,[bp+0]           ; size
    mov si,[bp+2]           ; address
    add bp,4
    mov ss:[bx],di
    sub bx,2
    rep movsb
    xor al,al
    stosb
    pop cx
    loop @B
    push ss
    pop ds
    assume ds:DGROUP
    pop bp

noargs:
    mov ax,[_argc]
    add ax,ax
    add ax,ax
    add sp,ax
    pop ax
    mov [bx],ax         ; store address filename as first item
    inc [_argc]
    ret
_setargv endp

