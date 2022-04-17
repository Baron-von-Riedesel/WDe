;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux
;
;-------------------------------------------------------

;--- entered with spot on a (deleted) directory entry

undelete proc
    mov [fromfat], 1
    call spot2bufofs                      ; bx = spot + bufofs
    and bl, 11100000b                     ; bx = start directory entry
    add bx, offset sectbuffer
    mov eax, dword ptr [bx+DIR_FILESIZE]
    mov [dwFilesize], eax
    mov ax, word ptr [bx+DIR_CLUST_HIGH]  ; get start cluster (high 16-bits)
    shl eax, 16
    mov ax, word ptr [bx+DIR_CLUST_LOW]   ; get start cluster (low 16-bits)
; bounds check
    cmp eax, 2
    jb invclust                           ; not a valid cluster if it's below 2
    mov [dwCluster], eax
    call getfatentry
    jc undelete_err1                      ; "file chain exceeds FAT"?
    jmp filenoexceed
invclust:
    mov dx, offset invalstartclust        ; "invalid start cluster"
    call printerror
    ret
filenoexceed:
    test eax, eax                         ; is the returned cluster# 0?
    jz undel1good

;--- this error may also occur if one has manually edited the first byte
;--- of a directory entry to 0E5h. 

    mov dx, CStr('File Too Corrupt')
    call printerror
    ret

undel1good:

    mov dx, CStr('New First Character: ')
    call printbottom

getkeyagain16:

    call cursorgetkey
    cmp al, ESCAPE_KEY
    je done

    call validfileinputchar
    jc getkeyagain16

    cmp al, 'a'
    jb unok1
    cmp al, 'z'
    ja unok1
    sub al, 32
unok1:
;    call spot2bufofs                   ; should be preserved from above
;    and bl, 11100000b
;    add bx, offset sectbuffer
    mov byte ptr [bx], al
    call writesect

    mov dx, CStr('UnDeleting...')
    call printbottom

    call UndeleteCore
    jc undelete_err1
    mov dx, CStr('Finished UnDeleting File')
    call printerror
done:
    ret
undelete_err1:
    mov dx, CStr('File Chain Exceeds FAT')
    call printerror
    ret
undelete endp

;--------------------------------------------------------
;--- in: [dwFilesize] - size of file to undelete)
;---     [dwCluster]  - cluster to work from

UndeleteCore proc
    pushad
undelLoop:
    mov eax, [dwBpc]                    ; bytes per cluster
    mov ebx, [dwCluster]
    cmp [dwFilesize], eax               ; less than bytes per cluster left?
    jbe writeeof                        ; yes, write end of file in
    sub [dwFilesize], eax               ; no, subtract bpc
getnextentry:
    inc ebx
    mov eax, ebx
    call getfatentry
    jc undelCoreError
    test eax, eax
    jnz getnextentry

    mov eax, ebx
    xchg ebx, [dwCluster]
    call putfatentry
    jmp undelLoop
writeeof:
    mov eax, 0FFFFFFFh
    call putfatentry
undelCoreError:
    popad
    ret
UndeleteCore endp

;-------------------------------------------------------
