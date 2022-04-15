
;--- simple sprintf() implementation

;--- ltob(long n, char * s, int base);
;--- convert long to string

ltob PROC stdcall uses bx di number:dword, outb:word, base:word

    mov ch,0
    movzx edi, base
    mov eax, number
    cmp di,-10
    jne @F
    mov di,10
    and eax,eax
    jns @F
    neg eax
    mov ch,'-'
@@:
    mov bx,outb
    add bx,10
    mov BYTE PTR [bx],0
    dec bx
@@nextdigit:
    xor edx, edx
    div edi
    add dl,'0'
    cmp dl,'9'
    jbe @F
    add dl,7+20h
@@:
    mov [bx],dl
    dec bx
    and eax, eax
    jne @@nextdigit
    cmp ch,0
    je @F
    mov [bx],ch
    dec bx
@@:
    inc bx
    mov ax,bx
    ret

ltob ENDP

;--- ds=ss=dgroup

sprintf PROC c buffer:ptr byte, fmt:ptr byte, args:VARARG

local size_:word
local flag:byte
local longarg:byte
local fill:byte
local szTmp[12]:byte

    pushad
    push ds
    pop es
    lea bx, [fmt+2]
    mov di, buffer
reloadfmt:
    mov si,[fmt]
nextchar:
    lodsb
    cmp al,'%'
    je formatitem
done:
    stosb
    or al, al
    jne nextchar
    popad
    ret

formatitem:
    push reloadfmt
    mov al, 1
    mov cl,' '
    cmp BYTE PTR [si],'-'
    jne @F
    mov al, 0
    inc si
@@:
    mov [flag], al
    cmp BYTE PTR [si], '0'
    jne @F
    mov cl,'0'
    inc si
@@:
    mov [fill],cl
    xor dx, dx
    jmp chkdigit
nextdigit:
    sub al,'0'
    cbw
    imul dx,dx,10       ;dx = dx * 10
    add dx,ax
chkdigit:
    lodsb
    cmp al,'0'
    jb @F
    cmp al,'9'
    jbe nextdigit
@@:
    mov [size_], dx

    cmp al, 'l'
    sete [longarg]
    je @F
    dec si
@@:
    lodsb
    mov [fmt], si
    cmp al,'x'
    je handle_x
    cmp al,'X'
    je handle_x
    cmp al,'c'
    je handle_c
    cmp al,'d'
    je handle_d
    cmp al,'i'
    je handle_i
    cmp al,'s'
    je handle_s
    cmp al,'u'
    je handle_u
    cmp al,0
    jnz storeal
    pop cx
    jmp done
handle_c:
    mov ax, [bx]
    add bx, 2
storeal:
    stosb
    retn

handle_x:
    mov cx, 16
    jmp @@lprt262
handle_d:
handle_i:
    mov cx, -10
    jmp @@lprt262
handle_u:
    mov cx, 10
@@lprt262:
    mov eax, [bx]
    add bx, 4
    cmp [longarg], 1
    je @F
    sub bx, 2
    movzx eax, ax
    and cx, cx      ;signed or unsigned?
    jge @F
    movsx eax, ax
@@:
    lea dx, [szTmp]
    invoke ltob, eax, dx, cx
    mov si, ax
    call output_string
    retn

handle_s:
    mov si, [bx]
    add bx, 2

output_string:  ;display string at si
    mov dx, si
    mov cx, size_
@@:
    lodsb
    cmp al, 0
    jnz @B
    dec si
    sub si, dx
    mov al, [fill]
    xchg dx, si    ;restore si, dx=size of string
    sub cx, dx
    jnc @F
    xor cx, cx
@@:
    cmp [flag], 1
    jnz @F
    rep stosb
@@:
    push cx
    mov cx, dx
    rep movsb
    pop cx
    rep stosb
    retn

sprintf ENDP

