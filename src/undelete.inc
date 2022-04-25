;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux
;
;-------------------------------------------------------

;--- entered with spot on a (deleted) directory entry;
;--- will never get called if file system is exFAT.
;--- problems:
;--- 1. only fat1 is updated
;--- 2. free entries in the FAT are modified, unfree entries
;---    are skipped. This strategy is not convincing.
;--- 3. [fixed in v0.50] if the free clusters in the FAT aren't
;---    sufficient, the changes aren't undone, leaving
;---    the FAT in bad shape.

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
;--- bounds check
    cmp eax, 2
    jb invclust                           ; not a valid cluster if it's below 2
    mov [dwCluster], eax
    call getfatentry
    jc invclust
    test eax, eax                         ; is the returned cluster# 0?
    jz undel1good

;--- error "File too corrupt" may also occur if one has manually edited the first byte
;--- of a directory entry to 0E5h. 

    mov dx, CStr('File Too Corrupt')
    call printerror
    ret
invclust:
    mov dx, offset invalstartclust        ; "invalid start cluster"
    call printerror
    ret

undel1good:
    mov dx, CStr('New First Character: ')
    call printbottom
getkeyagain16:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je done
ife ?LFN
    call validfileinputchar
    jc getkeyagain16
    cmp al, 'a'
    jb unok1
    cmp al, 'z'
    ja unok1
    sub al, 32
unok1:
else
    call validfirstfilechar
    jc getkeyagain16
endif
;    call spot2bufofs                   ; should be preserved from above
;    and bl, 11100000b
;    add bx, offset sectbuffer
    push ax
;    mov byte ptr [bx], al

    mov dx, CStr('UnDeleting...')
    call printbottom

;--- UndeleteCore modifies the FAT, but...
;--- currently only the first FAT!

    call UndeleteCore
    pop ax
    jc undelete_err1

    mov [bx], al
    mov eax, [dwCurSector]
    mov [ioreq.dwSector], eax
    call writesect                      ; rewrite directory sector

    mov dx, CStr('Finished UnDeleting File')
    call printerror
done:
    ret
undelete_err1:

;--- since v0.50, error "file chain exceeds FAT" is harmless, since
;--- the FAT hasn't been modified yet.

    mov dx, CStr('File Chain Exceeds FAT')
    call printerror
    ret
undelete endp

;--------------------------------------------------------
;--- in: [dwFilesize] - size of file to undelete)
;---     [dwCluster]  - cluster to work from
;---
;--- since v0.50, the FAT scan is done twice:
;--- First is without updates to the FAT, so if an
;--- error occurs, nothing is corrupted.

UndeleteCore proc
    pushad
    mov cl, 2
nexttry:
    mov edi, [dwFilesize]
    mov esi, [dwCluster]
undelLoop:
    mov eax, [dwBpC]                    ; bytes per cluster
    mov ebx, esi
    cmp edi, eax                        ; less than bytes per cluster left?
    jbe writeeof                        ; yes, write end of file in
    sub edi, eax                        ; no, subtract bpc
getnextentry:
    inc ebx
    mov eax, ebx
    call getfatentry
    jc undelCoreError

    test eax, eax                       ; is the entry free?
    jnz getnextentry                    ; if no, just get the next?????

    mov eax, ebx
    xchg ebx, esi
    cmp cl, 2
    jz undelLoop
    call putfatentry
    jmp undelLoop
writeeof:
    dec cl
    jnz nexttry
    mov eax, 0FFFFFFFh
    call putfatentry
undelCoreError:
    popad
    ret
UndeleteCore endp

;-------------------------------------------------------
