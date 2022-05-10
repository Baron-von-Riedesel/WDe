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
; getfatentry returns the entry in the fat table for a particular cluster#
; called:
;   1. when "recursing" ( ctrl-left ) within a FAT ( then may be called quite often).
;   2. if ctrl-right has been pressed in data region
;   3. within savechain
;   4. within restorechain
;   5. by undelete and unformat
;
;               IN:   eax       entry# to get
;               OUT:  eax       data stored in the fat
;                     C if entry# in eax is invalid
;-------------------------------------------------------
getfatentry proc
    push ebx
    push si

;   and eax, 0FFFFFFFh                ; ignore highest nibble
    mov ebx, eax
    call locatefatentry               ; will set BX=offset in sector
    jc abort
    mov si, [pFatCache]
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
    test [filesys], FS_FAT32          ; FAT32 or exFAT?
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
    ret
getfatentry endp
;-------------------------------------------------------
;
; putfatentry writes the entry in the fat table for a particular cluster #
; called by undelete and unformat.
;
;               IN:   ebx       entry# that is to be modified
;                     eax       data to store at that entry
;
;-------------------------------------------------------
putfatentry proc
    @dprintfln "putfatentry: entry=%lX, data=%lX", ebx, eax
    push edx
    push si
    mov edx, ebx
;    and eax, 0FFFFFFFh
    call locatefatentry                 ; will copy FAT sector into FAT cache buffer
    jc abortpfe
    mov si, [pFatCache]
    cmp [filesys], FS_FAT12
    jne dof132

    call fat12pad
    test dl, 00000001b
    jnz pmethod2
pmethod1:
    and ah, 0Fh
    and byte ptr [si+bx+1], 0F0h        ; replacing bottom 12 bits
    or ah, byte ptr [si+bx+1]           ; so preserve old top nibble
    jmp isfat1x
pmethod2:
    shl ax, 4                           ; replacing the top 12 bits
    and byte ptr [si+bx], 0Fh
    or al, [si+bx]                      ; so preserve old low nibble
    jmp isfat1x

;--- FAT16/FAT32

dof132:
    test [filesys], FS_FAT32
    je isfat1x
;fat32pfe:
    and dword ptr [si+bx], 0F0000000h   ; preserve highest nibble in fat32
    or dword ptr [si+bx], eax           ; as it is not part of the entry
isfat1x:
    mov [si+bx], ax

    push [ioreq.pBuffer]
nextsector:
    push [pFatCache]
    pop [ioreq.pBuffer]
    call writesect

    cmp bx, 511          ; FAT12?
    jne abortpfe2

    inc [dwFatSector]
    push [dwFatSector]
    pop [ioreq.dwSector]
    mov [ioreq.bRW], RW_READ
    call diskaccess

    inc bx
    mov al, [si+bx]
    mov [si], al
    jmp nextsector

abortpfe2:
    pop [ioreq.pBuffer]
    clc
abortpfe:
    pop si
    pop edx
    ret

putfatentry endp

;-----------------------------------------------------------------
;
; locatefatentry finds the offset within the fat for a given cluster
; called by getfatentry and putfatentry.
;
;               IN:   ebx       cluster number to locate
;               OUT:  [dwFatSector]  sector # the entry is in
;                     bx       byte offset to it inside the sector
;                     C if error
; the sector is read into pFatCache
;
;-----------------------------------------------------------------
locatefatentry proc
    push eax
    push ecx

if 0 ; changed in v0.50                                       
    cmp ebx, [dwLastCluster]    ; past the last cluster on the drive?
    stc                         ; ERROR!!!
    ja done                     ; so abort with an error
else
    cmp [dwLastCluster], ebx    ; past the last cluster on the drive?
    jb done                     ; C set if ebx > dwLastCluster
endif

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
;    jb @F
    cmp [fromfat], FF_FAT1
    je @F
    add eax, [dwSpF]
