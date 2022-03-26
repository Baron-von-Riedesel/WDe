
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

CallInt macro intno
    cmp [hVdd],-1
    jnz @F
    int intno
if intno eq 25h
    pop dx
elseif intno eq 26h
    pop dx
endif
    ret
@@:
    push ax
    push intno
    mov ax,[hVdd]
    Dispatch
    ret
endm

	.data

hVdd dw -1

	.code

int13:
    CallInt 13h
int21:
    CallInt 21h
int25:
    CallInt 25h
int26:
    CallInt 26h
int2F:
    CallInt 2Fh


initvdd proc
    mov ax,3306h
    int 21h
    cmp bx,3205h
    jnz @F
    mov si,CStr("wdevdd.dll")
    mov bx,CStr("Dispatch")     ;DS:BX->"Dispatch"
    mov di,CStr("Init")         ;ES:DI->"Init"
    push ds
    pop es
    RegisterModule
    jc @F
    mov [hVdd], ax
@@:
ifdef _DEBUG
    cmp [hVdd],-1
    jnz @F
    mov byte ptr [dbgout], 0C3h  ;opcode for RET
@@:
endif
    ret
initvdd endp

exitvdd proc
    mov ax,-1
    xchg ax,[hVdd]
    cmp ax,-1
    jz @F
    UnRegisterModule
@@:
    ret
exitvdd endp

ifdef _DEBUG
dbgout proc
    push ax		;location will be patched if VDD not found
    push 41h
    mov ax,[hVdd]
    Dispatch
    ret
dbgout endp
endif

