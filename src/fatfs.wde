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
; 0FFFFFFFFh is returned instead.
;
;-------------------------------------------------------
cluster2sector:
  push ebx
  sub eax, 2

  movzx ebx, byte ptr [spc]
  mul ebx
  jc errem2

  add eax, dword ptr [datastart]
  jc errem2
  cmp byte ptr [fattype], FAT32
  jne skipfat32adjust
  cmp dword ptr [rootc], 2
  ja skipfat32adjust
    sub eax, ebx
    jnc skipfat32adjust
    errem2:
      mov eax, 0FFFFFFFFh         ; invalid cluster number was sent
  skipfat32adjust:
  pop ebx
  ret
;-------------------------------------------------------
;
; cluster2sector converts a sector number to its matching cluster number.
;
;               IN:   eax       sector number
;               OUT:  eax       corresponding cluster number
;                     ecx       corrupted
;
;-------------------------------------------------------
sector2cluster:
  movzx ecx, byte ptr [fats]

;  cmp cl, 0                            ; useful if ever FATS=0
;  je skipsfats
;  inc cl

  subfats:
    sub eax, dword ptr [spf]
  loop subfats

  cmp byte ptr [fattype], FAT32
  je dontsubroot
    mov cx, word ptr [rootsectors]
    sub eax, ecx
  dontsubroot:

  sub eax, dword ptr [reserved]

  mov cl, byte ptr [spcmd]
  shr eax, cl                           ; divide by sectors per cluster
    
  add eax, 2                            ; clusters start at 2
  ret
;-------------------------------------------------------
;
; getfatentry returns the entry in the fat table for a particular cluster #
;
;               IN:   eax       cluster number to get
;               OUT:  eax       data stored in the fat
;
;-------------------------------------------------------
getfatentry:
  push ebx
  push dword ptr [sector]
  push si

;  and eax, 0FFFFFFFh            ; ignore highest nibble
  mov ebx, eax
  call locatefatentry
  cmp byte ptr [status], ERROR
  je abortgfe
  mov si, offset readbuffer
  cmp byte ptr [fattype], FAT12
  jne dof13

  call fat12pad

    test al, 00000001b
    jnz method2
    method1:
      mov ax, word ptr [si+bx]
      and ah, 0Fh
    jmp f12gfs
    method2:
      mov ax, word ptr [si+bx]
      shr ax, 4
  f12gfs:
      cmp ax, 0FF7h                     ; if the fat entry is an end of chain
      jb f16gfd                         ; or bad cluster entry, then pad
      jmp filltopbits                   ; it so for any FAT type it's set
                                        ; to 0FFFFFFxh
  dof13:
  mov eax, dword ptr [si+bx]
  cmp byte ptr [fattype], FAT32
  je f32gfd
    f16gfd:
    and eax, 0FFFFh                     ; cut off top word for fat16
    cmp ax, 0FFF7h
    jb abortgfe
    filltopbits:                        ; for ease/compatibility, all fat 
    or eax, 0FFFF000h                   ; oddities (full/bad cluster) are
  f32gfd:                               ; set as FFFFFFxh
  and eax, 0FFFFFFFh
  abortgfe:
  pop si
  pop ebx
  cmp dword ptr [sector], ebx
  je oefgf
  mov dword ptr [sector], ebx

  cmp byte ptr [status], ERROR
  je oefgf
  call rwsect
  oefgf:
  pop ebx
  ret
;-------------------------------------------------------
;
; putfatentry writes the entry in the fat table for a particular cluster #
;
;               IN:   ebx       cluster number to write to
;                     eax       data to store in the fat
;
;-------------------------------------------------------
putfatentry:
  push dword ptr [sector]
  push edx
  push si
  mov edx, ebx
;  and eax, 0FFFFFFFh
  call locatefatentry
  cmp byte ptr [status], ERROR
  je abortpfe
  mov si, offset readbuffer
  cmp byte ptr [fattype], FAT12
  jne dof132

  call fat12pad
    test dl, 00000001b
    jnz pmethod2
    pmethod1:

      and ah, 0Fh
      and byte ptr [si+bx+1], 0F0h      ; replacing bottom 12 bits
      or ah, byte ptr [si+bx+1]         ; so preserve old top nibble

    jmp dpfe2
    pmethod2:

      shl ax, 4                         ; replacing the top 12 bits
      and byte ptr [si+bx], 0Fh
      or al, byte ptr [si+bx]           ; so preserve old low nibble

    jmp dpfe2
  dof132:
cmp byte ptr [fattype], FAT32
jne dpfe2
fat32pfe:
    and dword ptr [si+bx], 0F0000000h   ; preserve highest nibble in fat32
    or dword ptr [si+bx], eax           ; as it is not part of the entry
  dpfe2:
    mov word ptr [si+bx], ax
  dpfe:
  call copybuffer
  mov byte ptr [rw], WRITE
  call rwsect

  cmp bx, 511
  jne abortpfe
    inc dword ptr [sector]
    call rwsect
    inc bx
    mov al, byte ptr [si+bx]
    mov byte ptr [si], al
    jmp dpfe
  abortpfe:
  pop si
  pop edx
  pop dword ptr [sector]
  jmp rwsect