@@:
    cmp [dwFatSector], eax      ; read that FAT sector if necessary
    je done
    call readfatcache
    jc done
    mov [dwFatSector], eax
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
;                     si        pointer to FAT sector cache
;               OUT:  bytes written around sectbuffer
;
;-----------------------------------------------------------------
fat12pad proc                           ; IN: ebx = bytes to fat entry
    pushad                              ;     si = sectbuffer pointer
                                        ; OUT: bytes put around sector
    mov eax, [dwFatSector]              ; did we call this function
    cmp [fat12fixsec], eax              ; from the same sector?  then
    je done                             ; we already have the correct data
    mov [fat12fixsec], eax              ; ...this would be a tiny bug if
                                        ; we switch drives on sector 0
    push eax
    mov [handling], IGNORE_ERRORS       ; inside fat12pad
    mov bx, [wBps]
    test eax, eax                       ; if the current sector is 0
    jz nopred                           ; then we can't read the previous

    dec eax
    call readfatcache
    jc @F
    mov cl, byte ptr [si+bx-1]          ; copy last byte of previous sector
;    mov [fat12fix1], cl
    mov [si-1], cl
@@:
    inc eax
nopred:                                 ; we don't want to read the next
    cmp eax, [dwDataend]                ; sector if it's past the drive end
    jae nosucc
    inc eax
    call readfatcache
    jc nosucc
    mov cl, byte ptr [si]
    mov byte ptr [si+bx], cl            ; verify if this is [si+512]
nosucc:
done2:
    pop eax
    call readfatcache
    mov [handling], ABORT_OPERATION     ; inside fat12pad
done:
    popad
    ret

readfatcache::
    cmp [pFatCache],0
    jnz @F
    push ax
    mov ax,[wBps]
    add ax, 2*4                 ; add a 4 byte reserve at start/end for fat12fix
    call allocmem
    add ax, 4                   ; the fat12 fix must be BEFORE sector start
    mov [pFatCache], ax
    pop ax
@@:
    mov [ioreq.dwSector], eax
    push [ioreq.pBuffer]
    push [pFatCache]
    pop [ioreq.pBuffer]
    mov [ioreq.bRW], RW_READ
    call diskaccess
    pop [ioreq.pBuffer]
    ret

fat12pad endp
;-----------------------------------------------------------------
;
; getentrynumber gets the fat entry number the cursor is on
; called 1. when ENTER has been pressed while in FAT
;        2. while in FAT, to display entry# in top line
;        3. from getcurrententry ( only called when inside FAT )
;
;               IN:   [dwCurSector]  current sector within a fat
;                     [spot]    byte offset inside current sector
;               OUT:  eax       entry number. That is actually
;                               the cluster.
;-----------------------------------------------------------------
getentrynumber proc
    movzx ebx, [spot]
getentrynumberX::              ; <--- if just the entry# of the sector start interests
    mov eax, [dwCurSector]
    sub eax, [dwReserved]

    mov [fromfat], FF_FAT1
    cmp eax, [dwSpF]
    jb @F
    sub eax, [dwSpF]           ; in 2. FAT
    inc [fromfat]
@@:

;---  here eax contains relative sector# within FAT

    mov cl, byte ptr [wBps+1]  ; if sector size = 512, it's 2
    shr cl, 1                  ; 2 -> 1
    add cl, 8                  ; = 9

    shl eax, cl                ; * 512

;--- here eax contains relative offset of current sector within FAT

    add eax, ebx

;--- here eax contains relative offset of current spot within FAT
;--- it's now to be divided thru 1.5 (FAT12), 2 (FAT16) or 4 (FAT32/exFAT)

    mov cl, [filesys]                           ; 12=exFAT,4=FAT32,2=FAT16,1=FAT12
    and cl, FS_FAT12 or FS_FAT16 or FS_FAT32    ; mask out the exFAT bit
    shr cl, 1             ; 4->2, 2->1, 1->0
    jz isfat12
    shr eax, cl           ; eax = entry #
    ret
isfat12:
;--- a FAT12-FAT can't have a size > 65536 (max should be 4096*12/8=6144),
;--- so a 16-bit muldiv should be ok as well.
    xor edx, edx
    shl eax, 1            ; eax = muldiv( eax, 2, 3 )
    mov bx, 3
    div ebx
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
