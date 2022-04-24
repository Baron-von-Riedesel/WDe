;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux
;
;-------------------------------------------------------
;
; cluster2sector converts a cluster number to its matching sector number.
;
;               IN:  eax: cluster number
;               OUT: eax: sector number
;                    edx is corrupted
;
; if the cluster number given multiplies out to a value larger than
; can be stored in 32-bits, or the value ends up less than 2, then
; -1 is returned instead.
;
;-------------------------------------------------------
cluster2sector proc
    push ebx
    sub eax, 2
    jc errem2

    movzx ebx, [bSpC]
    mul ebx
    jc errem2

    add eax, [dwDataStart]
    jc errem2

    test [filesys], FS_FAT32
    je skipfat32adjust
    cmp [dwRootCluster], 2
    ja skipfat32adjust
    sub eax, ebx
    jnc skipfat32adjust
errem2:
    mov eax, -1             ; invalid cluster number was sent
skipfat32adjust:
    pop ebx
    ret
cluster2sector endp
;-------------------------------------------------------
;
; sector2cluster converts a sector number to its matching cluster number.
;
;               IN:   eax       sector number
;               OUT:  eax       corresponding cluster number
;                     ecx       corrupted
;
;-------------------------------------------------------
sector2cluster proc
    movzx ecx, [bFats]
;   jcxz skipfats                         ; useful if ever FATS=0
@@:
    sub eax, [dwSpF]
    jc done
    loop @B
skipfats:

    test [filesys], FS_FAT32
    jnz @F
    mov cx, [wRootsectors]
    sub eax, ecx
    jc done
@@:

    sub eax, [dwReserved]
    jc done

    mov cl, [bSpCshift]
    shr eax, cl                           ; divide by sectors per cluster
    
    add eax, 2                            ; clusters start at 2
done:
    ret
sector2cluster endp
;-------------------------------------------------------
;
; getfatentry returns the entry in the fat table for a particular cluster #
;
;               IN:   eax       cluster number to get
;               OUT:  eax       data stored in the fat
;                     C if cluster# given in eax is invalid
; this function may be called quite a few times if
; "recursing" ( ctrl-left ) within a FAT.
;-------------------------------------------------------
getfatentry proc
    push ebx
    push [dwCurSector]
    push si

;   and eax, 0FFFFFFFh                ; ignore highest nibble
    mov ebx, eax
    call locatefatentry
    jc abort
    mov si, offset sectbuffer
    cmp [filesys], FS_FAT12
    jne fat1632

    call fat12pad

    test al, 00000001b
    jnz @F
    mov ax, word ptr [si+bx]
    and ah, 0Fh
    jmp f12gfs
@@:
    mov ax, word ptr [si+bx]
    shr ax, 4
f12gfs:
    cmp ax, 0FF7h                     ; if the fat entry is an end of chain
    jb f16gfd                         ; or bad cluster entry, then pad
    jmp filltopbits                   ; it so for any FAT type it's set
                                      ; to 0FFFFFFxh
fat1632:
    mov eax, dword ptr [si+bx]
    test [filesys], FS_FAT32
    jnz f32gfd
f16gfd:
    movzx eax, ax                     ; clear top word for fat12/fat16
    cmp ax, 0FFF7h
    cmc                               ; should be NC when jumping!
    jnc done

filltopbits:                          ; for ease/compatibility, all fat 
    or eax, 0FFFF000h                 ; oddities (full/bad cluster) are
f32gfd:                               ; set as FFFFFFxh
    and eax, 0FFFFFFFh
done:
abort:
    pop si
    pop ebx
    pushf
    cmp [dwCurSector], ebx            ; don't reread current sector if it
    je @F                             ; hasn't changed
    mov [ioreq.dwSector], ebx
    call rwsectx
@@:
    popf
    pop ebx
    ret
