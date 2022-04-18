
;--- include to make WDE compatible with Windows NT/XP
;--- copyright japheth 2010
;--- Released under GNU GPL 2 license.

RegisterModule macro
    db 0C4h, 0C4h, 58h, 0
    endm
UnRegisterModule macro
    db 0C4h, 0C4h, 58h, 1
    endm
Dispatch macro
    db 0C4h, 0C4h, 58h, 2
    endm

;--- display string on the windows debug terminal.
;--- this works only if running in a WinXP/Vista DOS-Box.
@DbgOut macro text:vararg
local xxx
ifdef _DEBUG
    call dbgout
    jmp xxx
    db text,0
xxx:
endif
endm

@int13 equ <call int13>
@int21 equ <call int21>
@int25 equ <call int25>
@int26 equ <call int26>
@int2F equ <call int2F>

    .data

hVdd dw -1

    .code

int13:
    int 13h
    ret
    mov ax, [hVdd]
    Dispatch
    ret
int21:
    int 21h
    ret
    mov ax, [hVdd]
    Dispatch
    ret
int25:
    int 25h
    pop dx
    ret
    mov ax, [hVdd]
    Dispatch
    ret
int26:
    int 26h
    pop dx
    ret
    mov ax, [hVdd]
    Dispatch
    ret
int2F:
    int 2fh
    ret
    mov ax, [hVdd]
    Dispatch
    ret


initvdd proc
    mov ax, 3306h
    int 21h
    cmp bx, 3205h
    jnz @F
    mov si, CStr("wdevdd.dll")
    mov bx, CStr("Dispatch")     ; DS:BX->"Dispatch"
    mov di, CStr("Init")         ; ES:DI->"Init"
    push ds
    pop es
    RegisterModule
    jc @F
    cmp ax, -1
    jz @F
    push ds
    mov [hVdd], ax
    push _CSALIAS
    pop ds
    assume ds:_TEXT
    mov ax, 06A50h               ; push AX, push XX
    mov cx, 9021h                ; push XX, nop
    mov word ptr [int21+0], ax
    mov byte ptr [int21+2], cl
    mov cl, 25h
    mov word ptr [int25+0], ax
    mov word ptr [int25+2], cx
    mov cl, 26h
    mov word ptr [int26+0], ax
    mov word ptr [int26+2], cx
    mov cl, 2Fh
    mov word ptr [int2F+0], ax
    mov byte ptr [int2F+2], cl
ifdef _DEBUG
    mov byte ptr [dbgout], ch    ; nop
endif
    pop ds
    assume ds:DGROUP
@@:
    ret
initvdd endp

exitvdd proc
    mov ax, -1
    xchg ax, [hVdd]
    cmp ax, -1
    jz @F
    UnRegisterModule
@@:
    ret
exitvdd endp

ifdef _DEBUG
dbgout proc
    ret                          ; location will be patched with NOP if VDD found
    push ax
    push 41h
    mov ax, [hVdd]
    Dispatch
    ret
dbgout endp
endif
