
;--- definitions for debug version

;--- get (start) time in ms

@getstarttime macro
if ?DEBUG
    pushad
    call gettimer
    mov starttime, eax
    popad
endif
endm

;--- print measured time in menu row

@dprinttime macro formstr 
if ?DEBUG
    pushf
    pushad
    call gettimer
    sub eax, starttime
    sub sp, 80
    mov dx, sp
    invoke sprintf, dx, CStr(formstr), eax
    call printerror
    add sp, 80
    popad
    popf
endif
endm

if ?DEBUG

_BSS segment
dbgbuff db 80 dup (?)
_BSS ends

_dbgout proc
    push dx
    push ax
    mov dx, offset dbgbuff
if ?VDD
    cmp [hVdd],-1
    jz @F
    push 41h
    mov ax, [hVdd]
    Dispatch
    jmp done ; note that the VDD has restored AX already
@@:
endif
    mov ah,9
    int 21h
    pop ax
done:
    pop dx
    ret
_dbgout endp

endif

;--- print a line on stdout/debug terminal if ?DEBUG=1

@dprintfln macro formstr, args:vararg 
if ?DEBUG
    pushf
 ifb <args>
    invoke sprintf, offset dbgbuff, CStr(formstr,13,10,'$')
 else
    invoke sprintf, offset dbgbuff, CStr(formstr,13,10,'$'), args
 endif
    call _dbgout
    popf
endif
endm

@dprintduration macro prefix
if ?DEBUG
    pushf
    push eax
    call gettimer
    sub eax, starttime
    invoke sprintf, offset dbgbuff, CStr( prefix, ": %u ms",13,10,'$'), eax
    pop eax
    call _dbgout
    popf
endif
endm