getfatentry endp
;-------------------------------------------------------
;
; putfatentry writes the entry in the fat table for a particular cluster #
;
;               IN:   ebx       cluster number to write to
;                     eax       data to store in the fat
;
;-------------------------------------------------------
putfatentry proc
    push [dwCurSector]
    push edx
    push si
    mov edx, ebx
;    and eax, 0FFFFFFFh
    call locatefatentry                 ; copy FAT sector into buffer
    jc abortpfe
    mov si, offset sectbuffer
    cmp [filesys], FS_FAT12
    jne dof132

    call fat12pad
    test dl, 00000001b
    jnz pmethod2
pmethod1:

    and ah, 0Fh
    and byte ptr [si+bx+1], 0F0h        ; replacing bottom 12 bits
    or ah, byte ptr [si+bx+1]           ; so preserve old top nibble

    jmp dpfe2
pmethod2:

    shl ax, 4                           ; replacing the top 12 bits
    and byte ptr [si+bx], 0Fh
    or al, byte ptr [si+bx]             ; so preserve old low nibble

    jmp dpfe2
dof132:
    test [filesys], FS_FAT32
    je dpfe2
fat32pfe:
    and dword ptr [si+bx], 0F0000000h   ; preserve highest nibble in fat32
    or dword ptr [si+bx], eax           ; as it is not part of the entry
dpfe2:
    mov word ptr [si+bx], ax
dpfe:
    call writesect

    cmp bx, 511
    jne abortpfe
    inc [dwCurSector]
    call rwsect
    inc bx
    mov al, byte ptr [si+bx]
    mov byte ptr [si], al
    jmp dpfe
abortpfe:
    pop si
    pop edx
    pop [ioreq.dwSector]
    jmp rwsectx

putfatentry endp

;-----------------------------------------------------------------
;
; locatefatentry finds the offset within the fat for a given cluster
;
;               IN:   ebx       cluster number to locate
;               OUT:  [dwCurSector]  sector # the entry is in
;                     ebx       byte offset to it inside the sector
;                     C if error
; the sector is also read into sectbuffer
;
;-----------------------------------------------------------------
locatefatentry proc
    push eax
    push ecx
                                        
    cmp ebx, [dwLastCluster]    ; past the last cluster on the drive?
    stc
    ja done                     ; so abort with an error

    mov cl, [filesys]           ; convert cluster number to FAT offset
    and cl, FS_FAT12 or FS_FAT16 or FS_FAT32
    shr cl, 1                   ; FAT32: 4->2, FAT16: 2->1, FAT12: 1->0
    jnz @F
    mov eax, ebx                ; adjustment for fat12 -
    shr eax, 1                  ; we must multiply with 1.5
    add ebx, eax
@@:
    shl ebx, cl                 ; ebx = FAT offset
                                ; divides ebx by bps in order to find
    movzx ecx, [wBps]           ; sector# of the entry
    push cx
    shr cx, 9                   ; 0x200 / 0x200 + 8 = 9; 0x400 / 0x200 + 8 = 10
    add cl, 8
    mov eax, ebx
    shr eax, cl
    pop cx

;    shr ch, 1                   ; ???
;    or cx, 1ffh                 ; ???
    dec cx

    and ebx, ecx

    add eax, [dwReserved]

;    cmp [bFats], 2
;    jb locationinfirstfat
    cmp [fromfat], 1
    je locationinfirstfat
    add eax, [dwSpF]
locationinfirstfat:
    cmp [dwCurSector], eax      ; read that FAT sector if necessary
    je done
    mov [ioreq.dwSector], eax
    call rwsectx
done:
    pop ecx
    pop eax
    ret
