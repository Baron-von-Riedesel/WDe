;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux
;
;-------------------------------------------------------
undelete proc
;undelete:
  mov [fromfat], 1
  call spot2bufofs                      ; move to the beginning of the
    and bl, 11100000b                   ; file entry
    add bx, offset readbuffer
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
  cmp [status], ST_ERROR                ; not enough free clusters?
  jne filenoexceed
  jmp undelete_err1
invclust:
    mov dx, offset greatmsg
    call printerror
    ret
filenoexceed:
  test eax, eax
  jz undel1good

    mov dx, offset nofirstcluster
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
;    add bx, offset readbuffer
    mov byte ptr [bx], al
    call copybuffer
    mov [ioreq.bRW], RW_WRITE
    call rwsect

    mov dx, CStr('UnDeleting...')
    call printbottom

    call UndeleteCore
    cmp [status], ST_ERROR
    je undelete_err1
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
UndeleteCore proc
;UndeleteCore:           ; in: [dwFilesize] - size of file to undelete)
  pushad                 ;     [dwCluster]  - cluster to work from
undelLoop:
    mov eax, [dwBpc]                    ; bytes per cluster
    mov ebx, [dwCluster]
    cmp [dwFilesize], eax               ; less than bytes per cluster left?
    jbe writeeof                        ; yes, write end of file in
      sub [dwFilesize], eax             ; no, subtract bpc
getnextentry:
      inc ebx
      mov eax, ebx
    call getfatentry
    cmp [status], ST_ERROR
    je undelCoreError
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
