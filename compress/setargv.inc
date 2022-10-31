
;--- read the commandline at PSP:81h
;--- and create an argc/argv structure on the stack.
;--- in: ES=FLAT, DS=FLAT, SS=FLAT
;--- out: _argc (=[ebp-4])
;---      _argv (=[ebp-8])
;--- all std registers modified (including ESP)

?DUMMYFN equ 1
?QUOTES  equ 1

_setargv proc

ifndef ?PUREFLAT            ; don't change seg regs ( LOADPE used )
    mov ah, 51h
    int 21h
    mov es, ebx
endif

    mov ebp, esp
    sub esp, 256            ; just make enough room for argc/argv

    xor edi, edi            ; init argc
    xor edx, edx            ; init size of mem block
ifdef ?PUREFLAT
    lea esi, [ebx+81h]
else
    mov esi, 81H
    push es
    pop ds
endif
    jmp scanarg

;--- EDI = argc
;--- EDX = block size (not including null terminators)
nextarg:
    push Ebx                ; save argument size
scanarg:
@@:
    lodsb
    cmp al, ' '
    je @B
    cmp al, 9
    je @B
    cmp al, 13
    jz doneargs             ; exit if eol
    inc edi                 ; another argument
    xor ebx, ebx            ; init argument size
if ?QUOTES
    cmp al, '"'
    jz handle_quote
endif
    dec esi                 ; back up to reload character
    push esi                ; save argument ofs
@@:
    lodsb
    cmp al, ' '             ; end argument?
    je nextarg
    cmp al, 9
    je nextarg              ; white space terminates argument
    cmp al, 13
    jz doneargs2            ; exit if eol
    inc ebx
    inc edx
    jmp @B
if ?QUOTES
handle_quote:
    push esi
@@:
    lodsb
    cmp al, 13
    jz quoteerr
    cmp al, '"'
    jz @F
    inc edx
    inc ebx
    jmp @B
quoteerr:
    dec esi                 ; "unread" the CR
@@:
    jmp nextarg
endif
doneargs2:
    push ebx                ; last argument's size
doneargs:

;--- address & size of arguments are pushed

    mov ecx, edi
    add edx, edi            ; EDX=size arguments + terminator bytes
    inc edi                 ; add one for NULL pointer
if ?DUMMYFN
    inc edi                 ; add one for filename
endif
    shl edi, 2              ; each ofs needs 4 bytes
    add edx, edi            ; EDX=size args + size argv
    add edx, 3
    and edx, -4             ; ensure stack remains dword aligned
    mov eax, [ebp]
    sub ebp, edx            ; alloc the really needed space for argc/argv
    mov [ebp-12], eax       ; store return address

_argc equ <ebp-4>
_argv equ <ebp-8>

    mov [_argv], ebp
    mov [_argc], ecx

    add edi, ebp            ; edi -> behind vector table (strings)
    xor eax, eax
    lea ebx, [edi-4]
ifdef ?PUREFLAT
    mov [ebx], eax          ; terminating 0000 _argv[x]
else
    mov ss:[ebx], eax       ; terminating 0000 _argv[x]
endif
    sub ebx, 4
    jecxz noargs
ifndef ?PUREFLAT
    push ss
    pop es
endif

;--- copy the arguments from PSP onto the stack

    mov edx, ecx
@@:
    pop ecx                 ; size
    pop esi                 ; address
ifdef ?PUREFLAT
    mov [ebx], edi          ; store _argv[x]
else
    mov ss:[ebx], edi       ; store _argv[x]
endif
    sub ebx, 4
    rep movsb
    stosb                   ; AL still 0
    dec edx
    jnz @B

noargs:
ifndef ?PUREFLAT
    push ss
    pop ds
    push ss
    pop es
endif
if ?DUMMYFN
    mov [ebx], eax          ; store 0 as dummy filename
    inc dword ptr [_argc]
endif
    lea esp, [ebp-12]
    ret
_setargv endp

