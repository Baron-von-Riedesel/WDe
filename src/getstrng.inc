
;--- old code from the 90ies - revived and changed to 16-bit.
;--- reads in a string from keyboard


GS_ESCAPE    equ 1
GS_EXIT      equ 2
GS_BSOUT     equ 4

    .code

getinsertstatus proc
    push ds
    push _0000H
    pop ds
    mov al,ds:[417h]
    and al,80h
    pop ds
    ret
getinsertstatus endp

;--- pBuffer: buffer for string to store
;--- wSizeBuf: size of buffer
;--- wCursor: cursor offset on entry; -1 = no positioning
;--- out: ax = chars in buffer
;---      dx = current cursor offset

getstring proc stdcall uses bx si di pBuffer:ptr, wSizeBuf:word, wCursor:word

local   insrst:word    ;insert status
local   flags:word     ;bool: escape (terminate without update)
local   curspos:word   ;cursor position
local   strsta:word    ;string start
local   lastkey:word
local   oldscrn:word

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

    mov ax, [scrn_xy]
    mov oldscrn, ax
    mov curspos, ax

    mov ax, wCursor       ; cursor offset
    mov si, di
    add di, ax            ; current pointer
    sub cx, ax            ; wSizeBuf - cursor
    jbe strex

    push cx
    add cx, ax
    call str_out          ; display string
    call getinsertstatus
    mov insrst, ax
    pop cx

wingx:                    ; <---- get next key
    push cx               ; cx = max remainder
    mov cx,curspos        ; position begin of input
    movzx dx, cl          ; col -> dx
    shr cx, 8             ; row -> cx
    mov ax, di            ; current offset -> ax
    sub ax, strsta
    add dx, ax
    mov [scrn_col], dl
    mov [scrn_row], cl

    call cursorgetkey
    mov dx, ax
    mov lastkey, ax
    mov ah,byte ptr lastkey+1   ; scancode is in bits 8-15
    pop cx
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
    mov dx, oldscrn
    mov [scrn_xy], dx
    mov dx, cx
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

    mov ah,byte ptr insrst          ; insert on?
    test ah,1
    jz @F
    call insert
    and al,al
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
    call printchar                  ; print echo
chkm3:
    inc di                          ; "cursor" right
    dec cx
    cmp cx, 1                       ; end reached?
    ja @F
;    or byte ptr flags, GS_EXIT
;    mov word ptr lastkey, 0         ; if no, auto terminate
    mov ax, 0e07h
    int 10h
    dec di
    inc cx
@@:
    retn
handle_tab:
    xor al, al
    xchg al, [bTabSw]
    cmp al, 1
    jz smexit
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
    db INS_KEY
    db CSRLEFT_KEY
    db HOME_KEY
    db END_KEY
    db CSRRIGHT_KEY
    db DEL_KEY
lctlkeytab equ $ - ctlkeytab

    align 2

ctlkeyjmptab label word
    dw offset inskey
    dw offset cursleft
    dw offset curshome
    dw offset cursend
    dw offset cursright
    dw offset delkey

;*** subroutines (ctrl keys)

inskey:
    xor byte ptr insrst,01h
_ret:
    retn
curshome:
    call cursleft
    jnz curshome
    retn
cursend:
    call cursright
    jnc cursend
    retn

;--- parms: cx=remainder length
;---        si -> string

str_out:
    pusha
    push [scrn_xy]
@@:
    lodsb
    and al, al
    jz @F
    mov dl, al
    call printchar
    jmp @B
@@:
    test byte ptr flags,GS_BSOUT ; clear EOL?
    jz @F
    mov dl, ' '
    call printchar
@@:
    pop [scrn_xy]
    popa
    retn

cursleft:
    cmp cx, wSizeBuf
    jz _ret
    inc cx
    dec di
    retn
delkey:
    cmp byte ptr [di], 00
    jz _ret
    inc di
    jmp bsv3
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
bsv:                            ; handle backspace
    cmp cx, wSizeBuf
    jz _ret                     ; cursor at start?
    inc cx
    mov ax, di
    dec ax
    sub ax, strsta
    mov dx, curspos
    add dx, ax

    dec [scrn_col]

bsv3:
    or byte ptr flags, GS_BSOUT
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
    mov si, di                 ; refresh from cursor to end
    call str_out
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
    mov si, di
    dec si
    std
    rep movsb                 ; make room
    cld
    mov cx, dx
    pop di
    pop ax
    mov [di],al
    inc si

    call str_out              ; row from cursor+1 refresh
    mov al,-1
    retn
ins1:                         ; error insert
    mov cx, dx                ; restore CX
    push cx
if 1
    mov ax, 0e07h
    int 10h
endif
    pop cx
    pop di
    pop ax
    xor al,al
    retn

getstring endp

