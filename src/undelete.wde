;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux
;
;-------------------------------------------------------
undelete:
  mov byte ptr [fromfat], 1
  call spotinbx                         ; move to the beginning of the
    and bl, 11100000b                   ; file entry
    add bx, offset readbuffer
  mov eax, dword ptr [bx+DIR_FILESIZE]
  mov dword ptr [filesize], eax
  mov ax, word ptr [bx+DIR_CLUST_HIGH]  ; get start cluster (high 16-bits)
  shl eax, 16
  mov ax, word ptr [bx+DIR_CLUST_LOW]   ; get start cluster (low 16-bits)
  ; bounds check
  cmp eax, 2
  jb invclust                           ; not a valid cluster if it's below 2
  mov dword ptr [cluster], eax
  call getfatentry
  cmp byte ptr [status], ERROR          ; not enough free clusters?
  jne filenoexceed
    mov dx, offset fileexceeded
    call printerror
    jmp mainmenu
    invclust:
    mov dx, offset greatmsg
    call printerror
    jmp mainmenu
  filenoexceed:
  test eax, eax
  jz undel1good

    mov dx, offset nofirstcluster
    call printerror
    jmp mainmenu

  undel1good:

  mov dx, offset firstcharmsg
  call printbottom

  getkeyagain16:

  call cursorgetkey
  cmp al, ESCAPE_KEY
  je mainmenu

  call validfileinputchar
  jc getkeyagain16

  cmp al, 'a'
  jb unok1
  cmp al, 'z'
  ja unok1
    sub al, 32
  unok1:
;    call spotinbx                      ; should be preserved from above
;    and bl, 11100000b
;    add bx, offset readbuffer
    mov byte ptr [bx], al
    call copybuffer
    mov byte ptr [rw], WRITE
    call rwsect

    mov dx, offset undeletingmsg
    call printbottom

    call undeleteCore
    cmp byte ptr [status], ERROR
    jne nofer
      mov dx, offset fileexceeded
      call printerror
      jmp mainmenu
    nofer:

    mov dx, offset doneudmsg
    call printerror
  jmp mainmenu
;--------------------------------------------------------
UndeleteCore:           ; in: [filesize] - size of file to undelete)
  pushad                ;     [cluster]  - cluster to work from
  undelLoop:
    mov eax, dword ptr [bpc]            ; bytes per cluster
    mov ebx, dword ptr [cluster]
    cmp dword ptr [filesize], eax       ; less than bytes per cluster left?
    jbe writeeof                        ; yes, write end of file in
      sub dword ptr [filesize], eax     ; no, subtract bpc
    getnextentry:
      inc ebx
      mov eax, ebx
    call getfatentry
  cmp byte ptr [status], ERROR
  je undelCoreError
    test eax, eax
    jnz getnextentry

    mov eax, ebx
    xchg ebx, dword ptr [cluster]
    call putfatentry
    jmp undelLoop
    writeeof:
    mov eax, 0FFFFFFFh
    call putfatentry
  undelCoreError:
  popad
  ret
;-------------------------------------------------------