locatefatentry endp
;-----------------------------------------------------------------
;
; fat12pad adds extra fat data around the sector buffer in case
;          the fat entry being read/written crosses a sector boundary
;
;               IN:   bx        bytes to fat entry
;                     si        sectbuffer pointer
;               OUT:  bytes written around sectbuffer
;
;-----------------------------------------------------------------
fat12pad proc                           ; IN: ebx = bytes to fat entry
    pushad                              ;     si = sectbuffer pointer
                                        ; OUT: bytes put around sector
    mov eax, [dwCurSector]              ; did we call this function
    cmp [fat12fixsec], eax              ; from the same sector?  then
    je done                             ; we already have the correct data
    mov [fat12fixsec], eax              ; ...this would be a tiny bug if
                                        ; we switch drives on sector 0
    push eax
    mov [handling], IGNORE_ERRORS
    mov bx, [wBps]
    test eax, eax                       ; if the current sector is 0
    jz nopred                           ; then we can't read the previous

    dec eax
    mov [ioreq.dwSector], eax
    call rwsectx
    jc @F
    mov cl, byte ptr [si+bx-1]          ; copy last byte of previous sector
    mov [fat12fix1], cl
@@:
    inc eax
nopred:                                 ; we don't want to read the next
    cmp eax, [dwDataend]                ; sector if it's past the drive end
    jae nosucc
    inc eax
    mov [ioreq.dwSector], eax           ; copy first byte of next sector
    call rwsectx
    jc nosucc
    mov cl, byte ptr [si]
    mov byte ptr [si+bx], cl
nosucc:
done2:
    pop [ioreq.dwSector]
    call rwsectx                        ; restore current sector
    mov [handling], ABORT_OPERATION
done:
    popad
    ret
fat12pad endp
;-----------------------------------------------------------------
;
; getentrynumber gets the fat entry number the cursor is on
;
;               IN:   [dwCurSector]  current sector within a fat
;                     [spot]    byte offset inside current sector
;               OUT:  eax       entry number. That is actually
;                               the cluster.
;-----------------------------------------------------------------
getentrynumber proc
    mov eax, [dwCurSector]
    sub eax, [dwReserved]

    mov [fromfat], 1
    cmp eax, [dwSpF]
    jb @F
    sub eax, [dwSpF]
    inc [fromfat]
@@:

;---  here eax contains relative sector# within FAT

    mov cl, byte ptr [wBps+1]  ; if sector size = 512, it's 2
    shr cl, 1                  ; 2 -> 1
    add cl, 8                  ; = 9

    shl eax, cl                ; * 512

;--- here eax contains relative offset of current sector within FAT

    movzx ebx, [spot]
    add eax, ebx

;--- here eax contains relative offset of current spot within FAT

    mov cl, [filesys]     ; 4=FAT32,2=FAT16,1=FAT12
    and cl, FS_FAT12 or FS_FAT16 or FS_FAT32
    shr cl, 1             ; 4->2, 2->1, 1->0
    shr eax, cl

;--- here eax contains - for FAT32 and FAT16 - the cluster #

    cmp cl, 0             ; FAT12?
    jne dlfe13
    xor edx, edx
    shl eax, 1
    mov bx, 3
    div ebx
dlfe13:
    ret
getentrynumber endp
;-----------------------------------------------------------------
;
; go2entry jumps to an entry in the fat
;
;               IN:   eax       cluster number
;               OUT:  [ioreq.dwSector]  corresponding sector within a fat
;                     [spot]    byte offset within the sector
;
;-----------------------------------------------------------------
go2entry proc
    cmp [filesys], FS_FAT12
    jne nosmd
    mov ecx, 3
    mul ecx

    shr eax, 1
    jnc noinc12
    inc eax
noinc12:
    jmp sub512
nosmd:

    mov cl, [filesys]
    and cl, FS_FAT12 or FS_FAT16 or FS_FAT32
    shr cl, 1
    shl eax, cl

sub512:

    movzx edx, [wBps]        ; \Fixed?/
    xor ecx, ecx
loopfindsect:
    cmp eax, edx
    jb donesub
    sub eax, edx
    inc ecx
    jmp loopfindsect
donesub:

    add ecx, [dwReserved]
    mov [ioreq.dwSector], ecx

    xor dl, dl
    jmp movecursor

go2entry endp
;-------------------------------------------------------
