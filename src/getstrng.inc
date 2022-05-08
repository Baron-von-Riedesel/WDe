
;--- reads in a string from keyboard

GS_ESCAPE    equ 1
GS_EXIT      equ 2

CSRPOS struct
col db ?
row db ?
CSRPOS ends

VPAGE equ <[vidpg]>

    .code

getkbdstatus proc
    push ds
    push _0000H
    pop ds
    mov ah, ds:[417h]
    pop ds
    ret
getkbdstatus endp

;--- pBuffer:  buffer for string to store
;--- wSizeBuf: size of buffer
;--- wCursor:  cursor offset on entry; -1 = no positioning
;--- wChars:   max chars to display
;--- out: ax = chars in buffer
;---      dx = current cursor offset

getstring proc stdcall uses bx si di pBuffer:ptr, wSizeBuf:word, wCursor:word, wChars:word, tabproc:ptr

local   flags:word     ; bool: escape (terminate without update)
local   strsta:word    ; string start offset
local   lastkey:word
local   csrsta:CSRPOS  ; start cursor position

    mov cx, wSizeBuf
    sub sp, cx
    mov di, sp            ; di -> current char
    mov strsta, di
    mov si, pBuffer
    xor cx, cx
    dec cx
    push ds
    pop es
@@:
    lodsb
    stosb
    inc cx
    and al, al
    jnz @B

    xor ax, ax
    mov flags, ax
    mov ax, cx            ; string length -> ax
    mov cx, wSizeBuf      ; string is temporary
    mov di, strsta

    mov ax, wCursor       ; cursor offset
    mov dx, [scrn_xy]
    sub dl, al
    mov csrsta, dx

    mov si, di
    add di, ax            ; current pointer
    sub cx, ax            ; wSizeBuf - cursor
    jbe strex

wingx:                    ; <---- get next key

;--- check if di - si is < wChars
;--- if no, adjust si :

    mov dx, wChars
    mov ax, di            ; current offset -> ax
    sub ax, si
    jnc @F
    mov si, di
    xor ax, ax
@@:
    cmp ax, dx
    jb @F
    mov si, di
    sub si, dx
    inc si
@@:
    push csrsta
    pop [scrn_xy]
    call str_out          ; display string

    mov ax, di
    sub ax, si
    mov dx, [csrsta]
    add dl, al
    mov [scrn_xy], dx
    call cursorgetkey

    mov dx, ax
    mov lastkey, ax
    mov ah,byte ptr lastkey+1   ; scancode is in bits 8-15
    call chkctl
    xor ax, ax                        ; exit "no chars entered"
    test byte ptr flags, GS_ESCAPE    ; escape pressed?
    jnz str_1
    test byte ptr flags, GS_EXIT
    jz wingx                          ; get next key
    push ds
    pop es
    mov si, strsta
    mov di, pBuffer
@@:
    lodsb
    stosb
    and al,al
    jnz @B
    mov ax, di
    dec ax
    sub ax, pBuffer
str_1:
    add sp, wSizeBuf
strex:
    mov dx, wSizeBuf
    sub dx, cx
    ret

chkctl:
    and al, al                      ; ctrl key?
    jz chkctl2
    cmp al, 0E0h
    jz chkctl2
    cmp al, 8                       ; BS?
    jnz @F
    call bsv
    retn
smexit:
    or byte ptr flags, GS_EXIT
    retn
@@:
    cmp al, 09                      ; TAB?
    jz handle_tab
    cmp al, 13
    jz smexit
    cmp al, 10
    jz smexit
    cmp al, 1bh                     ; ESC?
    jnz @F
    or byte ptr flags, GS_ESCAPE
    retn
@@:
    cmp al,20h                      ; exit on all ctrl codes?
    jb _ret ; smexit                ; no!

    call getkbdstatus
    test ah, 80h
    jz @F
    call insert
    and al, al
    jnz chkm3
    retn
@@:
    mov ah, [di]
    mov [di], al
    and ah, ah                      ; was cursor at eol?
    jnz @F
    cmp cx, 2
    jb @F
    mov byte ptr [di+1], 0          ; mark new eol
@@:
chkm3:
    inc di                          ; "cursor" right
    dec cx
    cmp cx, 1                       ; end reached?
    ja @F
    call ringbell
    dec di
    inc cx
@@:
    retn

handle_tab:
;--- tabproc is called with ax=strsta, di=curpos, cx=remaining
    mov ax, strsta
    call tabproc
    jc smexit
    and ax, ax
    jnz _ret
if 1
    mov cl, 79
    sub cl, [scrn_col]
    mov al, SPACE
    call fillchar
endif
    mov di, strsta                  ; set cursor to pos 0
    mov cx, wSizeBuf
    mov si, di
    retn

chkctl2:                            ; ctrl key entered ( ascii 00 or 0E0 )
    mov bx, offset ctlkeytab
    mov dl, lctlkeytab
@@:
    cmp ah, cs:[bx]
    jz ctlfound
    inc bx
    dec dl
    jnz @B
    retn
ctlfound:
    sub bx, offset ctlkeytab
    shl bx, 1
    jmp word ptr cs:[bx+ctlkeyjmptab]

ctlkeytab label byte
    db CSRLEFT_KEY
    db HOME_KEY
    db END_KEY
    db CSRRIGHT_KEY
    db DEL_KEY
lctlkeytab equ $ - ctlkeytab

    align 2

ctlkeyjmptab label word
    dw offset cursleft
    dw offset curshome
    dw offset cursend
    dw offset cursright
    dw offset delkey

;*** subroutines (ctrl keys)

curshome:
    call cursleft
    jnz curshome
_ret:
    retn
cursend:
    call cursright
    jnc cursend
    retn

;--- parms: cx=remainder length
;---        si -> string

str_out:
    pusha
    mov cx, wChars
@@:
    lodsb
    and al, al
    jz @F
    mov dl, al
    call printchar
    loop @B
@@:
    mov dl, ' '
    call printchar
    popa
    retn

cursleft:
    cmp cx, wSizeBuf
    jz _ret
    inc cx
    dec di
    retn

cursright:
    cmp cx, 2
    jna @F
    cmp byte ptr [di], 00
    jz  @F
    dec cx
    inc di
    retn
@@:
    stc
    retn

delkey:
    cmp byte ptr [di], 00
    jz _ret
    inc di
    jmp bsv3

bsv:                            ; handle backspace
    cmp cx, wSizeBuf
    jz _ret                     ; cursor at start?
    inc cx
    mov ax, di
    dec ax
bsv3:
    push si
    mov si, di
    dec di
    push di
    push ds
    pop es
@@:
    lodsb
    stosb
    and al, al
    jnz @B
    pop di
    pop si
    retn

insert:                        ; insert mode
    push ax
    push di
    mov dx, cx
    push ds
    pop es

    mov cx,-1
    xor al,al
    repnz scasb
    neg cx
    dec cx
    mov ax, dx
    sub ax, wSizeBuf
    neg ax
    add ax, cx
    cmp ax, wSizeBuf
    jnb ins1

    push si
    mov si, di
    dec si
    std
    rep movsb                 ; make room
    cld
    mov cx, dx
    pop si

    pop di
    pop ax
    mov [di],al
    mov al,-1
    retn
ins1:                         ; error insert
    mov cx, dx                ; restore CX
    push cx
    call ringbell
    pop cx
    pop di
    pop ax
    xor al,al
    retn

ringbell:
    mov ax, 0e07h
    int 10
    retn

getstring endp