;-----------------------------------------------------------------
;
; locatefatentry finds the offset within the fat for a given cluster
;
;               IN:   ebx       cluster number to locate
;               OUT:  [sector]  sector # the entry is in
;                     ebx       byte offset to it inside the sector
;
; the sector is also read into readbuffer
;
;-----------------------------------------------------------------
locatefatentry:
  push eax
  push ecx
                                        
  cmp ebx, dword ptr [lastcluster]      ; past the last cluster on the drive
  seta byte ptr [status]
  ja nntri                              ; so abort with an error

  mov cl, byte ptr [fattype]    ; convert cluster number to # of bytes
  shr cl, 1                     ; since the start of the fat table
  shl ebx, cl
  cmp cl, 0
  jne donelfe13
    mov eax, ebx                ; adjustment for fat12
    shr eax, 1
    add ebx, eax
  donelfe13:

                                ; ebx = # of bytes since fat start
  movzx ecx, word ptr [bps]
  push cx
    shr cx, 9
    add cl, 8
                                ; divides ebx by bps in order to find what
    mov eax, ebx                ; sector the fat entry is in
    shr eax, cl
  pop cx

  shr ch, 1
  or cx, 111111111b
  and ebx, ecx 

  add eax, dword ptr [reserved]

;  cmp byte ptr [fats], 2
;  jb locationinfirstfat
  cmp byte ptr [fromfat], 1
  je locationinfirstfat
    add eax, dword ptr [spf]
  locationinfirstfat:

  cmp dword ptr [sector], eax   ; sets [sector] to that sector
  je nntri
  mov dword ptr [sector], eax
  call rwsect
  nntri:

  pop ecx
  pop eax
  ret
;-----------------------------------------------------------------
;
; fat12pad adds extra fat data around the sector buffer in case
;          the fat entry being read/written crosses a sector boundary
;
;               IN:   ebx       bytes to fat entry
;                     si        readbuffer pointer
;               OUT:  bytes written around readbuffer
;
;-----------------------------------------------------------------
fat12pad:                               ; IN: ebx = bytes to fat entry
  pushad                                ;     si = readbuffer pointer
                                        ; OUT: bytes put around sector
  push word ptr [status]
  push word ptr [subsector]
  mov byte ptr [handling], IGNORE_ERRORS
  mov eax, dword ptr [sector]           ; did we call this function
  cmp dword ptr [fat12fix], eax         ; from the same sector?  then
  je nf12b2                             ; we already have the correct data
  mov dword ptr [fat12fix], eax         ; ...this would be a tiny bug if
                                        ; we switch drives on sector 0

  mov bx, word ptr [bps]
  test eax, eax                         ; if the current sector is 0
  jz donttrylastsect                    ; then we can't read the previous
  dec dword ptr [sector]
  call rwsect
  mov al, byte ptr [si+bx-1]            ; copy last byte of previous sector
  mov byte ptr [fat12fix+4], al
  inc dword ptr [sector]

  donttrylastsect:
  mov eax, dword ptr [sector]           ; we don't want to read the next
  cmp eax, dword ptr [dataend]          ; sector if it's past the drive end
  jae nf12b

  inc dword ptr [sector]                ; copy first byte of next sector
  call rwsect
  mov al, byte ptr [si]
  mov byte ptr [si+bx], al

  dec dword ptr [sector]
  nf12b:
  call rwsect
  nf12b2:
  mov byte ptr [handling], ABORT_OPERATION
  pop word ptr [subsector]
  pop word ptr [status]
  popad
  ret
;-----------------------------------------------------------------
;
; getentrynumber gets the fat entry number the cursor is on
;
;               IN:   [sector]  current sector within a fat
;                     [spot]    byte offset inside current sector
;               OUT:  eax       entry number
;
;-----------------------------------------------------------------
getentrynumber:
  mov eax, dword ptr [sector]
  sub eax, dword ptr [reserved]

  mov byte ptr [fromfat], 1
  cmp eax, dword ptr [spf]
  jb getfromfirstfat
    sub eax, dword ptr [spf]
    inc byte ptr [fromfat]
  getfromfirstfat:
  mov cl, byte ptr [bps+1]
  shr cl, 1
  add cl, 8

  shl eax, cl
  movzx ebx, word ptr [spot]
  add eax, ebx

  mov cl, byte ptr [fattype]
  shr cl, 1
  shr eax, cl
  cmp cl, 0
  jne dlfe13
    xor edx, edx
    shl eax, 1
    mov bx, 3
    div ebx
  dlfe13:
  ret
;-----------------------------------------------------------------
;
; go2entry jumps to an entry in the fat
;
;               IN:   eax       cluster number
;               OUT:  [sector]  corresponding sector within a fat
;                     [spot]    byte offset within the sector
;
;-----------------------------------------------------------------
go2entry:
  cmp byte ptr [fattype], FAT12
  jne nosmd
    mov ecx, 3
    mul ecx

    shr eax, 1
    jnc noinc12
      inc eax
    noinc12:
    jmp sub512
  nosmd:

    mov cl, byte ptr [fattype]
    shr cl, 1
    shl eax, cl

  sub512:

  movzx edx, word ptr [bps]        ; \Fixed?/
  xor ecx, ecx
  loopfindsect:
  cmp eax, edx
  jb donesub
    sub eax, edx
    inc ecx
  jmp loopfindsect
  donesub:

  add ecx, dword ptr [reserved]
  mov dword ptr [sector], ecx

  xor dl, dl
  jmp movecursor
;-------------------------------------------------------
