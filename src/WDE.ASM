;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux
;
;-------------------------------------------------------
; Welcome to the code.  It's a bit of a mess still, but it's gradually
; getting a little cleaner.  Some of the comments still around were
; written back when I never intended anyone to see the source, so they
; may not be particularly readable by anyone besides me for now.
;
; You might notice "\Fix/" in a few spots; this refers to my having
; hard-coded 512 bytes for sector sizes, not necessarily a bug.  Often
; I just need to go over the code and make sure it doesn't need to be fixed.
;
; I assemble the source with tasm32 5.3 and tlink 7.1.32.2
;
; for lfn/undelete:
;  if (spot < 33), then a calculation needs to be done to check
;  if it's the first sector of the current cluster or start of the root.
;  for fat32, ((currentsector - datastart % spc) = 0) should be true if 
;  at cluster start.  checksum needs to be calculated as well.
;
; Future Optimizations:
;  - repne can possibly be used to optimize finding strings
;
; for CD-rom drives/bootsector:
; offset:
;
;  50 (4): total sectors on drive
;  80 (2): bytes per sector
;  8C (4): type L path table location
;  94 (4): type M path table location
;  9C (-): directory record for root (below)
;
; Directory records:
;  0  (1): length of record
;  1  (1): extended attribute record length
;  2  (8): logical block number to entry's data
;  10 (8): length of file in bytes
;  18 (7?): recording date/time
;  25 (1): attributes hidden/directory (______DH)
;  32 (1): length of file identifier
;  33+   : file identifier
;  padding field byte at the end if file identifier length = even
;  another byte after this?
;
; for NTFS partitions/bootsector:
; offset:
;
;  0B (2): bytes per sector
;  0D (1): sectors per cluster
;  0E (1): reserved sectors
;  10 (5): 0
;  15 (1): media descriptor (F8h)
;  16 (2): 0
;  1C (4): LBA partition start
;  18 (2): sectors per track
;  1A (2): # of heads
;  20 (4): 0
;  28 (8): total number of sectors
;  24 (1): drive # (80h)
;  30 (8): logical cluster for file $MFT
;  38 (8): logical cluster for file $MFTmirr
;  40 (4): bytes per file record segment 2^(-1*this value, signed)
;  44 (4): clusters per index block (ie directories)
;  50 (4): checksum?
;
; MFT: first 16 entries are inaccessible to OS, known as metafiles
; each entry is ~1k - the first one is the MFT itself. others:
;
; calculation in bootsector for bytes per file record is to negate the
; value (two's complement), then shift the value 1 stored in eax left by
; that value. eax = 10000000000 = 1024 - why is this needlessly complex?
;
;
; $logfile:     list of steps used for file recovery
; $volume:      volume info
; $attrdef:     table of attribute names, numbers & descriptions
; $:            root folder
; $bitmap:      cluster bitmap?
; $boot:        bpb copy?
; $badclus:     bad cluster table
; $secure:      security descriptors for all files
; $upcase:      converts lowercase chars to matching unicode chars
; $quota:       info like quotas, reparse point data, object identifiers?
;
; backup bootsector is in the middle of the drive
;
; possible future functions:
;  - validcluster: clear/set carry flag depending on whether or not a
;                  cluster stored in eax is within the boundaries of the
;                  logical partition
;  - validsector:  same as above but for sectors
;
; Notes for int 24h:
;
; AH = device error bits
;       0:      error type
;               0: read
;               1: write
;
;       1-2:    location of error
;               00: ms-dos area
;               01: fat table
;               10: root
;               11: file area
;
;       7:      error type
;               0: char device error
;               1: block type error
;
;
; if block type error, low byte of DI contains error code:
;
;      00:      write protection violation
;      01:      unknown drive
;      02:      drive not ready
;      03:      invalid command
;      04:      crc data error
;      05:      length of request struct incorrect
;      06:      seek error
;      07:      unknown media (not formatted)
;      08:      sector not found
;      0A:      write error
;      0B:      read error
;      0C:      general failure
;      0E:      lock violation
;      0F:      disk changed at inappropriate time
;      10:      uncertain media?
;      11:      sharing buffer overflow?
;      14:      insufficient disk space
;

;locals
assume ds:WDE, cs:WDE
;WDE segment public word 'CODE'
WDE segment public dword 'CODE'
org 100h
.386p

;        DEBUG            EQU 1 ; uncomment to assemble in debug mode
;        BASIC            EQU 1 ; uncomment to enable extended functionality
        UNDEFINED        EQU 0

        CD_SECTOR_OFFSET EQU 10h  ; can't read first 16 sectors of CDs

; "rw" variable
        READ             EQU 0
        WRITE            EQU 1

; "fattype" variable
        FAT32            EQU 4
        FAT16            EQU 2
        FAT12            EQU 1

; "region" variable for figuring out what section we're on in the drive
        RESERVED_AREA    EQU 00010000b
        FAT_AREA         EQU 00100000b
        ROOT_AREA        EQU 01000000b
        DATA_AREA        EQU 10000000b

        ; if "region" does not have any of the lower 4 bits set, then
        ; it is set with a viewmode

; "viewmode" (low byte)
        DATAVIEW         EQU 0          ; not manually set mode

        MBRVIEW          EQU 00000001b
        BOOTSECTORVIEW   EQU 00000010b
        FAT12VIEW        EQU 00000011b
        FAT16VIEW        EQU 00000100b
        FAT32VIEW        EQU 00000101b
        ROOTVIEW         EQU 00000110b
        DEBUGVIEW        EQU 00000111b

        FSINFOVIEW       EQU 10000000b  ; not manually set mode     

; "viewmode" (high byte)
        AUTODETECT       EQU 0
        STATIC           EQU 1

; colors for the display
        EDITCOLOR        EQU 0cah        ; light green on red
        DEFAULTCOLOR     EQU 1fh         ; white on blue
        HIGHLIGHTCOLOR   EQU 30h         ; black on dark cyan

; "editmode" variable
        DEFAULTEDIT      EQU 0
        ASCIIEDIT        EQU 1

; "displaymode" variable
        HEX              EQU 0
        BINARY           EQU 1

; "drivetype" variable
        PHYSICAL         EQU 00000001b
        FAT              EQU 00000010b
        CDROM            EQU 00000011b

; "rwfunction" variable
        OLDINT13         EQU 00000001b
        NEWINT13         EQU 00000010b
        OLDINT25         EQU 00000100b
        NEWINT21         EQU 00001000b
        CDCOOKED         EQU 00010000b
        CDRAW            EQU 00100000b
        FILEFUNC         EQU 01000000b

        PRW              EQU 11111100b  ; physical read/write
        LRW              EQU 11110011b  ; logical read/write
        CRW              EQU 11001111b  ; cd-rom read/write
        FRW              EQU 00111111b  ; file read/write
        ; these 4 above can be used with the 'test' instruction
        ; to check which general read/write functions are being used


        NO_VERIFY               EQU 0
        VERIFY                  EQU 2
        NEWINT13_WRITE_FLAG     EQU NO_VERIFY

; "status" variable
        SUCCESS          EQU 0
        ERROR            EQU 1

; attribute bits
        READONLY         EQU 00000001b
        HIDDEN           EQU 00000010b
        SYSTEM           EQU 00000100b
        VOLUME           EQU 00001000b
        DIRECTORY        EQU 00010000b
        ARCHIVE          EQU 00100000b

; fat directory data offsets
        DIR_ATTRIBUTES   EQU 0Bh
        DIR_FILESIZE     EQU 1Ch
        DIR_CLUST_LOW    EQU 1Ah
        DIR_CLUST_HIGH   EQU 14h

; ascii
        BACKSPACE_KEY    EQU 8
        CTRLENTER_KEY    EQU 10
        ENTER_KEY        EQU 13
        ESCAPE_KEY       EQU 27
        SPACE            EQU 32
        DOUBLE_QUOTE     EQU 34
        PERCENT          EQU 37
        ASTERISK         EQU 42
        COMMA            EQU 44
        PERIOD           EQU 46
        FORWARD_SLASH    EQU 47
        COLON            EQU 58
        SEMICOLON        EQU 59
        LESS_THAN        EQU 60
        GREATER_THAN     EQU 62
        QUESTION_MARK    EQU 63
        BACK_SLASH       EQU 92
        PIPE             EQU 124


; scan codes
        TAB_KEY          EQU 15
        F1_KEY           EQU 59
        F2_KEY           EQU 60
        F3_KEY           EQU 61
        F4_KEY           EQU 62
        F5_KEY           EQU 63
        F6_KEY           EQU 64
        F7_KEY           EQU 65
        F8_KEY           EQU 66
        PAGEUP_KEY       EQU 73
        LEFT_KEY         EQU 75
        RIGHT_KEY        EQU 77
        UP_KEY           EQU 72
        DOWN_KEY         EQU 80
        PAGEDOWN_KEY     EQU 81
        DEL_KEY          EQU 83
        CTRLPAGEDOWN_KEY EQU 118
        CTRLPAGEUP_KEY   EQU 132
        CTRLLEFT_KEY     EQU 115
        CTRLRIGHT_KEY    EQU 116
        CTRLHOME_KEY     EQU 119
        CTRLEND_KEY      EQU 117

        ; it's far more code efficient to use scan codes
        ; instead of checking for both upper/lower case letters
        ; when the case is not significant
        SCAN_A           EQU 30
        SCAN_B           EQU 48
        SCAN_C           EQU 46
        SCAN_D           EQU 32
        SCAN_E           EQU 18
        SCAN_F           EQU 33
        SCAN_G           EQU 34
        SCAN_H           EQU 35
        SCAN_I           EQU 23
        SCAN_J           EQU 36
        SCAN_K           EQU 37
        SCAN_L           EQU 38
        SCAN_M           EQU 50
        SCAN_N           EQU 49
        SCAN_O           EQU 24
        SCAN_P           EQU 25
        SCAN_Q           EQU 16
        SCAN_R           EQU 19
        SCAN_S           EQU 31
        SCAN_T           EQU 20
        SCAN_U           EQU 22
        SCAN_V           EQU 47
        SCAN_W           EQU 17
        SCAN_X           EQU 45
        SCAN_Y           EQU 21
        SCAN_Z           EQU 44

; "handling" variable
        ABORT_OPERATION  EQU 0
        QUERY_FILL       EQU 1
        QUERY_SKIP       EQU 2
        IGNORE_ERRORS    EQU 3

; "fillflag" variable - low byte (type of fill)
        RANDOM           EQU 0
        INVERSE          EQU 1
        BIT8             EQU 2
        BIT12            EQU 3
        BIT16            EQU 4
        BIT32            EQU 5
;                     - high byte (for BIT fills)
        INCREMENT        EQU 0
        DECREMENT        EQU 1


; "srflag" variable
        SAVE             EQU 0
        RESTORE          EQU 1

; "mode" variable; dictates what mode WDe is in
        INITIAL          EQU 0
        EDIT             EQU 1

; "chainflag" variable
        NO_CHAIN         EQU 0
        FILE_CHAIN       EQU 1
        FAT_CHAIN        EQU 2

; "commandflag" variable for gethex
        GET_VALUE        EQU 0
        GET_STRING       EQU 1

;--- display string on the windows debug terminal
@DbgOut macro text
local xxx
ifdef _DEBUG
	call dbgout
	jmp xxx
	db text,0
xxx:
endif
	endm


Start:

  call init                     ; init: - set video mode
                                ;       - set default byte to edit
                                ;       - print copyright info
                                ;       - seed random timer
                                ;       - wipe variables
                                ;       - set some defaults
                                ;       - replace int24h

initsetdrive:
  mov byte ptr [driveflag], 0   ; set to reading drive letters with tab
setdrive:                       ; sets the drive being edited
  cmp byte ptr [driveflag], 0
  jne displayfnreq
  mov dx, offset drivemsg       ; "Drive:"
  call printbottom              ; print on the bottom of the screen

  getkeyagain3:
  call cursorgetkey             ; cursorgetkey turns the cursor on, gets
                                ; a key and then shuts the cursor back off
                                ; again (for normal editing)
  abortsetdrive:
  cmp byte ptr [mode], INITIAL  ; if the editor is in initial mode,
  jne notfirstset               ; the program can't return to the menu
    cmp al, ESCAPE_KEY
    jne notfirstset             ; if it's not been run then we're
    call quit                   ; in the initial screen, so hitting
    jmp setdrive                ; escape should start the quit sequence
  displayfnreq:
    call getfilename
    cmp ah, TAB_KEY
    je initsetdrive

    mov al, ESCAPE_KEY
    jcxz abortsetdrive
    call findfile
    jnc filefound
      mov dx, offset filenotfound
      call printerror
      jmp setdrive
    filefound:

    call getfilesize
;    mov eax, dword ptr [filesize]       ; file must be 1+ sectors in size
    cmp eax, 512
    jb toosmalltomount
    mov dword ptr [rwfilesize], eax

    call openfile

    mov ax, word ptr [filehandle]
    mov word ptr [rwhandle], ax
    mov bx, PHYSICAL*100h + FILEFUNC     ; bh = physical, bl=filefunc
    mov al, 0FFh
    jmp doreaddevice
  toosmalltomount:
    mov dx, offset toosmall
    call printerror
    jmp setdrive
  notfirstset:                  ; otherwise it should go back to the menu

  cmp al, ESCAPE_KEY
  je mainmenu

  cmp ah, TAB_KEY
  jne noswitch2f
    mov byte ptr [driveflag], 1
    jmp setdrive
  noswitch2f:

  sub al, '0'                   ; subtract 48, so '0' becomes 0, '1' = 1, etc
  cmp al, 9                     ; if the value is <= 9, the key pressed was
  jbe hdphysical                ; a drive number, 0-9

  sub al, 17                    ; 17 is the 65-48, so 'A' = 0, 'B' = 1, etc
  cmp al, 26                    ; if the value is > 26, a non-letter
  jbe gdriveletter              ; was pressed (non-valid drive letter)

  sub al, 32                    ; 32 is 'a'-'A', so 'a' = 0, 'b' = 2, etc
  cmp al, 26                    ; same concept as above
  ja getkeyagain3

  gdriveletter:
  mov bx, FAT*100h + OLDINT25
  doreaddevice:
  mov dx, offset readingdrive
  call printbottom

  push dword ptr [sector]               ; if drive switching is unsuccessful
  push word ptr [drive]                 ; the original drive/sector has to
  push word ptr [rwfunction]            ; be restored
  push dword ptr [drivestart]

  mov byte ptr [subsector], 0           ; rwfunction is the 'read/write'
  mov dword ptr [sector], 0             ; function being used.  2 for CDrom,
  mov dword ptr [drivestart], 0

  mov word ptr [rwfunction], bx         ; type of read/write functions

  setdrivevar:

  mov byte ptr [drive], al      ; attempt to read sector 0
  call rwsect

  cmp byte ptr [status], ERROR  ; failed?
  je driveerror

  add sp, 12                    ; if the drive could be set just fine,
                                ; then the pushed data (last drive, etc)
                                ; is no longer needed
  jmp readnext

  hdphysical:                   ; this is for setting up the
                                ; editing for a physical
                                ; rather than logical drive

    mov cl, al                  ; back up drive number
    mov dx, offset fhdmsg       ; choose between floppy and HD
    call printbottom
      getfh:
      call cursorgetkey

      cmp al, ESCAPE_KEY
      je setdrive

      cmp ah, SCAN_F
      je readasfloppy

      cmp ah, SCAN_H
      jne getfh

      add cl, 80h                       ; physical hard drive.
      readasfloppy:
    mov al, cl
;    al: 80h+ = hard drive
;    al: 00h+ = floppy
  dophysicalread:
    mov bx, PHYSICAL*100h + NEWINT13
  jmp doreaddevice

  driveerror:

  pop dword ptr [drivestart]
  pop word ptr [rwfunction]             ; restore original drive settings
  pop word ptr [drive]                  ; if reading the new drive failed
  pop dword ptr [sector]

  cmp byte ptr [mode], INITIAL
  je setdrive

  jmp mainmenu


  readnext:
  call setvariables             ; set all obtainable parameter variables

  cmp byte ptr [mode], EDIT
  je dontwipescreen
  redraw:
    mov es,[vidseg]             ; clear display area
if 0
    mov di, 178
else
    mov bl,[vidcols]
    mov bh,0
    add bx,bx
    mov di,bx
    add di,2*9
endif
    mov ax, DEFAULTCOLOR*100h+SPACE
    mov dl, 32
    continuewipescreen:
    mov cx, 52
    push di
    rep stosw
    pop di
    add di,bx
    dec dl
    jnz continuewipescreen

  mov byte ptr [mode], EDIT
  dontwipescreen:

  call printoffset              ; print current offset

  mainmenu:

    mov byte ptr [handling], ABORT_OPERATION
    call updatescreen
    mov dx, offset initialmenu
    call printmenu

  getkeyagain:

    call printview
    mov ax, word ptr [cxy]      ; set [xy] to cursor coordinates so that
    mov word ptr [xy], ax       ; functions like changemode color the right
                                ; spot on the screen
  call getkey

  cmp al, ESCAPE_KEY
  jne noquit0
    call quit
    jmp mainmenu
  noquit0:

  cmp ah, PAGEDOWN_KEY
  je nextsect

  cmp ah, PAGEUP_KEY
  je lastsect

  cmp ah, CTRLPAGEDOWN_KEY
  je nextsect1000

  cmp ah, CTRLPAGEUP_KEY
  je lastsect1000

  cmp al, ENTER_KEY
  je entercluster

  cmp al, CTRLENTER_KEY
  je retfat

  cmp ah, CTRLLEFT_KEY
  je recursechain

  cmp ah, CTRLRIGHT_KEY
  je jumpcluster

  cmp ah, CTRLHOME_KEY
  je jumptobootsector

  cmp ah, CTRLEND_KEY
  je jumptolastsect

  cmp ah, LEFT_KEY
  je moveleft

  cmp ah, RIGHT_KEY
  je moveright

  cmp ah, UP_KEY
  je moveup

  cmp ah, DOWN_KEY
  je movedown

  cmp ah, F1_KEY
  je savetodisk

  cmp byte ptr [drivetype], CDROM
  je cdromfileopts
    cmp ah, F2_KEY                      ; different menu for CDRoms
    je fileoperations
  cdromfileopts:
  mov byte ptr [srflag], SAVE
    cmp ah, F2_KEY
    je srfileoptions

  cmp ah, F3_KEY
  je jumpto

  cmp ah, F4_KEY
  je viewoptions

  cmp ah, F5_KEY
  je searchoptions

  cmp ah, F6_KEY
  je functions

  cmp ah, F7_KEY
  je setdrive

  cmp ah, TAB_KEY
  je changemode

  cmp ah, DEL_KEY       ; allow writing of null when using the delete key
  je domod              ; in ascii editing mode

  cmp al, 0             ; don't write null values in ascii for certain
  je skipmod            ; extended keys (F8-F12 for example)

domod:

  cmp byte ptr [editmode], ASCIIEDIT
  je modascii

skipmod:

  cmp byte ptr [displaymode], BINARY
  je modbinary

  mov dl, al            ; back up the key pressed for printing

  sub al, '0'           ; subtract 48, so '0'-'9' becomes 0-9
  cmp al, 9
  jbe number            ; below or equal to 9?  a number was typed.

  sub al, 17            ; 'A'-'0' = 17, so make A-F = 0-5

  cmp al, 5             ; below or equal to 'F'?
  jbe cletter           ; then a hex letter was typed

  cmp al, 37            ; check again
  ja getkeyagain

  sub dl, 32            ; possibly lower case, which are 32 bytes higher
  sub al, 32            ; so subtract 32 bytes for printing/use

cletter:

  add al, 10            ; A-F are currently 0-5, so make them 10-15
;-------------------------------------------------------
number:
  call printchar

modifybuffer:
  mov dx, word ptr [spot]

  call aspotcalc
  mov word ptr [xy], dx
  call spotinbx
  mov dl, byte ptr [readbuffer+bx]      ; get the byte to be edited from
                                        ; the buffer

  cmp byte ptr [hl], 0
  jne lowmodify
    and dl, 0Fh                 ; remove the top nibble, set the typed in
    shl al, 4                   ; value in place to be the new top nibble
  jmp donemodify

  lowmodify:
    and dl, 0F0h                ; remove the bottom nibble

  donemodify:
    or dl, al                   ; set new high/low nibble

    mov byte ptr [readbuffer+bx], dl    ; display the new character
    call printchar                      ; on the right side of the screen
  jmp moveright
;-------------------------------------------------------
savetodisk:
  mov dx, offset readingmsg
  call printbottom
    call copybuffer                     ; copy readbuffer to writebuffer
    push word ptr [subsector]           ; remember subsector number
    mov byte ptr [rw], WRITE            ; set to write sector
    call rwsect                         ; write it.
    pop word ptr [subsector]
    cmp byte ptr [status], ERROR
    je mainmenu
    mov dx, offset donermsg
  call printerror
jmp mainmenu
;-------------------------------------------------------
restrictsectors:
  mov dx, offset abmsg
  call printbottom
  rsgetkeys:
  call cursorgetkey
  cmp al, ESCAPE_KEY
  je functions
  cmp ah, SCAN_A
  je restrictabove
  cmp ah, SCAN_B
  jne rsgetkeys
  restrictbelow:
    mov eax, dword ptr [sector]         ; set the current sector as the
    mov dword ptr [dataend], eax        ; last sector of the drive
    jmp mainmenu
  restrictabove:
    mov eax, dword ptr [sector]         ; set the current sector as the
    add dword ptr [drivestart], eax     ; first sector; this is added to
    sub dword ptr [dataend], eax        ; [sector] for r/w, so adjust the
    xor eax, eax                        ; final sector accordingly
    mov dword ptr [sector], eax
      mov dx, offset plmsg
      call printbottom
      rsgetkeys2:
      call cursorgetkey
      cmp al, ESCAPE_KEY
      je functions
      mov dl, PHYSICAL
      cmp ah, SCAN_P
      je donesetpl
      cmp ah, SCAN_F
      jne rsgetkeys2
      mov dl, FAT
    donesetpl:
      mov byte ptr [drivetype], dl
      call setvariables
      jmp mainmenu
;-------------------------------------------------------
functions:
  mov byte ptr [funcmenu], 2

  ifndef BASIC
    cmp byte ptr [drivetype], FAT
    jne nlfdf
        
    inc byte ptr [funcmenu]
    mov si, offset readbuffer
    xor bx, bx
    call finddirectory 
    jc nlfdf                      ; dir not found
    call spotinbx               ; if a directory is found, check to see if
    and bl, 11100000b           ; the very first entry of the current file
                                ; we're in (cur_byte / 32) is equal to
                                ; E5h, if so, we should display the option
                                ; to undelete

    cmp byte ptr [readbuffer+bx], 0E5h
    jne nlfdf
    inc byte ptr [funcmenu]
    nlfdf:
  endif

  mov dx, offset funcmenu
  call printmenu

  getkeyagain13:
  call getkey

  cmp al, ESCAPE_KEY
  je mainmenu

  cmp ah, F1_KEY
  je restrictsectors

  cmp ah, F2_KEY
  je fillfunctions

  ifndef BASIC
    cmp byte ptr [funcmenu], 2
    je getkeyagain13

    cmp ah, F3_KEY
    je unformat

    cmp byte ptr [funcmenu], 3
    je getkeyagain13

    cmp ah, F4_KEY
    jne getkeyagain13
      ;------------------------------------------------------
include UNDELETE.WDE
;------------------------------------------------------
include UNFORMAT.WDE
;------------------------------------------------------
  else
    jmp getkeyagain13
  endif

fillstring:
  call getstring

dofill:

  jcxz fillfunctions
  call getnos
  je fillfunctions

    mov dx, offset readingmsg
    call printbottom
  push dword ptr [sector]
  push cs
  pop es
  mov di, offset readbuffer

  mov ax, word ptr [bps]
  mov dx, cx

  kfi:
  mov si, offset stringbuffer
  fillstringloop:
    movsb
    dec ax
    jz dfs
  cfloop:
  loop fillstringloop
    mov cx, dx
  jmp kfi
  dfs:

    call fillcommon
    jc fillerror
    jz donefillrand

    mov ax, word ptr [bps]
  jmp cfloop
;-------------------------------------------------------
fillfunctions:
  mov dx, offset fillmenu
  call printmenu

  getkeyagain14:
  call getkey

  cmp al, ESCAPE_KEY
  je functions

  cmp ah, F1_KEY
  je fillhex

  cmp ah, F2_KEY
  je fillstring

  cmp ah, F4_KEY
  je decremental

  mov byte ptr [fillflag+1], INCREMENT

  cmp ah, F3_KEY
  je incremental

  mov byte ptr [fillflag], INVERSE

  cmp ah, F5_KEY
  je fillinvrand

  mov byte ptr [fillflag], RANDOM

  cmp ah, F6_KEY
  je fillinvrand

  jmp getkeyagain14
;-----------------------------------------------------
decremental:
  mov byte ptr [fillflag+1], DECREMENT
incremental:
  mov dx, offset idmenu
  call printmenu
  getkeyagain15:
  call getkey

  cmp al, ESCAPE_KEY
  je fillfunctions

  mov dx, offset hexmsg

  xor ecx, ecx

  mov byte ptr [fillflag], BIT8
  mov cl, 0FFh
  cmp ah, F1_KEY
  je fillamount

  mov byte ptr [fillflag], BIT12
  mov ch, 0Fh                           ; ECX=0FFFh
  cmp ah, F2_KEY
  je fillamount

  mov byte ptr [fillflag], BIT16
  mov ch, 0FFh                          ; ECX=0FFFFh
  cmp ah, F3_KEY
  je fillamount

  mov byte ptr [fillflag], BIT32
  mov ecx, 0FFFFFFFFh
  cmp ah, F4_KEY
  jne getkeyagain15
      ;---------------------------------------------------
fillamount:
  mov eax, ecx
  call gethex                    ; valuebuffer gets set in menu section
  jc fillfunctions
      ;-----------------------------------------------------
fillinvrand:
  call getnos
  je fillfunctions
    mov dx, offset readingmsg
    call printbottom
  mov eax, ebx
  push cs
  pop es

  push dword ptr [sector]
  mov di, offset readbuffer
  keeprandomfill:
  mov cx, word ptr [bps]                ; \Fixed?/

  cmp byte ptr [fillflag], BIT12
  je do12fill
  cmp byte ptr [fillflag], BIT8         ; writing byte at a time?
  je dontshift                          ; then dont divide by 2
    shr cx, 1                           ; divide by 2 to write words
  cmp byte ptr [fillflag], BIT16        ; if we're writing 32-bits at a time
  je dontshift
    shr cx, 1                           ; divide by 2 again
  dontshift:
  cmp byte ptr [fillflag], INVERSE
  jne randomloop                        ; inverse function requires reading
    mov si, di                          ; every sector to reverse that data
    call rwsect
    cmp byte ptr [status], ERROR
  je fillerror

  randomloop:
    cmp byte ptr [fillflag], INVERSE
    jne tryrandfill
      lodsd                             ; reverse a dword at a time
      not eax
    jmp continuerandinv
    tryrandfill:
    cmp byte ptr [fillflag], RANDOM
    jne continuerandinv
      push cx
      call rand                         ; generate random value (eax)
      pop cx
    continuerandinv:
    cmp byte ptr [fillflag], BIT16
    je fill16bit
    cmp byte ptr [fillflag], BIT8
    je fill8bit
    stosd

    cmp byte ptr [fillflag], BIT32      ; inverse/random are finished
    jne doriloop
    fill32bit:
      cmp byte ptr [fillflag+1], DECREMENT
      je decdword
        inc eax
        jmp doriloop
      decdword:
        dec eax
        jmp doriloop

    fill16bit:
      stosw
      cmp byte ptr [fillflag+1], DECREMENT
      je decword
        inc ax                          ; increment word
        jmp doriloop
      decword:
        dec ax                          ; decrement word
        jmp doriloop

    fill8bit:                           ; byte
      stosb
      cmp byte ptr [fillflag+1], DECREMENT
      je decbyte
        inc al
        jmp doriloop
      decbyte:
        dec al
    doriloop:
  loop randomloop

    call fillcommon
    jc fillerror
    jnz keeprandomfill
donefillrand:
  pop dword ptr [sector]
  call rwsect
  mov dx, offset donermsg
  call printerror
  jmp fillfunctions
;-----------------------------------------------------
do12fill:
  stosb
  loop n1s22                    ; ran out of bytes to this sector?
    call fillcommon
    jc fillerror
    jz donefillrand
    mov cx, word ptr [bps]      ; \Fixed?/

  n1s22:
    mov bh, ah
    call cax12
    mov dx, ax
    shl al, 4
    or al, bh
    stosb

  loop n2s22
    call fillcommon
    jc fillerror
    jz donefillrand
    mov cx, word ptr [bps]      ; \Fixed?/

  n2s22:
    mov ax, dx
    shr ax, 4
    stosb

  loop n3s22
    call fillcommon
    jc fillerror
    jz donefillrand
    mov cx, word ptr [bps]      ; \Fixed?/

  n3s22:
    mov ax, dx
    call cax12
  jmp do12fill
;-----------------------------------------------------
fillerror:
  pop dword ptr [sector]
  push word ptr [status]
    call rwsect
    call updatescreen
  pop word ptr [status]
  cmp byte ptr [status], ERROR
  je fillfunctions
    mov dx, offset abortdmsg
    call printerror
  jmp fillfunctions
;-----------------------------------------------------
fillhex:
  mov dx, offset hexmsg
  call gethexstring
  jc fillfunctions

  jmp dofill
;-----------------------------------------------------
fillcommon:                     ; zero flag set if no more sectors to fill
  call checkabort               ; carry flag set if there's an error
  je commonfillerror
  call copybuffer
  mov byte ptr [rw], WRITE
  call rwsect
  cmp byte ptr [status], ERROR
  je commonfillerror
  dec dword ptr [value]
  jz donefillinc
  inc dword ptr [sector]
  call printcounts
  push cs
  pop es
  mov di, offset readbuffer
  test di, di                   ; zero flag cleared
donefillinc:
  clc
  ret
commonfillerror:
  stc
  ret
;-----------------------------------------------------
cax12:
  cmp byte ptr [fillflag+1], INCREMENT
  je doinc12
    sub ax, 1
    jnc loopdi12                ; rolled over to FFFFh?
    and ah, 0Fh                 ; yes, removed highest nibble
    jmp loopdi12

  doinc12:
    inc ax
    cmp ax, 0FFFh
    jbe loopdi12
    xor ax, ax
  loopdi12:
  ret
;-----------------------------------------------------
modbinary:
  call spotinbx                 ; get the current cursor position
  mov cl, byte ptr [hl]
  cmp cl, 5                     ; if we're over the space between nibbles
  jb skipbinadjust              ; decrement so that the position matches
    dec cl                      ; incrementally to bits 0-7
  skipbinadjust:
  mov dl, 10000000b             ; this byte gets shifted as a mask
  shr dl, cl                    ; to work with the bit we're editing

  cmp al, '1'
  je onebin
  cmp al, SPACE
  je reversebin
  cmp al, '0'
  jne getkeyagain
    not dl
    and byte ptr [readbuffer+bx], dl    ; clearing a bit
    jmp donefixbin
  reversebin:
    xor byte ptr [readbuffer+bx], dl    ; changing a bit
    mov al, '0'
    test byte ptr [readbuffer+bx], dl
    jz donefixbin
    mov al, '1'
    jmp donefixbin
  onebin:
    or byte ptr [readbuffer+bx], dl     ; setting a bit
  donefixbin:

  mov dl, al                            ; print binary
  call printchar

  mov dx, bx                            ; set [xy] to the next bit
  call aspotcalc
  mov word ptr [xy], dx
  mov dl, byte ptr [readbuffer+bx]      ; replace the ascii on the screen
  call printchar
  jmp moveright
;-------------------------------------------------------
modascii:
  call spotinbx
  mov byte ptr [readbuffer+bx], al
  mov bx, word ptr [spot]
  mov dx, bx
  call spotcalc
  mov word ptr [xy], dx

  cmp byte ptr [displaymode], HEX
  je dofixhex
  call displaybinary
  jmp donefixscreen
  dofixhex:
    call printhex
    mov dx, offset valuebuffer+7
    call printstring
  donefixscreen:
    mov dx, bx
    call aspotcalc
    mov word ptr [xy], dx

    mov cl, 1
    call printchar2
  jmp moveright
;-------------------------------------------------------
changemode:
  cmp al, 0                     ; shift+tab
  je changedispmode

  cmp byte ptr [editmode], 0    ; switch between ascii/regular editing
  sete byte ptr [editmode]

  call colorchar
  jmp getkeyagain
;-------------------------------------------------------
changedispmode:
  cmp byte ptr [displaymode], 0 ; switch between hex/binary editing
  sete byte ptr [displaymode]

  xor dl, dl
  mov ax, word ptr [spot]
  call movecursor
  jmp redraw
;-------------------------------------------------------
log2phys:                            ; jump from logical drive
  mov al, byte ptr [hdnumber]        ; to parent physical drive
  jmp dophysicalread
;-------------------------------------------------------
retfat:
  cmp byte ptr [drivetype], FAT      ; won't work with non-logical drives
  jne getkeyagain
  mov eax, dword ptr [sector]
  test eax, eax                      ; if we're on a logical drive, attempt
  jz log2phys                        ; to jump to respective phys. drive

  test byte ptr [region], DATA_AREA
  jz getkeyagain

retcluster:
  call sector2cluster
  call go2entry

  call rwsect
  jmp mainmenu
;-------------------------------------------------------
recursechain:
  cmp byte ptr [region], FAT_AREA
  jne getkeyagain

  call getcurrententry                  ; ebx = current entry number

  mov eax, ebx                          ; no where to recurse from
  cmp ebx, 2                            ; starting (2nd) cluster
  jbe mainmenu

  push word ptr [xy]
  mov dx, offset recursemsg
  call printbottom
  pop word ptr [xy]

  recurse:
    call checkabort
    je mainmenu

    dec eax                             ; go back one fat entry
    cmp eax, 1                          ; past first entry in fat?
    je chainnotfound                    ; yes, link not found

    push eax
      call getfatentry                  ; read the fat entry
      cmp ebx, eax                      ; match the one we want?
    pop eax

  jne recurse                           ; no...keep recursing
  jmp dochainjump
  chainnotfound:
  mov dx, offset nochainmsg
  call printerror
  jmp mainmenu
;-------------------------------------------------------
jumpcluster:
  cmp byte ptr [region], FAT_AREA
  je jumpfatcluster
  test byte ptr [region], DATA_AREA
  jz getkeyagain
      ;-------------------------------------------------------
jumpdatacluster:
  mov eax, dword ptr [sector]
  mov byte ptr [fromfat], 1
  call sector2cluster                   ; get respective cluster number
  call getfatentry                      ; read fat entry
  cmp byte ptr [status], ERROR
  je mainmenu

  jmp jumptoeax                         ; jump to the cluster number read
;-------------------------------------------------------
jumpfatcluster:

  call getcurrententry
  cmp byte ptr [status], ERROR
  je mainmenu

  dochainjump:

  cmp eax, 2            ; disregard ebx, which is the current entry #
  jb mainmenu           ; we only care about eax, the value stored there.
;  cmp eax, 0FFFFFF7h
;  jae mainmenu

  cmp eax, dword ptr [lastcluster]
  ja mainmenu
  push dword ptr [sector]
  call go2entry
  pop edx
  cmp edx, dword ptr [fatend]           ; bad coding.  doesn't support 3+ fats
  jb nsf
    mov ecx, dword ptr [spf]
    add dword ptr [sector], ecx
  nsf:

  cmp dword ptr [sector], edx           ; don't read the same sector twice
  je drsfj
    call rwsect
  drsfj:

  jmp mainmenu
;-------------------------------------------------------
entercluster:
  cmp byte ptr [drivetype], FAT
  jne getkeyagain

  cmp byte ptr [viewmode], ROOTVIEW
  je enterfiledir

  call getentrynumber                   ; get the cluster number for current
jumptoeax:                              ; offset
  cmp eax, 2
  jb mainmenu
  call cluster2sector                   ; multiply it out to get the
  cmp eax, dword ptr [dataend]          ; corresponding sector number
  ja mainmenu                           ; verify that it's a valid sector
  mov dword ptr [sector], eax
  call rwsect
  jmp mainmenu
;-------------------------------------------------------
enterfiledir:                           ; this code is set up so that
  call spotinbx                         ; if you hit enter on the 32
  and bl, 11100000b                     ; bytes belonging to a file entry
                                        ; the editor will jump to its
                                        ; starting cluster
  mov ax, word ptr [readbuffer+bx+DIR_CLUST_HIGH]
  shl eax, 16
  mov ax, word ptr [readbuffer+bx+DIR_CLUST_LOW]

  cmp eax, 2
  jb jumptoroot
  jmp jumptoeax
;-------------------------------------------------------
viewoptions:
  mov dx, offset viewmenu
  call printmenu

  getkeyagain1:
  call getkey

  cmp al, ESCAPE_KEY
  je mainmenu

  cmp ah, F1_KEY
  je defaultview
  jb getkeyagain

mov al, ah
sub al, 59

ifdef DEBUG                             ; extra view for registers
  cmp ah, F8_KEY        ; (debug)
  je setview
endif

  cmp ah, F7_KEY        ; (dir)
  ja getkeyagain1

      ;-------------------------------------------------------
      ; IN: al = mode
setview:                         ; the high byte of viewmode, if set to 1,
  mov byte ptr [viewmode+1], STATIC
  mov dl, al                     ; will force the current viewmode.
  cmp dl, FAT12VIEW              ; if zeroed, the default viewmode will be
  jne dsf12s                     ; used on the drive

  mov eax, dword ptr [sector]
  mov dword ptr [fat12start], eax

  dsf12s:
  call checksetview
  jmp mainmenu
;-------------------------------------------------------
defaultview:
  mov byte ptr [viewmode+1], AUTODETECT
  call printcounts
  jmp mainmenu
;-------------------------------------------------------
searchoptions:
  mov dx, offset searchmenu
  call printmenu

  mov byte ptr [handling], QUERY_SKIP

  getkeyagain8:
  call getkey

  cmp al, ESCAPE_KEY
  je mainmenu

  cmp ah, F1_KEY
  je findstring
  
  cmp ah, F2_KEY
  je findhex

  cmp ah, F3_KEY
  je findmbr

  cmp ah, F4_KEY
  je findbs

  cmp ah, F5_KEY
  je findfat

  cmp ah, F6_KEY
  jne getkeyagain8
      ;-------------------------------------------------------
finddir:
  mov si, offset readbuffer

  finddirnext:
  xor bx, bx

  call finddirectory
  jnc mainmenu

  call findcommon
  jmp finddirnext
;-------------------------------------------------------
findbs:
  mov si, offset readbuffer
findbsnext:
  cmp dword ptr [si+1fch], 0AA550000h           ; check for boot sig ++
  jne findbs2
  cmp byte ptr [si], 0EBh                       ; check for jmp
  je mainmenu
  findbs2:
  call findcommon
  jmp findbsnext
;-------------------------------------------------------
; This function is slightly bugged; the first byte is a media descriptor
; byte and only makes the partition more likely to be a certain type of
; fat.  Fat finding should only verify that the first byte is a valid
; media descriptor and then attempt to identify the fat type.
;
findfat:
  mov si, offset readbuffer
  findfatnext:
  cmp byte ptr [si], 0F0h       ; fat12
  je n12sfl
  cmp byte ptr [si], 0F8h       ; fat16/fat32
  jne findfat2
  fatok:
  mov bx, 3
  cmp byte ptr [si+bx], 0Fh     ; fat32
  jne if16

  ; likely fat32

  lfatloop:
    add bx, 4
    test byte ptr [si+bx], 0F0h         ; highest nibble on fat32 shouldn't
    jnz findfat2                        ; be anything but 0000b
  cmp bx, 511
  jne lfatloop
  jmp dfstests

  ; likely fat12

  if12:
    mov ax, word ptr [si+bx]
    and ah, 0Fh
    cmp ax, 001h                        ; nothing links to cluster 1
    je findfat2
    cmp ax, 0FF7h
    jae n12sfl
    cmp ah, 0Fh                         ; no clusters >= F00h
    je findfat2
    n12sfl:
    mov al, byte ptr [si+bx+2]
    mov ah, byte ptr [si+bx+1]
    rol ax, 4
    and ah, 0Fh
    cmp ax, 001h
    je findfat2
    cmp ax, 0FF7h
    jae d12sw
    cmp ah, 0Fh
    je findfat2
    d12sw:
    add bx, 3
    cmp bx, 510
  jb if12

  cmp byte ptr [si+5], 00h
  je dfstests
  cmp byte ptr [si+5], 0FFh
  jne findfat2
  jmp dfstests

  ; likely fat16

  if16:
  cmp byte ptr [si+bx], 0FFh
  jne findfat2
  inc bx

  lfatloop2:
    cmp word ptr [si+bx], 0001h         ; nothing links to cluster 1
    je findfat2
    cmp word ptr [si+bx], 0FFF7h
    jae nf16lt
    cmp word ptr [si+bx], 0E800h        ; no clusters >= E800h in the first
    jae findfat2                        ; sector of the fat?  (not a fact)
    nf16lt:
    add bx, 2
  cmp bx, 512
  jne lfatloop2

  cmp byte ptr [si+5], 00h
  je dfstests
  cmp byte ptr [si+5], 0FFh
  jne findfat2

  dfstests:
  cmp word ptr [si+1], 0FFFFh
  je mainmenu
  findfat2:
  call findcommon
  jmp findfatnext
;-------------------------------------------------------
findmbr:
  mov si, offset readbuffer
  findmbrnext:

  cmp byte ptr [si], 0EBh
  je findmbr2
  cmp dword ptr [si+1fch], 0AA550000h   ; mbr signature
  jne findmbr2
  cmp dword ptr [si+1e4h], 061417272h   ; fsinfo sector signature
  je findmbr2                           ; annoying of microsoft to
                                        ; give it an MBR signature
  mov bx, 1BEh

  xor al, al
  checkactiveloop:
    mov ah, byte ptr [si+bx]            ; "active" partition byte
    test ah, 01111111b                  ; any bits other than 7 set?
    jnz findmbr2                        ; yes, not a valid MBR.
    shl ah, 1                           ; shift bit 7 out of the register
    adc al, 0                           ; if it was 1, increase al
    add bx, 10h
    cmp bx, 1EEh
    jne checkactiveloop

  cmp al, 1                             ; more than one active partition?
  je mainmenu                           ; no, MBR found.

  findmbr2:
  call findcommon
  jmp findmbrnext
;-------------------------------------------------------
findhex:
  mov dx, offset hexmsg
  call gethexstring
  jc searchoptions

  test cx, cx
  jz searchoptions

  mov dx, offset searchingmsg
  call printbottom
  jmp stringsearch
;-------------------------------------------------------
updatescreen:
  cmp byte ptr [mode], EDIT
  je doupdate                   ; fixes display for an init file not found
    ret
  doupdate:
  call printcounts
  call printscreen

    cmp byte ptr [viewmode+1], AUTODETECT       ; detect the view type
    jne continueprintview
    mov dl, byte ptr [region]

    test dl, 11110000b                  ; is region set with a forced view?
    jz dontscanforbsfs                  ; then set it

    cmp dl, FAT_AREA
    je choosefatview

    test dl, ROOT_AREA                  ; root can also be a data area
    jnz settodir

    cmp dl, DATA_AREA
    jne dontscanfordir
      mov si, offset readbuffer
      xor bx, bx
      call finddirectory
      jnc settodir
      mov dl, DATAVIEW
    dontscanfordir:
    cmp dl, RESERVED_AREA
    jne dontscanforbsfs
      cmp dword ptr [sector], 0
      je setbsview
      mov eax, dword ptr [backupbs]
      cmp dword ptr [sector], eax
      je setbsview
      movzx edx, word ptr [fsinfo]
      cmp dword ptr [sector], edx       ; in the fsinfo sector?
      je setfsview                      ; then set fsinfo view
      add edx, eax                      ; checks if we're in the backup
      cmp dword ptr [sector], edx       ; fsinfo sector...but it assumes
      je setfsview                      ; it's the same distance from the backupbs
      mov dl, DATAVIEW                  ; as the main fsinfo is the main
      jmp dontscanforbsfs               ; bootsector, which is wrong.
      settodir:
      mov dl, ROOTVIEW
    dontscanforbsfs:
      call checksetview
    continueprintview:
  jmp printview
  setbsview:
    mov dl, BOOTSECTORVIEW
    jmp dontscanfordir
  setfsview:
    mov dl, FSINFOVIEW
    jmp dontscanfordir
;-------------------------------------------------------
choosefatview:
  cmp byte ptr [fattype], FAT12
  jne tryfat16view

    mov eax, dword ptr [reserved]
    add eax, dword ptr [spf]
    cmp eax, dword ptr [sector]
    jbe okasis12
      sub eax, dword ptr [spf]
    okasis12:
    mov dword ptr [fat12start], eax

    mov dl, FAT12VIEW
  tryfat16view:
    cmp byte ptr [fattype], FAT16
    jne tryfat32view
    mov dl, FAT16VIEW
  tryfat32view:
    cmp byte ptr [fattype], FAT32
    jne donechoosingfat
    mov dl, FAT32VIEW
    donechoosingfat:
  jmp dontscanfordir
;-------------------------------------------------------
findstring:
  call getstring

  jcxz abortfindstring
    mov dx, offset searchingmsg
    call printbottom
    stringsearch:
    mov word ptr [stringbuffer+74], cx
    xor bx, bx
    xor si, si

    nextbyte:
    mov al, byte ptr [stringbuffer+si]
    cmp al, byte ptr [readbuffer+bx]
    je comparenextbyte
    cmp bx, si                          ; if so much of the string matched
    jae dontgolastsect                  ; until now that a sector was crossed
      add bx, 512

      dec byte ptr [subsector]          ; then back up to continue search
      jnz dontgolastsect

      dec dword ptr [sector]
      call rwsect
    dontgolastsect:
      sub bx, si
      xor si, si

    continuefindstring0:
    inc bx                              ; next byte in sector

    cmp bx, word ptr [bps]              ; last byte?
    je nextfindsector                   ; jump to next sector
    mov ah, bh
    shr ah, 1                           ; calculate our current subsector
    mov byte ptr [subsector], ah

    jmp nextbyte
stringnotfound:
  mov dx, offset stringerror
  call printerror
  jmp searchoptions
abortfindstring:
  call updatescreen
  jmp searchoptions

comparenextbyte:
  inc si                                ; next byte
  cmp si, word ptr [stringbuffer+74]    ; end of string?
  je mainmenu                           ; found string.
  jmp continuefindstring0
nextfindsector:
  mov eax, dword ptr [dataend]
  cmp eax, dword ptr [sector]
  je stringnotfound
  inc dword ptr [sector]
  call rwsect
  cmp byte ptr [status], ERROR
  je abortfindstring

  call checkabort
  je abortfindstring

  call printcounts
  xor bx, bx
  jmp nextbyte
;-------------------------------------------------------
fileoperations:

  mov dx, offset filemenu
  call printmenu

  getkeyagain5:
  call getkey

  cmp al, ESCAPE_KEY
  je mainmenu

    cmp ah, F1_KEY
    setne byte ptr [srflag]     ; set SAVE mode if equal, otherwise RESTORE
    je srfileoptions
    cmp ah, F2_KEY
    je srfileoptions

  jmp getkeyagain5
;-------------------------------------------------------
savechain:
  mov byte ptr [fromfat], 1
  call srcommon

  mov dword ptr [filesize], 0
  cmp byte ptr [chainflag], FAT_CHAIN
  je begincsave

    call spotinbx
    and bl, 11100000b                    ; chop off 0-31 bytes to set bx to
    add bx, offset readbuffer            ; the start of the current entry
    mov eax, dword ptr [bx+DIR_FILESIZE] ; filesize
    mov dword ptr [filesize], eax
    mov ax, word ptr [bx+DIR_CLUST_HIGH] ; high cluster word
    shl eax, 16
    mov ax, word ptr [bx+DIR_CLUST_LOW]  ; low cluster word

    mov dword ptr [sbackup], eax         ; back the cluster number up
    cmp eax, 2
    jb f2great                           ; outside of valid cluster range
    call cluster2sector
    cmp eax, dword ptr [dataend]
    ja f2great
    push eax
    mov eax, dword ptr [sbackup]
    call getfatentry
    mov dword ptr [sbackup], eax
    pop eax
    jmp startchainsaving

f2great:
  mov dx, offset greatmsg
  call printerror
  jmp srfileoptions

  begincsave:
  call getcurrententry
  cmp ebx, 2
  jb f2great
  mov dword ptr [sbackup], eax          ; current entry's data
  mov eax, ebx
  call cluster2sector
  cmp eax, dword ptr [dataend]
  ja f2great                            ; current entry is beyond data end

  startchainsaving:
  push ax
  call createfile
  pop ax
  cmp byte ptr [status], ERROR
  je srfileoptions

  chainsaveloop:
  movzx ebx, byte ptr [spc]             ; save sectors per cluster worth of
  mov dword ptr [value], ebx            ; sectors.
  call writefile
  cmp byte ptr [status], ERROR
  je srfileoptions

  mov eax, dword ptr [sbackup]
  call cluster2sector
  cmp eax, dword ptr [dataend]
  ja donechainsave

  push eax
  mov eax, dword ptr [sbackup]
  call getfatentry
  mov dword ptr [sbackup], eax
  pop eax
  jmp chainsaveloop

  donechainsave:
  cmp dword ptr [filesize], 0
  je notruncate

  mov ax, 4201h                         ; seek from current file position
  mov bx, word ptr [filehandle]
  xor cx, cx
  xor dx, dx
  int 21h

  shl edx, 16
  mov dx, ax

  cmp edx, dword ptr [filesize]
  jbe notruncate

  mov dx, offset truncatemsg
  call printbottom
  call getyn
  jnc notruncate

    mov ax, 4200h                       ; seek from start of file
    mov bx, word ptr [filehandle]
    mov dx, word ptr [filesize]
    mov cx, word ptr [filesize+2]
    int 21h

    xor cx, cx                          ; write to file, 0 bytes (truncate)
    mov ah, 40h
    mov bx, word ptr [filehandle]
    int 21h

  notruncate:


  call closefile
  call rwsect
  mov dx, offset donemsg
  call printerror

  jmp srfileoptions
;-------------------------------------------------------
restchain:
  call srcommon

  mov eax, dword ptr [sector]
  mov dword ptr [sbackup], eax

  call getcurrententry
  cmp byte ptr [chainflag], FAT_CHAIN
  je restclusts
    mov byte ptr [fromfat], 1
    call getfilesize
    call spotinbx
    and bl, 11100000b
;    cmp eax, dword ptr [readbuffer+bx+DIR_FILESIZE]
;    jb toosmallerr
    mov ax, word ptr [readbuffer+bx+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [readbuffer+bx+DIR_CLUST_LOW]
  restclusts:

  call openfile                         ; \/\/\ corrupts eax for below?

  rbuhs:

  mov dword ptr [cluster], eax
  call cluster2sector                   ; fix?  checking needed for sector.
  mov dword ptr [sector], eax
  mov al, byte ptr [spc]
  mov byte ptr [spcc], al

  dornsb:

  mov ah, 3Fh
  mov bx, word ptr [filehandle]
  mov cx, word ptr [bps]
  mov dx, offset writebuffer
  int 21h
  jc disperread

  cmp ax, cx
  je docwrite
    call rwsect
    cmp byte ptr [status], ERROR
    je srfileoptions
    push cs                             ; preserve bytes at end of sector
    pop es
    sub cx, ax
    mov si, offset readbuffer
    add si, ax
    mov di, offset writebuffer
    add di, ax
    rep movsb
  docwrite:
  mov byte ptr [rw], WRITE
  call rwsect
  cmp byte ptr [status], ERROR
  je srfileoptions
  cmp ax, cx
  jne donerestchain

  dec byte ptr [spcc]
  jz restnextclust
  inc dword ptr [sector]
  jmp dornsb
  restnextclust:

  mov eax, dword ptr [cluster]
  call getfatentry
  cmp eax, 0FFFFFF7h
  jae donerestchain
  cmp eax, 2
  jae rbuhs

  donerestchain:

    mov eax, dword ptr [sbackup]
    mov dword ptr [sector], eax
    call rwsect

    mov dx, offset donermsg
    call printerror

  jmp srfileoptions
  disperread:
    mov dx, offset errorread
    call printerror
    jmp srfileoptions
;-------------------------------------------------------
srcommon:
  pop bp
  push ax
  call getfilename
  pop ax
  jcxz srfileoptions
  cmp byte ptr [srflag], RESTORE
  jne skipffsr
    call findfile
    jnc filefound2
      mov dx, offset filenotfound
      call printerror
      jmp srfileoptions
    filefound2:
  skipffsr:
  push bp
  ret
;-------------------------------------------------------
savefile:
  call srcommon
  call getnos

  cmp byte ptr [status], ERROR
  je srfileoptions

  mov eax, dword ptr [sector]
  jmp endsavedrive
;-------------------------------------------------------
srfileoptions:
  cmp byte ptr [srflag], SAVE
  jne startfileops

  cmp byte ptr [drivetype], CDROM
  jne startfileops
    mov dx, offset cdfilemenu
    call printmenu
    jmp getkeyagain0

  startfileops:
    call printfilemenu
  getkeyagain0:
    call getkey

    cmp byte ptr [srflag], RESTORE
    je crfile
      cmp ah, F1_KEY
      je savefile
    crfile:
      cmp ah, F1_KEY
      je restfile

    cmp byte ptr [drivetype], CDROM
    je cdf2check

    cmp al, ESCAPE_KEY
    je fileoperations

    cmp ah, F2_KEY      ; bootsect
    je srsector0

    cmp byte ptr [drivetype], PHYSICAL
    je hdsfcheck

    cmp ah, F3_KEY
    je srfat1
    cmp ah, F4_KEY
    je srfat2
    cmp ah, F5_KEY
    je srroot
    cmp byte ptr [srflag], RESTORE
    je crdrive
      cmp ah, F6_KEY
      je dumpiso
    crdrive:
      cmp ah, F6_KEY
      je restdrive

    cmp byte ptr [chainflag], NO_CHAIN
    je getkeyagain0

    cmp byte ptr [srflag], RESTORE
    je crchain
      cmp ah, F7_KEY
      je savechain
    crchain:
      cmp ah, F7_KEY
      je restchain
    jmp getkeyagain0

    hdsfcheck:

    mov bx, 1CAh
    mov cx, 4
    mov al, F3_KEY
    mov si, offset p1

    csp:
    cmp ah, al
    je srpartition
    inc al
    add bx, 10h
    add si, 4
    loop csp

  cdf2check:
    cmp ah, F2_KEY
    je dumpiso

    cmp al, ESCAPE_KEY
    je mainmenu

  jmp getkeyagain0
;-------------------------------------------------------
srroot:
  call srcommon

  mov eax, dword ptr [root]
  xor edx, edx

  cmp byte ptr [fattype], FAT32
  jne userootsects
    mov dl, byte ptr [spc]
    jmp dorootsr
  userootsects:
    mov dx, word ptr [rootsectors]

  dorootsr:
  mov dword ptr [value], edx
  cmp byte ptr [srflag], SAVE
  je endsavedrive
  jmp endrestsectors
;-------------------------------------------------------
restdrive:
  mov eax, dword ptr [dataend]
  mov dword ptr [value], eax

  call srcommon
  xor eax, eax

endrestsectors:
  call readfile
  jmp srfileoptions
;-------------------------------------------------------
srpartition:
  mov eax, dword ptr [si]
  test eax, eax
  jz srfileoptions
  call srcommon

  push dword ptr [sector]
  xor edx, edx
  mov dword ptr [sector], edx
  call rwsect
  mov ebx, dword ptr [readbuffer+bx]
  mov dword ptr [value], ebx
  pop dword ptr [sector]
  cmp byte ptr [srflag], RESTORE
  je endrestsectors
;-------------------------------------------------------
endsavedrive:
  call savedata
  jmp srfileoptions
;-------------------------------------------------------
srfat1:
  mov eax, dword ptr [reserved]
  jmp srfat
;-------------------------------------------------------
srfat2:
  cmp byte ptr [fats], 2
  jb srfat1
  mov eax, dword ptr [fatend]
      ;-------------------------------------------------------
srfat:
  call srcommon
    mov edx, dword ptr [spf]
    mov dword ptr [value], edx
  cmp byte ptr [srflag], SAVE
  je endsavedrive
  jmp endrestsectors
;-------------------------------------------------------
srsector0:
  call srcommon
  xor eax, eax
  mov dword ptr [value], 1
  cmp byte ptr [srflag], SAVE
  je endsavedrive
  jmp endrestsectors
;-------------------------------------------------------
restfile:
  call srcommon
  call getfilesize
  movzx ebx, word ptr [bps]
  cmp eax, ebx
  jae filesizeok
  toosmallerr:

  mov dx, offset toosmall
  call printerror

  jmp srfileoptions

  filesizeok:  

;  mov eax, dword ptr [filesize]

  xor edx, edx
  div ebx

  mov ebx, dword ptr [dataend]
  sub ebx, dword ptr [sector]
  inc ebx

  cmp eax, ebx                          ; if there are more sectors in the
  jbe mvok                              ; file than there are remaining
    xchg eax, ebx                       ; on the partition; then set number
  mvok:                                 ; of partition sectors remaining
                                        ; as maxvalue
  mov dx, offset sectorsmsg
  call inputvalue

  cmp byte ptr [status], ERROR
  je srfileoptions

  mov eax, dword ptr [sector]
  jmp endrestsectors
;-------------------------------------------------------
jumptocluster:
  mov eax, dword ptr [lastcluster]
  mov dx, offset clustermsg
  call gethex
  jc mainmenu
  mov eax, ebx
  jmp jumptoeax
;-------------------------------------------------------
jumpto2:
  mov dx, offset pdfilemenu
  call printmenu

  getkeyagain11:
  call getkey

  cmp al, ESCAPE_KEY
  je mainmenu
  cmp ah, F1_KEY
  je jumptosector
  cmp ah, F2_KEY
  je jumptobootsector

  mov ebx, dword ptr [p1]
  cmp ah, F3_KEY
  je donejump

  mov ebx, dword ptr [p2]
  cmp ah, F4_KEY
  je donejump

  mov ebx, dword ptr [p3]
  cmp ah, F5_KEY
  je donejump

  mov ebx, dword ptr [p4]
  cmp ah, F6_KEY
  je donejump

  jmp getkeyagain11
;-------------------------------------------------------
jumpto:
  cmp byte ptr [drivetype], PHYSICAL
  je jumpto2

  cmp byte ptr [drivetype], CDROM
  jne doregularjumps
  mov dx, offset cdjumpmenu
  jmp docdjumps

  doregularjumps:
  mov dx, offset jumpmenu

  docdjumps:
  call printmenu

  getkeyagain2:
  call getkey

  cmp al, ESCAPE_KEY
  je mainmenu
  cmp ah, F1_KEY
  je jumptosector

  cmp byte ptr [drivetype], CDROM
  je getkeyagain2

  cmp ah, F2_KEY
  je jumptocluster
  cmp ah, F3_KEY
  je jumptobootsector
  cmp ah, F4_KEY
  je jumptofat1
  cmp ah, F5_KEY
  je jumptofat2
  cmp ah, F6_KEY
  je jumptoroot
  cmp ah, F7_KEY
  jne getkeyagain2

  jumptodata:
    mov ebx, dword ptr [datastart]
    jmp donejump
  jumptobootsector:
    xor ebx, ebx
    jmp donejump
  jumptofat1:
    mov ebx, dword ptr [reserved]
    jmp donejump
  jumptofat2:
    cmp byte ptr [fats], 2
    jb jumptofat1
    mov ebx, dword ptr [fatend]
    jmp donejump
  jumptoroot:
    mov ebx, dword ptr [root]

  donejump:
  cmp dword ptr [dataend], ebx
  jb mainmenu 
  mov dword ptr [sector], ebx
  call rwsect
  
  jmp mainmenu
;-------------------------------------------------------
jumptosector:
  mov eax, dword ptr [dataend]
  mov dx, offset sectormsg
  call inputvalue
  cmp byte ptr [status], ERROR
  je jumpto

  mov ebx, dword ptr [value]
  jmp donejump
;-------------------------------------------------------
jumptolastsect:
  mov ebx, dword ptr [dataend]
  jmp donejump
;-------------------------------------------------------
moveup:
  xor ax, ax
  mov dl, byte ptr [hl]
  cmp byte ptr [editmode], ASCIIEDIT
  je regularmoveup
  cmp byte ptr [displaymode], BINARY
  je binarymoveup
  regularmoveup:
    sub ax, 12
  binarymoveup:
    sub ax, 4
  jmp domove
;-------------------------------------------------------
movedown:
  xor ax, ax
  mov dl, byte ptr [hl]
  cmp byte ptr [editmode], ASCIIEDIT
  je regularmovedown
  cmp byte ptr [displaymode], BINARY
  je binarymovedown
  regularmovedown:
    add al, 12          ; see moveup
  binarymovedown:
    add al, 4
  jmp domove
;-------------------------------------------------------
moveleft:
  mov dl, byte ptr [hl]
  xor ax, ax
  cmp byte ptr [editmode], ASCIIEDIT
  je deconly
  cmp dl, 0
  je zero_left
    cmp dl, 5
    jne skipbinspecial
      dec dl
    skipbinspecial:
    dec dl
  jmp domove

  zero_left:
    cmp byte ptr [displaymode], HEX
    je dohexaddonly
      mov dl, 7
    dohexaddonly:
    inc dl
    deconly:
    dec ax
  jmp domove
;-------------------------------------------------------
moveright:
  mov dl, byte ptr [hl]
  xor ax, ax
  cmp byte ptr [editmode], DEFAULTEDIT
  jne sr_iax

  cmp byte ptr [displaymode], HEX
  je dohexrightcheck
    cmp dl, 8
  jmp rightcheck
  dohexrightcheck:
    cmp dl, 1
  rightcheck:
  je none_right

  cmp dl, 3
  jne skiprightadjust
    inc dl
  skiprightadjust:
    inc dl
  jmp domove

  none_right:
    mov dl, 0
  sr_iax:
    inc ax
      ;-------------------------------------------------------
domove:
  add ax, word ptr [spot]
  cmp ax, 512
  jae getkeyagain

  push word ptr [spot]          ; back old cursor spot up
  call movecursor               ; spot is changed to ax
  pop ax

  cmp byte ptr [displaymode], BINARY
  jne dontchangescreens
    mov bx, word ptr [spot]     ; figures out if we've crossed a 128-byte
    shl ax, 1                   ; barrier by checking if the high bits have
    shl bx, 1                   ; changed.  if so, then we need to redraw,
    cmp bh, ah                  ; otherwise there's no need to waste CPU.
    je dontchangescreens
    call printscreen
  dontchangescreens:
  call printoffset
jmp getkeyagain
;-------------------------------------------------------
; viewmode; see the variable definition for details

printview:

  mov bx, offset viewmode
  cmp byte ptr [bx], BOOTSECTORVIEW
  je bsview
  cmp byte ptr [bx], FAT12VIEW
  je fat12viewmode
  cmp byte ptr [bx], FAT16VIEW
  je fat16viewmode
  cmp byte ptr [bx], FAT32VIEW
  je fat32viewmode
  cmp byte ptr [bx], ROOTVIEW
  je dirview
  cmp byte ptr [bx], MBRVIEW
  je hd0view
  cmp byte ptr [bx], FSINFOVIEW
  je fsinfoviewmode

ifdef DEBUG
  cmp byte ptr [bx], DEBUGVIEW
  je debugviewmode
endif

;  call clearview

  ; [highlight]: 11223333h
  ;
  ;        11: Number of bytes to highlight on screen
  ;        22: Number of bytes deviating from [spot] to highlight for
  ;        3333: Starting [spot] to highlight from

  ret
;-------------------------------------------------------
readbufferinsi:         ; OUT:  si -> offset to current subsector buffer
  movzx ax, byte ptr [subsector]
  shl ax, 9
  mov si, offset readbuffer
  add si, ax
  ret
;-------------------------------------------------------
fsinfoviewmode:
  mov word ptr [xy], 2201h

  call readbufferinsi

  mov dword ptr [highlight], 0A0401E8h
  mov dx, offset fcs

  dofcssfc: 
  call printstring
  mov bx, word ptr [highlight]
; dec bx

  mov eax, dword ptr [si+bx]
  cmp eax, 0FFFFFFFFh
  jne vbik
    mov byte ptr [highlight+3], 07h
    call bshighlight
    mov dx, offset unknownmsg
    call printstring
    mov al, 00h
    mov cl, 3
    call printchar2
    jmp dtsc
  vbik:
  call bshighlight

  call printcount
  mov dx, offset valuebuffer
  call printstring
  dtsc:
  cmp byte ptr [highlight], 0E8h
  je dosfc
  ret

  dosfc:
  call gotonextline

  mov byte ptr [highlight+3], 0Ah
  mov byte ptr [highlight], 0ECh
  mov dx, offset sfc
  jmp dofcssfc
;-------------------------------------------------------
dirview:
  mov word ptr [xy], 2201h

  call readbufferinsi

  mov cx, word ptr [spot]

  xor bx, bx

  cmp cx, 64
  jb dirviewok
  dirviewnotok:
    sub cx, 32
    add bx, 32
  cmp bx, 416
  jae dirviewok
  cmp cx, 64
  jae dirviewnotok
  dirviewok:

  mov ch, 7

  processentry:

  cmp bx, 512          ; when we're looking at the very last entry in
  jb ncll1             ; a directory...a line remains that needs wiping.
    cmp ch, 1
    jne ncll1
    mov al, SPACE
    mov cl, 78
    call printchar2
    jmp doneentry
  ncll1:

  mov dx, offset attributesmsg
  call printstring

  mov dword ptr [highlight], 0601000Bh
  add word ptr [highlight], bx
  call bshighlight

  mov al, byte ptr [si+bx+DIR_ATTRIBUTES]

  mov dx, 'A' + (100h * ARCHIVE)
  call testattrib

  mov dx, 'D' + (100h * DIRECTORY)
  call testattrib

  mov dx, 'V' + (100h * VOLUME)
  call testattrib

  mov dx, 'S' + (100h * SYSTeM)
  call testattrib
  
  mov dx, 'H' + (100h * HIDDEN)
  call testattrib

  mov dx, 'R' + (100h * READONLY)
  call testattrib

  add byte ptr [xy], 9

  mov dx, offset createdmsg
  call printstring

  push bx
  add bx, 10h
  call printdate

  movzx dx, byte ptr [si+bx-03h]
  cmp dl, 199
  jb msok
    mov dl, 199
  msok:

  sub bx, 02h
  mov ax, word ptr [si+bx]
  call printtime
  pop bx

  mov dl, '.'
  call printchar

  mov dword ptr [highlight], 0101000Dh
  add word ptr [highlight], bx
  call bshighlight

  movzx ax, byte ptr [si+bx+0Dh]
  cmp al, 199
  jbe msecok
    mov al, 199
  msecok:
  xor dx, dx
  push bx
  mov bx, 10
  div bx
  pop bx
  add dl, 48
  call printchar

  add byte ptr [xy], 5

  mov dx, offset clustermsg
  call printstring

  mov dword ptr [highlight], 03020014h
  add word ptr [highlight], bx
  call bshighlight

  mov ax, word ptr [si+bx+DIR_CLUST_HIGH]
  call printhex
  mov dx, offset valuebuffer+6
  call printstring

  mov byte ptr [highlight+3], 04
  add word ptr [highlight], 6
  call bshighlight

  mov ax, word ptr [si+bx+DIR_CLUST_LOW]
  call printhex
  mov dx, offset valuebuffer+5
  call printstring

  dec ch
  jz doneentry

  call gotonextline

  halfdir:

  mov dx, offset accessedmsg    ; last accessed
  call printstring

  push bx
  add bx, 12h
  call printdate
  pop bx

  add byte ptr [xy], 5

  mov dx, offset modifiedmsg    ; last modified
  call printstring

  push bx
  add bx, 18h
  call printdate
  xor dx, dx
  sub bx, 02h
  call printtime
  pop bx


  add byte ptr [xy], 7

  mov dx, offset sizemsg
  call printstring

  mov dword ptr [highlight], 0A04001Ch
  add word ptr [highlight], bx
  call bshighlight

  mov eax, dword ptr [si+bx+DIR_FILESIZE]
  call printcount
  mov dx, offset valuebuffer
  call printstring

  call gotonextline
  add bx, 32
  dec ch
  jnz processentry
  doneentry:
  ret
;-------------------------------------------------------
fat32viewmode:
  mov word ptr [xy], 2204h
  mov dword ptr [highlight], 07040000h

  call readbufferinsi

  mov bx, 144

  loopline2:
  cmp word ptr [spot], bx
  jb donesetline2

    add si, 36
    add bx, 36
    add word ptr [highlight], 36

  cmp bx, 432
  jne loopline2

  donesetline2:

  mov cl, 9
  mov ch, 7

  fat32loop:

  call bshighlight
  add word ptr [highlight], 4

  lodsd

  call printhex
  mov dx, offset valuebuffer+2
  call printstring

  mov dl, SPACE
  call printchar

  cmp ch, 1
  jne skipskip2
  cmp cl, 8
  jne skipskip2
    cmp bx, 432
    jne skipskip2
    mov al, SPACE
    mov cl, 55
    jmp printchar2
  skipskip2:

  dec cl
  jnz fat32loop

  inc byte ptr [xy+1]
  mov byte ptr [xy], 4
  mov cl, 9

  dec ch
  jnz fat32loop

ret
;-------------------------------------------------------
fat16viewmode:
  mov word ptr [xy], 2203h
  mov dword ptr [highlight], 04020000h

  call readbufferinsi

  mov bx, 120

  loopline:
  cmp word ptr [spot], bx
  jb donesetline

    add si, 30
    add bx, 30
    add word ptr [highlight], 30

  cmp bx, 450
  jne loopline

  donesetline:

  mov cl, 15
  mov ch, 7

  fat16loop:

  call bshighlight
  add word ptr [highlight], 2

  lodsw

  call printhex
  mov dx, offset valuebuffer+5
  call printstring

  mov dl, SPACE
  call printchar

  cmp ch, 1
  jne skipskip
    cmp bx, 450
    jne skipskip
    mov al, SPACE
    mov cl, 69
    jmp printchar2
  skipskip:

  dec cl
  jnz fat16loop

  inc byte ptr [xy+1]
  mov byte ptr [xy], 3
  mov cl, 15

  dec ch
  jnz fat16loop

ret
;-------------------------------------------------------
fat12viewmode:

  mov dword ptr [highlight], 03020000h

  xor ax, ax                            ; this little loop figures out
  mov bx, word ptr [spot]               ; where to start displaying
  buf12fix:                             ; fat12 entries, since an entire
  cmp bx, 108                           ; subsector (512 bytes) of 3-nibbles
  jb donebuffix                         ; won't fit in the view area.
    sub bx, 27
    add ax, 27
    add word ptr [highlight], 27
    cmp ax, 300
    jbe buf12fix
  donebuffix:

  movzx dx, byte ptr [subsector]        ; displaying fat12 entries, we
  mov si, offset readbuffer             ; need to figure out what subsector
  shl dx, 9                             ; we're looking at. (subsector*512)
  add si, dx

  call fat12pad

  add si, ax

  mov eax, dword ptr [sector]

  mov ebx, dword ptr [fat12start]
  cmp ebx, eax
  ja dodec12
  sub eax, ebx
  jmp donesub12
  dodec12:
    dec eax
  donesub12:

    movzx ebx, byte ptr [subsector]
    add eax, ebx
    mov cx, word ptr [bps]
    shr cx, 10
    shl eax, cl

  xor edx, edx
  mov ebx, 3
  div ebx

  mov word ptr [xy], 2203h

  cmp dl, 0
  je fat12loop
  dec word ptr [highlight]
  dec si
  cmp dl, 1
  je ssection
  
  fat12loop:

    lodsw
    call print12bits
    dec si
    ssection:
    lodsw
    xchg al, ah
    rol ax, 4
    call print12bits
    inc word ptr [highlight]

  jmp fat12loop
print12bits:
  mov dl, SPACE
  call printchar
  call bshighlight
  inc word ptr [highlight]
  call printhex
  mov dx, offset valuebuffer+6
  call printstring
  cmp byte ptr [xy], 75
  jne rp12
    inc byte ptr [xy+1]
    mov byte ptr [xy], 3
  rp12:
  mov cx, 2903h
  cmp word ptr [xy], cx
  jb rp13
    mov al, SPACE
    mov cl, 4
    pop dx
    jmp printchar2
  rp13:
  ret
;-------------------------------------------------------
hd0common:
  mov al, 20
  mul cl
  inc al
  mov byte ptr [xy], al
  inc byte ptr [xy+1]
  ret
;-------------------------------------------------------
hd0view:
  mov byte ptr [xy], 01h
  xor cx, cx

  call readbufferinsi

  nextpart:
  mov byte ptr [xy+1], 22h

  mov dx, offset partition
  call printstring
  mov dl, SPACE
  call printchar
  mov ax, 10h
  mul cx
  mov bx, 1BEh
  add bx, ax
  mov dx, cx
  add dl, '1'
  call printchar
  mov dl, ':'
  call printchar

  call hd0common

  mov dx, offset mboot
  call printstring

  mov word ptr [highlight+2], 0201h
  mov word ptr [highlight], bx
  call bshighlight

  mov al, byte ptr [si+bx]
  call printhex
  mov dx, offset valuebuffer+7
  call printstring

  mov dl, SPACE
  call printchar
  cmp al, 80h
  je partactive

  push cx
  mov al, SPACE
  mov cl, 8
  call printchar2
  pop cx
  jmp donepart

  partactive:
  mov dl, '('
  call printchar
    mov dx, offset active
    call printstring
    mov dl, ')'
    call printchar
  donepart:

  call hd0common

  mov dx, offset startchs
  call printchs

  call hd0common

  mov dx, offset mtype
  call printstring

  mov word ptr [highlight+2], 0201h
  mov word ptr [highlight], bx
  add word ptr [highlight], 4

  call bshighlight

  mov al, byte ptr [si+bx+4]
  call printhex
  mov dx, offset valuebuffer+7
  call printstring

  mov dl, SPACE
  call printchar

  mov dx, offset part00
  cmp al, 00h
  je showpart

  mov dx, offset part01
  cmp al, 01h
  je showpart

  mov dx, offset part04060E
  cmp al, 04h
  je showpart
  cmp al, 06h
  je showpart
  cmp al, 0Eh
  je showpart

  mov dx, offset part0B0C
  cmp al, 0Bh
  je showpart
  cmp al, 0Ch
  je showpart

  mov dx, offset part050F
  cmp al, 05h
  je showpart
  cmp al, 0Fh
  je showpart

;16,1B,1C,1E,8D,90,91,92,97,98,9A,9B are all hidden fat

  mov dx, offset parthid
  cmp al, 16h
  je showpart
  cmp al, 1Bh
  je showpart
  cmp al, 1Ch
  je showpart
  cmp al, 1Eh
  je showpart
  cmp al, 8Dh
  je showpart
  cmp al, 90h
  je showpart
  cmp al, 91h
  je showpart
  cmp al, 92h
  je showpart
  cmp al, 97h
  je showpart
  cmp al, 98h
  je showpart
  cmp al, 9Ah
  je showpart
  cmp al, 9Bh
  je showpart

  mov dx, offset part07
  cmp al, 07h
  je showpart

  mov dx, offset part83
  cmp al, 83h
  je showpart

  mov dx, offset partA5
  cmp al, 0A5h
  je showpart

  push cx                       ; clear space after partition number
    mov al, SPACE
    mov cl, 10
    call printchar2
  pop cx

  jmp dontshowpart

  showpart:
    push dx
    mov dl, '('
    call printchar
    pop dx
    call printstring
    mov dl, ')'
    call printchar
    mov dl, SPACE
    call printchar
    call printchar

  dontshowpart:

  call hd0common
  mov dx, offset endchs

  add bx, 4

  call printchs
  call hd0common

  mov dx, offset startlba
  call printstring
  mov dl, SPACE
  call printchar

  mov word ptr [highlight+2], 0A04h
  mov word ptr [highlight], bx
  add word ptr [highlight], 4
  call bshighlight

  mov eax, dword ptr [si+bx+04h]
  call printcount
  mov dx, offset valuebuffer
  call printstring

  call hd0common

  mov dx, offset psize
  call printstring

  mov word ptr [highlight+2], 0A04h
  mov word ptr [highlight], bx
  add word ptr [highlight], 8
  call bshighlight

  mov eax, dword ptr [si+bx+08h]
  call printcount
  mov dx, offset valuebuffer
  call printstring

  inc cx

  call hd0common
  cmp cx, 4
  jb nextpart

  ret
;-------------------------------------------------------
bsview:
  mov word ptr [xy], 2201h

  call readbufferinsi

  mov bx, offset highlight

  movzx eax, word ptr [0Bh+si]
  mov dx, offset mbps
  mov dword ptr [bx], 0502000Bh

  call basicbs

  mov al, byte ptr [0Dh+si]
  mov dx, offset mspc
  mov dword ptr [bx], 0301000Dh

  call basicbs

  mov ax, word ptr [si+0Eh]
  mov dx, offset mreserved
  mov dword ptr [bx], 0502000Eh

  call basicbs

  mov dx, offset mfats
  mov al, byte ptr [si+10h]
  mov dword ptr [bx], 03010010h

  call basicbs

  mov ax, word ptr [si+11h]
  mov dx, offset mrootentries
  mov dword ptr [bx], 05020011h

  call basicbs

  mov ax, word ptr [si+13h]
  mov word ptr [bx], 0013h
  test ax, ax
  jnz sipcorrect
  mov eax, dword ptr [si+20h]
  mov dword ptr [bx], 0A040020h
  sipcorrect:
  mov dx, offset msip

  call basicbs

  mov al, byte ptr [si+15h]
  mov dx, offset mdb
  mov dword ptr [bx], 03010015h

  call basicbs

  mov ax, word ptr [si+16h]
  mov dword ptr [bx], 0A020016h
  test ax, ax
  jnz spfcorrect
    mov eax, dword ptr [si+24h]
    mov dword ptr [bx], 0A040024h
  spfcorrect:
  mov dx, offset mspf

  call basicbs

  mov eax, dword ptr [si+1Ch]
  mov dx, offset mhs
  mov dword ptr [bx], 0A04001Ch

  call basicbs

  mov eax, dword ptr [si+2Ch]
  mov dx, offset mrootc
  mov word ptr [bx], 002Ch

  call basicbs

  mov ax, word ptr [si+30h]
  mov dx, offset mfsis
  mov dword ptr [bx], 05020030h

  call basicbs

  mov ax, word ptr [si+32h]
  mov dx, offset mbackup
  mov word ptr [bx], 0032h

  call basicbs

  mov al, byte ptr [si+24h]
  mov dword ptr [bx], 03010024h
  cmp word ptr [si+16h], 0
  jne ldncorrect
    mov al, byte ptr [si+40h]
    mov word ptr [bx], 0040h
  ldncorrect:
  mov dx, offset mldn

        ;  jmp basicbs
        ;-------------------------------------------------------
basicbs:
  call printstring
  call spaceandcolon
  call printcount
  mov di, offset valuebuffer
  mov cl, 0Ah
  locateloop:
  cmp cl, 01
  je doneshift
    cmp byte ptr [di], '0'
    jne doneshift
      inc di
    loop locateloop
  doneshift:

  mov byte ptr [bx+3], cl
  mov dx, di

  call bshighlight

  call printstring

;  mov al, byte ptr [si+15h]
;  mov dx, offset mdb
;  mov dword ptr [bx], 03010016h

  cmp word ptr [bx], 0015h
  jne npldn2
  mov al, byte ptr [si+15h]
  cmp al, 0F0h
  jb npldn2
    mov dx, offset mfixed
    cmp al, 0F8h
    je itisfixed
      mov dx, offset mremovable
    itisfixed:
    call printstring

    add cl, 5
  npldn2:

  cmp word ptr [si+16h], 0
  je isldn
  cmp word ptr [bx], 0024h
  jne isldn
  mov al, byte ptr [si+24h]
  jmp isldn2

  isldn:
  cmp word ptr [bx], 0040h
  jne npldn
  mov al, byte ptr [si+40h]
  isldn2:
  cmp al, 80h
  jb npldn
  cmp al, 89h
  ja npldn
    mov dl, SPACE
    call printchar
    mov dl, '('
    call printchar
    mov dl, al
    sub dl, 80h-48
    call printchar
    mov dl, ')'
    call printchar
    add cl, 4
  npldn:

  neg cl
  add cl, 0Dh
  mov al, SPACE
  call printchar2

  xor eax, eax
      ;-------------------------------------------------------
nextviewline:
  cmp byte ptr [xy], 55
  ja gotonextline
  mov byte ptr [xy], 40
  ret

gotonextline:
  inc byte ptr [xy+1]
  mov byte ptr [xy], 1
  ret
;-------------------------------------------------------
colorize:                               ; in: cl=number of chars to color
  pusha                                 ;     al=color to use
  call cbuffer_offset

  ccloop:
  inc di
  stosb
  dec cl
  jnz ccloop

  popa
  ret
;-------------------------------------------------------
bshighlight:
  pusha
  mov cl, 0Ah

;--- make sure not to modify attribs beyond col 80
  mov al, 80
  sub al, byte ptr [xy]
  jc @F
  cmp al, cl
  jnc @F
  mov cl, al
@@:

  mov al, DEFAULTCOLOR
  call colorize
  mov cl, byte ptr [highlight+3]

  movzx bx, byte ptr [highlight+2]
  mov dx, word ptr [highlight]
  cmp word ptr [spot], dx
  jb notonspot
  add dx, bx
  cmp word ptr [spot], dx
  jae notonspot
    mov al, HIGHLIGHTCOLOR
    notonspot:
    call colorize
  popa
  ret
;-------------------------------------------------------
nextsect1000:
  mov eax, dword ptr [sector]
  add eax, 100
jmp donextsect
;-------------------------------------------------------
nextsect:
  inc byte ptr [subsector]
  checkcursorbounds:
  movzx dx, byte ptr [subsector]        ; subsector * 512
  shl dx, 9
  mov ax, word ptr [bps]                ; if (subsector*512 <= bps), then
  cmp ax, dx                            ; we've not paged down completely
  jbe dorns
    sub ax, dx
    dec ax
    cmp word ptr [spot], ax
    jbe incursorbounds
      call movecursor
    incursorbounds:
    jmp mainmenu
  dorns:
  mov eax, dword ptr [sector]
  inc eax
        ;-------------------------------------------------------
donextsect:
  cmp eax, dword ptr [dataend]
  jbe gonextsect
  sub eax, dword ptr [dataend]
  dec eax
  gonextsect:
  mov dword ptr [sector], eax
  call rwsect
  jmp mainmenu
;-------------------------------------------------------
lastsect:
  sub byte ptr [subsector], 1
  jnc mainmenu

  mov eax, dword ptr [sector]
  dec eax
jmp dolastsect
;-------------------------------------------------------
lastsect1000:
  mov eax, dword ptr [sector]
  sub eax, 100
;-------------------------------------------------------
dolastsect:
  cmp eax, dword ptr [sector]
  jb golastsect
  not eax

  mov ebx, dword ptr [dataend]
  sub ebx, eax
  mov eax, ebx
  golastsect:
  mov dword ptr [sector], eax
  call rwsect
  mov dx, word ptr [bps]
  dec dx
  shr dx, 9
  mov byte ptr [subsector], dl
  jmp checkcursorbounds
;-------------------------------------------------------
setcdvar:
  mov bx, 50h
  cmp byte ptr [rwfunction], CDCOOKED
  je norawadjust
    add bx, 18h
  norawadjust:
  mov eax, dword ptr [readbuffer+bx]
  sub eax, CD_SECTOR_OFFSET+1
  mov dword ptr [dataend], eax
  ret
;-------------------------------------------------------
setvariables:
  call setseeds2

  cmp byte ptr [drivetype], CDROM
  je setcdvar
  test byte ptr [rwfunction], CRW
  jz cdbpsset
    mov word ptr [bps], 512
  cdbpsset:
  cmp byte ptr [drivetype], PHYSICAL
  jne logicalsetvars

    push cs                             ; sets variables p1-p4
    pop es                              ; for jumping to partitions
    mov di, offset p1                   ; on physical drives
    mov si, offset readbuffer + 1c6h
    mov cx, 4
    partition_data_fill:
    movsd
    add si, 0Ch
    loop partition_data_fill

  cmp byte ptr [rwfunction], FILEFUNC  ; file read?
  je setffparam
  test byte ptr [rwfunction], PRW      ; non-physical function?
  jnz donesetphysvars

    mov ah, 08h
    push 0000h                          ; damned bios bug
    pop es                              ; circumvention
    xor di, di
    mov dl, byte ptr [drive]
    call int13
    inc dh
    mov byte ptr [heads], dh
    mov byte ptr [sectors], cl
    and byte ptr [sectors], 00111111b
    mov byte ptr [cylinders], cl
    shl word ptr [cylinders], 2
    mov byte ptr [cylinders], ch

    movzx eax, word ptr [cylinders]     ; CHS -> LBA
    movzx ebx, dh                       ; heads*cylinders
    mul ebx
    add eax, ebx                        ; + heads
    mov bl, byte ptr [sectors]
    mul ebx                             ; * sectors
    dec eax                             ; - 1
    sub eax, dword ptr [drivestart]
    mov dword ptr [dataend], eax

  cmp byte ptr [rwfunction], NEWINT13
  jne donesetphysvars

    mov si, offset diskinfobuffer
    mov word ptr [si], 1Ah
    mov dl, byte ptr [drive]
    mov ah, 48h                         ; get drive parameters

    call int13                          ; call bios code

    mov eax, dword ptr [si+10h]
    dec eax                             ; remove for HUGE hd support?
    sub eax, dword ptr [drivestart]
    mov dword ptr [dataend], eax

    mov ax, word ptr [si+18h]
    mov word ptr [bps], ax

;     mov eax, dword ptr [si+14h]
;     mov dword ptr [dataend2], eax     ; uncomment for (some) support
;     dec dword ptr [dataend]           ; for HDs that are HUGE
;     sbb dword ptr [dataend2], 0       ; this should never be required
;                                       ; as it goes beyond 2tb
  donesetphysvars:
  ret
  logicalsetvars:
    xor eax, eax
    mov dword ptr [rootc], eax          ; default root cluster = 0
    mov al, byte ptr [readbuffer+0Dh]   ; sectors per cluster
    mov byte ptr [spc], al

    mov dl, 0FFh
    setspcmd:
      inc dl
      shr al, 1
    jnz setspcmd

    mov byte ptr [spcmd], dl

    mov ax, word ptr [readbuffer+0Eh]   ; number of reserved sectors
    mov dword ptr [reserved], eax
    mov al, byte ptr [readbuffer+10h]   ; number of fat tables
    mov byte ptr [fats], al
    mov ax, word ptr [readbuffer+11h]   ; maximum number of root entries
    mov word ptr [rootentries], ax
    shr ax, 4                           ; 16 entries in one sector
    mov word ptr [rootsectors], ax      ; # of entries/16 = # of sectors

    mov ax, word ptr [readbuffer+16h]   ; sectors per fat
    test ax, ax
    jnz setspf
      mov eax, dword ptr [readbuffer+36]
      mov dword ptr [spf], eax
    setspf:
    mov dword ptr [spf], eax

    movzx eax, word ptr [readbuffer+13h]        ; sectors in partition
    test ax, ax
    jnz lessthan32mb
      mov eax, dword ptr [readbuffer+20h]
    lessthan32mb:
    dec eax
    mov dword ptr [dataend], eax

      sub eax, dword ptr [spf]
      cmp byte ptr [fats], 2
      jb skipsub2
        sub eax, dword ptr [spf]
      skipsub2:
      sub eax, dword ptr [reserved]

      movzx ebx, word ptr [rootsectors]
      sub eax, ebx
      mov cl, byte ptr [spcmd]
      shr eax, cl

      mov byte ptr [fattype], FAT32
      cmp eax, 65525
      jae goodnumcluster                ; jump if not fat16 or less
      mov byte ptr [fattype], FAT16
      cmp eax, 4085
      jae goodnumcluster                ; jump if not fat12
        mov byte ptr [fattype], FAT12
      goodnumcluster:
      add eax, 2
      mov dword ptr [lastcluster], eax

    mov eax, dword ptr [spf]
    movzx ebx, byte ptr [fats]
    mul ebx
    add eax, dword ptr [reserved]       ; spf * fats + reserved = root
    mov dword ptr [root], eax

    cmp byte ptr [fattype], FAT32
    jne not_fat32

    push eax
      mov al, byte ptr [readbuffer+40h] ; hard drive number
      mov byte ptr [hdnumber], al
      mov ax, word ptr [readbuffer+32h] ; backup boot sector
      mov word ptr [backupbs], ax
      mov ax, word ptr [readbuffer+30h] ; file system info sector
      mov word ptr [fsinfo], ax
      movzx ax, byte ptr [spc]
      mov word ptr [rootsectors], ax
      mov eax, dword ptr [readbuffer+44]
      mov dword ptr [rootc], eax

      sub eax, 2
      jc wrongrootc
      mov cl, byte ptr [spcmd]
      shl eax, cl
      add dword ptr [root], eax
      wrongrootc:
    pop eax
    jmp isfat32

    not_fat32:

    mov al, byte ptr [readbuffer+24h]   ; hard drive number
    mov byte ptr [hdnumber], al
    movzx eax, word ptr [rootsectors]
    add eax, dword ptr [root]           ; calculate start of data area

  isfat32:

  cmp eax, dword ptr [root]
  jne datastartiscorrect
    mov bl, byte ptr [spc]
    add eax, ebx
  datastartiscorrect:
    mov dword ptr [datastart], eax

    mov eax, dword ptr [reserved]
    add eax, dword ptr [spf]
    mov dword ptr [fatend], eax         ; calculate end of fat 1 area

    movzx eax, word ptr [bps]           ; calculate bytes per cluster
    mov bl, byte ptr [spc]
    mul ebx
    mov dword ptr [bpc], eax

    test byte ptr [rwfunction], LRW
    jnz donegetvars

    ; lock partition
    mov cx, 084Ah
    cmp byte ptr [fattype], FAT32
    jne fat1xlock
      mov ch, 48h
    fat1xlock:

;--- japheth: windows complains if drive is an USB memory stick.
;--- hence don't lock if running on NT!
    cmp [hVdd],-1
    jnz donegetvars

    mov bl, byte ptr [drive]
    inc bl
    mov dx, 1
    mov bh, 1
    mov ax, 440Dh       ; lock the drive for windows
    int 21h

    mov bh, 04h         ; locks the drive for real dos
    mov ax, 440Dh       ; i don't quite understand why i must lock it twice
    int 21h             ; some sort of OS bug i guess
  donegetvars:
    ret

  setffparam:
    mov eax, dword ptr [rwfilesize]
    shr eax, 9                          ; \Fix/ ?
    jz donesetff
    dec eax
    donesetff:
    sub eax, dword ptr [drivestart]
    mov dword ptr [dataend], eax
  ret
;------------------------------------------------------------
dumpiso:
  call srcommon
  call createfile
  cmp byte ptr [status], ERROR
  je srfileoptions
  cmp byte ptr [drivetype], CDROM
  jne drivedump

  push cs
  pop es
  mov di, offset readbuffer
  mov cx, word ptr [bps]
  mov al, 0
  rep stosb

  mov cx, word ptr [bps]
  mov dx, offset readbuffer
  mov bx, word ptr [filehandle]
  mov si, 10h
  isoloop:
  mov ah, 40h                           ; write to file (10 blank sectors)
  int 21h                               ; to the beginning of the iso
  jnc noisoerror                        ; since we can't read the first 10
                                        ; sectors on a CD
    mov dx, offset filewerror
    call printerror
  jmp srfileoptions

  noisoerror:

  dec si
  jnz isoloop

  drivedump:

  xor eax, eax
  mov edx, dword ptr [dataend]
  inc edx
  mov dword ptr [value], edx
  call writefile
  cmp byte ptr [status], ERROR
  pushf
    call closefile
    call updatescreen
  popf
  je srfileoptions

    mov dx, offset donemsg
    call printerror

  jmp srfileoptions
;-------------------------------------------------------





;*******************************************************
; CALLS
;*******************************************************
include FATFS.WDE
;-------------------------------------------------------
printchs:
  call printstring
  mov dl, SPACE
  call printchar
  movzx eax, byte ptr [si+bx+3]
  mov ah, byte ptr [si+bx+2]
  shr ah, 6

  mov word ptr [highlight+2], 0402h
  mov word ptr [highlight], bx
  add word ptr [highlight], 2

  call bshighlight

  call printcount
  mov dx, offset valuebuffer+6
  call printstring

  mov dl, '/'
  call printchar

  mov word ptr [highlight+2], 0301h
  dec word ptr [highlight]

  call bshighlight

  movzx eax, byte ptr [si+bx+1]
  call printcount
  mov dx, offset valuebuffer+7
  call printstring
  mov dl, '/'
  call printchar

  mov byte ptr [highlight+3], 02h
  inc word ptr [highlight]
  call bshighlight

  movzx eax, byte ptr [si+bx+2]
  and al, 111111b
  call printcount
  mov dx, offset valuebuffer+8
  jmp printstring
;-------------------------------------------------------
; IN: AL = attribute bits
;     DH = bit to test for
;     DL = character to print if bit is set in AL
;
testattrib:
  test al, dh
  jnz printchar
    mov dl, '-'
  jmp printchar
;-------------------------------------------------------
finddirectory:                  ;IN: SI=readbuffer
  push cx                       ;    BX=offset in readbuffer

                                ; not found: carry set
                                ; found    : carry cleared
  cmp byte ptr [si+bx], 0
  je notfound

  flok:
;  mov ch, byte ptr [bps+1]              ; 16 entries every 512 bytes
;  shl ch, 4                             ; this puts 16 in ch if bps is 512
  mov ch, 16

  nextentry:

;  cmp byte ptr [si+12+bx], 0           ; NT series *does* use this byte,
;  jne notfound                         ; so it may not be 0 on drives that
;                                       ; have been messed with by NT
  mov cl, 10

  cmp byte ptr [si+bx], 0               ; first byte zero?
  je allzero

  test byte ptr [si+bx+DIR_ATTRIBUTES], 11000000b
  jnz notfound                          ; top two bits of attribute are
                                        ; reserved.  can't be used.
  cmp byte ptr [si+bx+DIR_ATTRIBUTES], 0Fh
  je lfn                                ; if attribute is 0F, then it's lfn

  notlfn:
    inc cl
    cmp byte ptr [si+0Dh+bx], 199               ; tenth of a second for
    ja notfound                                 ; creation time (0-199)
    
    mov ax, word ptr [si+18h+bx]                ; test the date
                                                ; to see if it exceeds any
                                                ; hour/minute/etc boundaries
    test al, 00011111b
    jz notfound
    shr ax, 5
    and al, 00001111b
    jz notfound
    cmp al, 12
    ja notfound

    mov ax, word ptr [si+10h+bx]                ; test the date
    test ax, ax
    jz dontcheckseconddate
    test al, 00011111b
    jz notfound
    shr ax, 5
    and al, 00001111b
    jz notfound
    cmp al, 12
    ja notfound
    dontcheckseconddate:

    mov ax, word ptr [si+bx+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [si+bx+DIR_CLUST_LOW]

    cmp eax, 0FFFFFF7h                          ; cluster can't be EOC and
    jae notfound                                ; the top nibble must = 0
    cmp dword ptr [si+16h+bx], 0                ; pointless?
    je notfound

    test byte ptr [si+bx+DIR_ATTRIBUTES], DIRECTORY  ; directory?
    jz entrynotdirectory
      test byte ptr [si+bx+DIR_ATTRIBUTES], VOLUME   ; can't also be a label.
      jnz notfound
      cmp dword ptr [si+bx+DIR_FILESIZE], 0          ; filesize must = 0   
      jne notfound
    entrynotdirectory:

    cmp byte ptr [si+bx], 20h           ; first character cannot be a space
    je notfound
    cmp byte ptr [si+bx], 0E5h          ; first character can be E5h (del'd)
    je charok
      kctfn:
      mov al, byte ptr [si+bx]
      call extvalidfilechar
      jc notfound
      charok:

    inc bx
    dec cl
    jnz kctfn
    jmp donextentry

  lfn:

  cmp word ptr [si+bx+DIR_CLUST_LOW], 0         ; low cluster word must = 0
  jne notfound                                  ; for long file names

  mov al, byte ptr [si+bx]

;  cmp al, 0ffh                                  ; wtf?
;  je nextletter
  cmp al, 0                     ; first character can't be null
  je notfound
  cmp al, 0e5h
  je nextletter
  ; the first character of long file names details what part of the LFN
  ; it is (bits 0-5) and whether it's the last (bit 6).  files can only
  ; be 255 characters at maximum, however, and each LFN entry stores 13
  ; characters.  bits 0-5, therefore, should not have a value > 20
  ; and bit 7 should never be set
  and al, 10111111b
  cmp al, 20
  ja notfound

  nextletter:
    inc bx
    mov al, byte ptr [si+bx]
    cmp al, 0
    je letterok
    cmp al, 0ffh
    je letterok
    cmp al, 20h
    je letterok
    cmp al, 7eh                         ; extended characters are not valid
    ja notfound                         ; though...they should be?
    cmp al, 20h
    jb notfound

    letterok:

  dec cl
  jnz nextletter
;  mov ax, bx                            ; odd sector size support
;  shr ax, 9
;  mov byte ptr [subsector], al

  inc bx
  donextentry:
  add bx, 21
  dec ch
  jnz nextentry

  founddir:
    pop cx
    clc
    ret
  notfound:
    pop cx
    stc
    ret

  allzero:
    mov cl, 32
    allzero2:
    cmp byte ptr [si+bx], 0
    jne notfound
    inc bx
    dec cl
    jnz allzero2
    dec ch
    jnz allzero
    jmp founddir
;-------------------------------------------------------
findcommon:
  pop word ptr [calladdress]
  mov dx, offset searchingmsg
  call printbottom

  call checkabort
  je abortfindstring

  call printcounts
  mov si, offset readbuffer
  mov ax, word ptr [bps]
  dec ax
  shr ax, 9
  cmp byte ptr [subsector], al
  jb dontrw
    mov eax, dword ptr [dataend]
    cmp dword ptr [sector], eax
    je stringnotfound
    inc dword ptr [sector]
    call rwsect
    cmp byte ptr [status], ERROR
    je abortfindstring

  jmp dontinc
  dontrw:

  inc byte ptr [subsector]
  mov al, byte ptr [subsector]
  shl ax, 9
  add si, ax

  dontinc:
  push word ptr [calladdress]
  ret
;-------------------------------------------------------
spaceandcolon:                  ; i don't like this function, it was created
  mov dl, ':'                   ; for optimal code size instead of clean,
  call printchar                ; reusable code
  mov dl, SPACE
  mov cl, 63                    ; it places the cursor in the right position
  cmp byte ptr [xy], 47         ; to display the next string when showing
  ja loopwipeview               ; the bootsector view
  mov cl, 23
  loopwipeview:
  call printchar
  cmp byte ptr [xy], cl
  jb loopwipeview
  ret
;-------------------------------------------------------
readfile:                       ; IN: eax start sector
  mov dx, offset readingmsg     ;     d:[value] # of sectors to write
  call printbottom              ; OUT: sectors written to disk from file

  mov edx, eax
  add edx, dword ptr [value]
  jc invalidperror
  dec edx
  cmp edx, dword ptr [dataend]
  ja invalidperror

  push eax
  call getfilesize
    mov eax, dword ptr [value]
    movzx edx, word ptr [bps]
    mul edx
    cmp dword ptr [filesize], eax
  pop eax

  mov dx, offset toosmall
  jb printerror

  mov byte ptr [handling], QUERY_SKIP
  push dword ptr [sector]
  mov dword ptr [sector], eax
  call openfile

  readfileloop:

  mov ah, 3Fh                           ; read 512 bytes of the file
  mov bx, word ptr [filehandle]         ; directly into the write buffer
  mov cx, word ptr [bps]                ; bad idea?
  mov dx, offset writebuffer
  int 21h

  jnc noreaderror
    mov dx, offset errorread
    call printerror
    jmp donefileread

  noreaderror:

    call checkabort
    jne keepreadingfile
    mov dx, offset abortdmsg
    call printerror
    jmp donefileread

  keepreadingfile:

  mov byte ptr [rw], WRITE
  call rwsect

  cmp byte ptr [status], ERROR
  je donefileread

  inc dword ptr [sector]
  call printcounts

  dec dword ptr [value]
  jnz readfileloop

  donefileread:
  call closefile
  mov byte ptr [handling], ABORT_OPERATION
  pop dword ptr [sector]
  push word ptr [status]
  call rwsect
  pop word ptr [status]
  call updatescreen

  mov dx, offset donermsg
  cmp byte ptr [status], ERROR
  jne printerror
  ret
;-------------------------------------------------------
printentry:                             ; prints the fat entry the cursor
  cmp byte ptr [region], FAT_AREA       ; is currently in, in the top
  jne abortentry                        ; right of the screen

    call getentrynumber
    call printhex

    mov byte ptr [xy], 34h
    mov dx, offset valuebuffer+1
    call printstring

  abortentry:
  ret
;-------------------------------------------------------
getkey:
  mov ah, 00h
  int 16h
  ret
;-------------------------------------------------------
aspotcalc:                      ; ascii spot calculator
  and dh, 00000001b             ; based on the spot in the hex area (dx)
  shl dx, 4
  shr dl, 4
  add dl, 3Fh
  inc dh
  ret
;-------------------------------------------------------
inputvalue:                     ; IN:
  mov dword ptr [maxvalue], eax ;      EAX: maximum allowed value
  call printbottom              ; OUT:
  mov dl, byte ptr [xy]         ;      ECX / [value]: returned value
  mov byte ptr [maxleft], dl
  call clearbottom
  xor ecx, ecx
  getkeyagain7:
  mov dword ptr [value], ecx
  call cursorgetkey

  cmp al, ESCAPE_KEY
  sete byte ptr [status]        ; set an error if you hit escape
  je donevalue

  cmp al, ENTER_KEY             ; otherwise no error
  je donevalue

  cmp al, BACKSPACE_KEY
  je backvalue

  cmp al, '0'
  jne non0jump

  jecxz getkeyagain7

  non0jump:

  cmp al, '0'
  jb getkeyagain7

  cmp al, '9'
  ja getkeyagain7

  movzx edx, al
  sub dl, 48

  lea ebx, [ecx][ecx*4]
  shl ebx, 1
  add ebx, edx

  cmp ebx, dword ptr [maxvalue]
  ja getkeyagain7

  mov ecx, ebx
  mov dl, al
  call printchar
  call setxy

  jmp getkeyagain7
  donevalue:
  ret
;------------
backvalue:
  mov al, byte ptr [maxleft]
  cmp byte ptr [xy], al
  je getkeyagain7

  call backcommon

  xor edx, edx
  mov eax, ecx
  mov ecx, 10
  div ecx
  mov ecx, eax

  jmp getkeyagain7
;------------------------------------------------------
printcounts:
  pushad
  mov word ptr [xy], 21        ; print the current sector
  mov byte ptr [region], UNDEFINED
  mov eax, dword ptr [sector]  ; the string "Sector:"
  call printcount              ; isn't printed for efficiency
  mov dx, offset valuebuffer
  call printstring

  inc byte ptr [xy]            ; prints subsector in this manner: [1]
  mov dl, '['
  call printchar
  mov dl, byte ptr [subsector]
  add dl, '1'
  call printchar
  mov dl, ']'
  call printchar

  mov byte ptr [xy], 36

  mov eax, dword ptr [sector]

  cmp byte ptr [drivetype], PHYSICAL
  je inphysical
  cmp byte ptr [drivetype], CDROM
  je indata

  mov edx, dword ptr [reserved]
  cmp eax, edx
  jb inreserved

  movzx cx, byte ptr [fats]
  jcxz notinfat
  anotherfat:
    add edx, dword ptr [spf]
  loop anotherfat
  cmp eax, edx
  jb infat

  notinfat:
  mov edx, dword ptr [root]
  cmp eax, edx
  jb indata
  movzx ebx, word ptr [rootsectors]
  add edx, ebx
  cmp eax, edx
  jae indata

  mov byte ptr [region], ROOT_AREA
  mov dx, offset inrootmsg

  cmp byte ptr [fattype], FAT32
  je dispclust

  continuecount:
  call printstring
  abortdc:

  mov cl, 61                            ; clear to column 61
  cmp byte ptr [drivetype], PHYSICAL
  je noclearchs
    mov cl, 79                          ; clear to column 79
  noclearchs:
  sub cl, byte ptr [xy]
  mov al, SPACE
  call printchar2

  cmp byte ptr [drivetype], PHYSICAL
  jne doneprintcounts
    call getchs
    movzx eax, ch                        ; the following block of code
    mov ah, cl                           ; prints "CHS: xx/xxx/xxxx" in the
    shr ah, 6                            ; top right corner for ah=02h/int13h

    push dx
    mov word ptr [xy], 003Fh
    mov dx, offset chsmsg
    call printstring
    call printcount
    mov dx, offset valuebuffer+6
    call printstring
    mov dl, '/'
    call printchar
    pop dx

    movzx ax, dh
    call printcount
    mov dx, offset valuebuffer+7
    call printstring
    mov dl, '/'
    call printchar

    mov al, cl
    and al, 00111111b
    call printcount
    mov dx, offset valuebuffer+8
    call printstring

  doneprintcounts:
  popad
  ret

  inreserved:
    mov byte ptr [region], RESERVED_AREA
    mov dx, offset inreservedmsg
    jmp continuecount

  infat:
    mov byte ptr [region], FAT_AREA
    push word ptr [xy]
    call printentry
    pop word ptr [xy]
    mov dx, offset infatmsg 
    call printstring
    mov dl, '1'
    mov eax, dword ptr [fatend]
    cmp dword ptr [sector], eax
    jb firstfat
    mov dl, '2'
    firstfat:
    call printchar
    mov dl, ']'
    call printchar
    mov al, SPACE
    mov cl, 2
    call printchar2

    cmp byte ptr [fattype], UNDEFINED
    je abortdc

    mov byte ptr [xy], 2Dh
    mov dx, offset entrymsg
    call printstring
    mov byte ptr [xy], 3Ch
  jmp abortdc

  setmbrview:
    mov byte ptr [region], MBRVIEW
    mov dx, offset inmbrmsg
    call printstring
  jmp abortdc

  inphysical:
   cmp byte ptr [drive], 80h                   ; lower than 80h?
   jb indata                                   ; not an hd - no mbr.
    test eax, eax
    jz setmbrview

  indata:
    mov dx, offset indatamsg
    dispclust:

    call printstring
    mov dl, SPACE
    call printchar

    cmp byte ptr [drivetype], FAT
    jne abortdc

      or byte ptr [region], DATA_AREA

      mov dx, offset clustermsg         ; display cluster number
      call printstring

      mov eax, dword ptr [sector]
      call sector2cluster

      mov dx, offset valuebuffer+1
      call printhex
    jmp continuecount
;-------------------------------------------------------
printhex:                               ; takes whats in eax
  pusha                                 ; and sticks the equivalent
    mov byte ptr [valuebuffer+9], 0     ; hex into valuebuffer
    mov si, 8

    clusterloop:
    mov dl, al                          ; leave only one nibble in AL
    and dl, 0Fh

    add dl, '0'                         ; add '0' to it
    cmp dl, '9'                         ; if AL was less than 10
    jbe ishexnum                        ; then it's a hex number
      add dl, 7                         ; otherwise it's a letter
    ishexnum:

    mov byte ptr [valuebuffer+si], dl
    ror eax, 4
    dec si
    jnz clusterloop
  popa
  ret
;-------------------------------------------------------
cursorgetkey:
  pusha
  mov ah, 01h
  mov cx, 0808h
  int 10h
  popa
call getkey
  pusha
  mov ah, 01h
  mov cx, 2000h
  int 10h
  popa
  ret
;-------------------------------------------------------
printstring:
  pusha
    mov si, dx
    call cbuffer_offset
    printstrloop:
    lodsb

    cmp al, 0
    je abortprintstr

    inc byte ptr [xy]
    stosb
    inc di
    jmp printstrloop

    abortprintstr:
    call setxy
  popa
  ret
;-------------------------------------------------------
printscreen:                    ; this routine prints out all the
                                ; bytes in the read buffer
  call readbufferinsi

  mov dx, word ptr [bps]
  sub dx, ax
  mov word ptr [rembytes], dx

  cmp word ptr [spot], dx
  jb notsignificant

    dec dx
    mov ax, dx
    mov dl, byte ptr [hl]

  notsignificant:

  xor eax, eax
  xor cx, cx

  displaynextchar:
    lodsb

    mov dx, cx
    call aspotcalc
    mov word ptr [xy], dx
    mov dl, al
    cmp cx, word ptr [rembytes]
    jb nntps
      mov dl, SPACE
    nntps:
    call printchar

    mov dx, cx
    call spotcalc
    mov word ptr [xy], dx

    cmp byte ptr [displaymode], BINARY
    je displaybinval
      cmp cx, word ptr [rembytes]
      jb pscontinue
        mov dl, '-'
        call printchar
        call printchar
        jmp donextdispbyte

      pscontinue:

        call printhex
        mov dx, offset valuebuffer+7
        call printstring
        jmp donextdispbyte

    displaybinval:
      mov dx, word ptr [spot]
      and dl, 10000000b
      add dx, 128
      cmp cx, dx
      jae donextdispbyte
      mov dx, word ptr [spot]
      and dl, 10000000b
      cmp cx, dx
      jb donextdispbyte

      cmp cx, word ptr [rembytes]
      jb pscontinue2
        mov al, '-'
        push cx
          mov cl, 4
          call printchar2
          add byte ptr [xy], 5
          call printchar2
        pop cx
        jmp donextdispbyte

      pscontinue2:

    call displaybinary

    donextdispbyte:

  inc cx
  cmp cx, 512
  jne displaynextchar
      ;---------------------------------------------------------------
printaddresses:
  mov byte ptr [xy+1], 00h
  mov byte ptr [xy], 1
  mov dx, offset offsetmsg
  call printstring
  mov byte ptr [xy], 13
  mov dx, offset sectormsg
  call printstring
  movzx eax, byte ptr [subsector]
  shl ax, 9

  mov bx, 10h                           ; 16 bytes per line (hex)
  mov cx, 32                            ; 32 vertical lines for editing
  cmp byte ptr [displaymode], BINARY
  jne nextaddress

  mov dx, word ptr [spot]
  and dl, 10000000b
  add ax, dx
  mov bx, 4                             ; 4 bytes per line (binary)

  nextaddress:
    call gotonextline
    call printhex
    mov dx, offset valuebuffer+3
    call printstring
    add ax, bx
    loop nextaddress
  ret
;---------------------------------------------------------------
printoffset:
  mov word ptr [xy], 9
  call spotinbx
  movzx eax, bx

  call printhex
  mov dx, offset valuebuffer+6
  call printstring

  call printentry

  mov ax, word ptr [cxy]
  mov word ptr [xy], ax
  jmp colorchar
;-------------------------------------------------------
decolorchar:
  pusha
  mov ax, DEFAULTCOLOR + (DEFAULTCOLOR*100h)    ; ah & al = DEFAULTCOLOR
jmp startcolorchar
;-------------------------------------------------------
colorchar:                      ; in: aL = color for character being edited
  pusha                         ;     aH = color for character cursor is on
  mov ax, EDITCOLOR + (HIGHLIGHTCOLOR*100h)

  startcolorchar:
  call cbuffer_offset

  cmp byte ptr [editmode], DEFAULTEDIT
  je ecolor1
    xchg al, ah
  ecolor1:
  mov byte ptr es:[di+1], al

  push word ptr [xy]
    mov dx, word ptr [spot]
    call aspotcalc
    mov word ptr [xy], dx

    call cbuffer_offset
    mov byte ptr es:[di+1], ah
  pop word ptr [xy]
  popa
  ret
;-------------------------------------------------------
printchar2:
  pusha
  call cbuffer_offset

  printchar2loop:
    stosb
    inc di
  dec cl
  jnz printchar2loop
  popa
  ret
;-------------------------------------------------------
printchar:
  pusha
  call cbuffer_offset

  mov byte ptr es:[di], dl
  inc byte ptr [xy]
  popa
  ret
;-------------------------------------------------------
init:
  cld                                   ; following code sets video mode

  mov di, 0B800h
  push ds
  push 0
  pop ds
  mov cl,ds:[44Ah]
  mov bx,ds:[44Eh]
  mov ch,ds:[484h] ;rows
  mov dl,ds:[462h] ;video page
  inc ch
  pop ds
  cmp ch,43
  jae clrscn
  mov ax, 1200h                         ; EGA or better present?
  mov bl, 10h
  xor cx, cx
  int 10h
  or cx, cx
  jz fth
  mov bl, 30h
  mov ax, 1201h                         ; 350 scan lines in next mode set
  int 10h

  mov ax, 3
  or bh, bh
  jz skipacd
  mov di,0B000h
  mov al, 7
skipacd:
  int 10h                               ; set video mode 3/7
  mov ax, 1112h
  mov bl, 0
  int 10h                               ; select font 8x8 ROM
fth:
  mov cl, 80
  mov ch, 43
  xor bx, bx
  mov dl,0
clrscn:
  mov [vidcols],cl
  mov [vidrows],ch
  mov [vidpg],dl
  mov ch,43
  shr bx,4
  add di,bx
  mov [vidseg],di
  mov es,di
  xor di,di
@@:
  push cx
  push di
  mov cx,80
  mov ax, DEFAULTCOLOR*100h+SPACE
  rep stosw
  pop di
  pop cx
  mov al,[vidcols]
  mov ah,0
  shl ax,1
  add di,ax
  dec ch
  jnz @B

  mov word ptr [xy], 1423h              ; print out copyright info
  mov dx, offset introtext
  call printstring
  mov word ptr [xy], 161Ah              ; print out copyright info
  mov dx, offset copyright
  call printstring

    mov ax, 3524h                       ; back up old int 24h
    int 21h
    mov word ptr [old24h], bx
    mov word ptr [old24h+2], es

    mov ah, 25h                         ; set up new int 24h
    mov dx, offset int24h               ; (al preserved from previous call)
    int 21h

  call wipemem
  call setseeds1

  mov word ptr [drivepacket+4], 1       ; read in 1 sector at a time
  mov word ptr [drivepacket+8], ds      ; set segment

  xor dx, dx                            ; y = (spot-1)/16
  call spotcalc
  mov word ptr [cxy], dx

;--- japheth: init vdd on nt platforms
  call initvdd

  ret
;-------------------------------------------------------
setxy:                          ; set the current x/y coordinate
  pusha                         ; of the cursor this is mainly for
  mov bh, [vidpg]               ; the cursor when receiving input
  mov dx, word ptr [xy]         ; since we use direct text output
  mov ah, 02h
  int 10h
  popa
ret
;-------------------------------------------------------
; IN:   eax             = value to convert to ascii
; OUT:  [valuebuffer]   = ascii equivalent
;
printcount:
  pushad
  mov cx, 10
  mov si, offset valuebuffer+10
  mov ebx, 10

  mov byte ptr [si], 0
  writevaluebuffer:
  dec si
  xor edx, edx
  div ebx
  add dl, '0'
  mov byte ptr [si], dl
  loop writevaluebuffer

  popad
  ret
;-------------------------------------------------------
getchs:
  movzx eax, byte ptr [heads]
  movzx ebx, byte ptr [sectors]
  mul ebx

  mov ebx, eax
  mov eax, dword ptr [sector]
  xor edx, edx
  test ebx, ebx
  jz skipchs1
    div ebx
  skipchs1:
  mov cl, ah
  shl cl, 6
  mov ch, al

  mov eax, edx
  xor edx, edx
  movzx ebx, byte ptr [sectors]
  cmp bl, 0
  je skipchs2
    div ebx
  skipchs2:
  mov dh, al
  inc dl
  and dl, 00111111b
  or cl, dl
  ret
;-------------------------------------------------------
; rwsect handles all sector reading and writing in WDe for all disk types
;       IN:     [sector]      = the sector number to read
;               [handling]    = what to do when sector read/write fails
;               [drive]       = drive number to use
;               [rwfunction]  = type of read/write function
;               [rw]          = 1 for write, all other values read
;       OUT:    [status]      = success or fail
;               sector is read into readbuffer or written from writebuffer
;
; Notes:
;   Old versions of MS-DOS that do not support FAT32 do not set carry
;   flag when returning from int 21h/ax=7305h to indicate that the function
;   is not supported.
;
;   New versions of MS-DOS do not return ax=0207h when attempting a read
;   with int 25h on a FAT32 partition as reported by Ralf Browns interrupt
;   list, however, they do set the carry flag.
;
;   This function can't simply be removed from WDe quite yet, as many
;   assumptions are made about various buffers being filled.
;
rwsect:
  push dword ptr [sector]
  pushad
  mov eax, dword ptr [drivestart]
  add dword ptr [sector], eax
  push cs
  pop es
  mov ax, word ptr [rwfunction]
  mov word ptr [oldfunction], ax
  mov ax, word ptr [bps]
  mov word ptr [oldbps], ax
  mov dl, byte ptr [drive]
  mov byte ptr [olddrive], dl
  mov byte ptr [status], SUCCESS

  mov byte ptr [subsector], 0

  test byte ptr [rwfunction], CRW
  jz cdromread
  cmp byte ptr [rwfunction], OLDINT13
  je useoldint13

  mov eax, dword ptr [sector]

  cmp byte ptr [rwfunction], FILEFUNC
  je fileread
  cmp byte ptr [rwfunction], NEWINT13
  je hdread

  ; the following are used for both int21h and 25h/26h
  mov cx, 0FFFFh
  mov bx, offset drivepacket
  mov dword ptr [bx], eax               ; set sector #
    mov word ptr [bx+6], offset readbuffer
    xor si, si                          ; 0 (read)
  cmp byte ptr [rw], WRITE
  jne reading                           ; default to reading for safety
    mov word ptr [bx+6], offset writebuffer
    inc si                              ; 1 (write)
  reading:

  cmp byte ptr [rwfunction], NEWINT21
  je newread

     ;-------------

    mov al, byte ptr [drive]

  cmp byte ptr [rw], WRITE
  je dooldwrite

    call int25
    ;pop dx                              ; pop original flags left on stack
    jc newreadadjust
    jmp nosectorerror

  dooldwrite:

    call int26
    ;pop dx                              ; pop original flags left on stack
    jc sectorerror
    jmp nosectorerror

     ;--------------

  newreadadjust:
    mov byte ptr [rwfunction], NEWINT21

  newread:
    mov dl, byte ptr [drive]
    inc dl
    mov ax, 7305h                       ; extended sector read/write
    call int21
    jc trycdrom
    jmp nosectorerror

     ;-------------

    fileread:
      mov edx, dword ptr [dataend]
      add edx, dword ptr [drivestart]
      cmp eax, edx
      ja sectorerror

      shl eax, 9                        ; \Fix/

      mov edx, dword ptr [rwfilesize]
      sub edx, 512
      cmp eax, edx
      ja sectorerror

      mov bx, word ptr [rwhandle]
      mov dx, ax
      shr eax, 16
      mov cx, ax
      mov ax, 4200h                     ; seek from start of file
      int 21h

      push cs
      pop ds

      mov ah, 3Fh                       ; read from file
      mov dx, offset readbuffer
      cmp byte ptr [rw], WRITE
      jne dofread
        mov dx, offset writebuffer
        inc ah
      dofread:
      mov bx, word ptr [rwhandle]
      mov cx, 512
      int 21h
      jc sectorerror
      jmp nosectorerror
   ;-------------
    trycdrom:                           ; check a drive for mscdex
      mov ax, 150Bh
      movzx cx, byte ptr [drive]
      int 2Fh
      cmp bx, 0ADADh                    ; 0ADADh returned if mscdex called
      jne sectorerror
      test ax, ax                       ; ax=0 if not read successfully
      jz sectorerror

      mov byte ptr [rwfunction], CDCOOKED
      mov byte ptr [drivetype], CDROM

      mov word ptr [bps], 2048
      mov byte ptr [cdheader], 13       ; size of header
      mov word ptr [cdheader+14], offset readbuffer
      mov word ptr [cdheader+16], cs
      mov word ptr [cdheader+18], 1
      mov byte ptr [cdheader+24], 0     ; cooked mode

      mov dx, offset cdrcmsg            ; choose between raw/cooked
      call printbottom

      getrc:
      call cursorgetkey
      cmp al, ESCAPE_KEY
      je secterrhandle
      cmp ah, SCAN_C
      je cdromread
      cmp ah, SCAN_R
      jne getrc

    mov byte ptr [cdheader+24], 1     ; read cd-rom using raw mode
    mov word ptr [bps], 2352          ; 2352 bytes per sector
    mov byte ptr [rwfunction], CDRAW

    cdromread:
      mov bx, offset cdheader
      mov eax, dword ptr [sector]
      add eax, CD_SECTOR_OFFSET         ; can't read first 10h sectors

      mov byte ptr [bx+2], 128          ; read long
      cmp byte ptr [rw], WRITE
      jne docdread
        mov byte ptr [bx+2], 134        ; write long
      docdread:
      clc                               ; fixes bug in Win9x
      mov dword ptr [bx+20], eax
      push cs
      pop es
      movzx cx, byte ptr [drive]
      mov ax, 1510h                     ; cd-rom send device driver request
      call int2F
      jc sectorerror                    ; device driver has not been called
      test byte ptr [bx+4], 10000000b   ; check status word for error
      jz nosectorerror

   ;-------------

      sectorerror:
      mov dx, offset sectorrerror
      cmp byte ptr [rw], WRITE
      jne werror
        mov dx, offset sectorwerror
      werror:

      cmp byte ptr [handling], IGNORE_ERRORS
      je nosectorerror
      cmp byte ptr [handling], ABORT_OPERATION
      je sectorerror2
      mov bx, word ptr [lastbottomtext]
        call printbottom

        mov dx, offset sectorrerror3
        cmp byte ptr [handling], QUERY_SKIP
        je printabortskip
        mov dx, offset sectorrerror2
        printabortskip:
        call printstring
      gak:
        call cursorgetkey
        cmp al, ESCAPE_KEY
        je secterrhandle
        cmp ah, SCAN_A
        je secterrhandle
        cmp byte ptr [handling], QUERY_SKIP
        je checkskip
          cmp ah, SCAN_Z
          jne gak
      itsZ:
        push cs
        pop es
        mov di, offset readbuffer
        xor al, al
        mov cx, 2352
        rep stosb
      itsS:
        mov dx, bx
        call printbottom
      jmp nosectorerror
        checkskip:
          cmp ah, SCAN_S
          je itsS
          cmp ah, SCAN_I
          jne gak
        mov byte ptr [handling], IGNORE_ERRORS
      jmp itsS
      sectorerror2:

        ifdef DEBUG
          push eax
            mov eax, dword ptr [sector]
            call printcount
            mov dx, offset valuebuffer
          pop eax
        endif

        call nuprinterror
    secterrhandle:
      mov byte ptr [status], ERROR
      mov ax, word ptr [oldfunction]
      mov word ptr [rwfunction], ax
      mov al, byte ptr [olddrive]
      mov byte ptr [drive], al
      mov ax, word ptr [oldbps]
      mov word ptr [bps], ax

    jmp nosectorerror

   ;-------------

  hdread:
    mov si, offset diskrwbuffer
    mov byte ptr [si], 10h
    mov word ptr [si+2], 1
    mov word ptr [si+6], ds
    mov dword ptr [si+8], eax           ; set sector #

;    mov eax, dword ptr [sector2]       ; \/\/\/\ 64-bit lba support
;    mov dword ptr [si+0Ch], eax

    mov dl, byte ptr [drive]

    cmp byte ptr [rw], WRITE
    je int13write

      mov word ptr [si+4], offset readbuffer
      mov ah, 42h

    jmp exint13
    int13write:

      mov word ptr [si+4], offset writebuffer
      mov ax, 4300h + NEWINT13_WRITE_FLAG

    exint13:

    stc                         ; bug circumvention
    call int13
    sti                         ; interrupt flag sometimes disabled
    jnc nosectorerror           ; try older int13h functions (ah=02h)

   ;-------------

  mov byte ptr [rwfunction], OLDINT13

  useoldint13:
    call getchs

    mov dl, byte ptr [drive]
    mov ax, 0201h
    cmp byte ptr [rw], WRITE
    jne old13hread
      inc ah
    old13hread:
    mov bx, offset readbuffer
    call int13

    jc sectorerror

  ;---------------

  nosectorerror:

  mov byte ptr [rw], READ
  popad
  pop dword ptr [sector]
  ret
;-------------------------------------------------------
printerror:
  push dx
    call updatescreen
  pop dx
  nuprinterror:
  call printbottom
  mov dx, offset errormsg
  call printstring
  call getkey

  mov byte ptr [status], ERROR
  ret
;-------------------------------------------------------
validpathchar:
  cmp al, BACK_SLASH
  je validchar
  cmp al, COLON
  je validchar
  cmp al, PERIOD
  je validchar
validfileinputchar:
  cmp al, 'a'                   ; lower case letters allowed in paths
  jb validfilechar
  cmp al, 'z'
  ja validfilechar
  jmp validchar
extvalidfilechar:
  cmp al, PERIOD
  je validchar
  cmp al, SPACE                 ; directory entries can contain spaces
  je validchar
validfilechar:
  cmp al, SPACE                 ; short file name can't have chars
  jbe invalidchar               ; under 20h
  cmp al, DOUBLE_QUOTE          ; can't have double-quotes
  je invalidchar
  cmp al, ASTERISK
  je invalidchar
  cmp al, COMMA
  je invalidchar
  cmp al, PERIOD
  je invalidchar
  cmp al, FORWARD_SLASH
  je invalidchar
  cmp al, '9'                   ; everything else & numbers allowed
  jbe validchar
  cmp al, 40h                   ; boolean test chars and what not
  jb invalidchar                ; are not allowed
  cmp al, 7Bh                   ; brace allowed
  je validchar
  cmp al, 7Dh                   ; brace allowed
  je validchar
  cmp al, 7Eh                   ; tilde allowed
  je validchar
  cmp al, BACK_SLASH
  je invalidchar
  cmp al, 'a'                   ; no lower case letters
  jae invalidchar

    validchar:
    clc
  ret
    invalidchar:
    stc
  ret
;-------------------------------------------------------
getfilename:                    ; IN:  nothing
  mov dx, offset filenamemsg    ; OUT: CX=length of filename
  call printbottom              ;      asciz 'filename' buffer filled
  mov di, offset filename       ;      ax/di/dx/cx corrupted
  xor cx, cx

  getkeyagain6:
  call cursorgetkey

  cmp al, BACKSPACE_KEY
  jne nobackspacefile
  jcxz getkeyagain6             ; no characters left to delete
  dec cx

  call backcommon

  dec di
  nobackspacefile:

  cmp al, ENTER_KEY
  je donegetfilename

  cmp al, ESCAPE_KEY
  je abortgetfilename

  cmp ah, TAB_KEY
  je abortgetfilename

  cmp cx, 68
  je getkeyagain6

  call validpathchar
  jc getkeyagain6

  mov dl, al
  call printchar
  call setxy

  mov byte ptr [di], al
  inc di

  inc cx
  jmp getkeyagain6

  abortgetfilename:
    xor cx, cx
  donegetfilename:
    mov byte ptr [di], 0                ; null-terminate filename
  ret
;-------------------------------------------------------
cbuffer_offset:                 ; take what's in [xy] and set di to offset
  push ax                       ; to the respective byte in the screen buffer
;   push 0b800h
;   pop es
    mov es,[vidseg]
    mov al, byte ptr [xy+1]
	mov bl,[vidcols]
	mov bh,0
;    mov bx, 80
    mul bl
    mov bl, byte ptr [xy]
    add ax, bx
    shl ax, 1
    mov di, ax
  pop ax
  ret
;-------------------------------------------------------
printdate:
  mov ax, word ptr [si+bx]
  mov word ptr [highlight], bx
  mov word ptr [highlight+2], 0202h
  call bshighlight
  and eax, 0FFFFh
  push ax
  shr ax, 5
  and ax, 1111b
    jnz monthok1
      inc ax
    monthok1:
    cmp ax, 12
    jbe monthok2
      mov ax, 12
    monthok2:
    call printcount
    mov dx, offset valuebuffer+8
    call printstring
  mov dl, '-'
  call printchar

  mov byte ptr [highlight+2], 01h
  call bshighlight
  pop ax
  push ax
    and ax, 11111b
    jnz dayok
      inc ax
    dayok:
    call printcount
    mov dx, offset valuebuffer+8
    call printstring
  mov dl, '-'
  call printchar
  inc byte ptr [highlight]
  mov byte ptr [highlight+3], 04h
  call bshighlight
  pop ax
  shr ax, 9
  add ax, 1980                          ; dates start at 1980
  call printcount
  mov dx, offset valuebuffer+6
  call printstring
  inc byte ptr [xy]
  ret
;-------------------------------------------------------
printtime:
  mov ax, word ptr [si+bx]
  mov word ptr [highlight], bx
  mov word ptr [highlight+2], 0201h
  call bshighlight

  and eax, 0FFFFh
  push dx
  push ax
    shr ax, 11
    cmp ax, 23
     jbe hourok
     mov ax, 23
     hourok:
    call printcount
    mov dx, offset valuebuffer+8
    call printstring
  mov dl, ':'
  call printchar
  dec word ptr [highlight]
  inc byte ptr [highlight+2]
  call bshighlight
  pop ax
  push ax
    shr ax, 5
    and ax, 111111b
    cmp ax, 59
     jbe minok
     mov ax, 59
     minok:
    call printcount
    mov dx, offset valuebuffer+8
    call printstring
  mov dl, ':'
  call printchar
  pop ax
  pop dx

  push ax                               ; \Fix/
  mov ax, word ptr [spot]
  and ax, 11111b
  cmp ax, 15h
  pop ax
  je nodec
  dec word ptr [highlight]
  jmp dobshl
  nodec:
  dec byte ptr [highlight+2]
  dobshl:
  call bshighlight

    and ax, 11111b
    cmp ax, 29
     jbe secok
     mov ax, 29
     secok:
    shl ax, 1

  push ax
  push bx
    mov ax, dx
    xor dx, dx
    mov bx, 10
    div bx
    mov dx, ax
  pop bx
  pop ax
    add ax, dx
    cmp ax, 59
    jbe secok2
      mov ax, 59
    secok2:

  call printcount
  mov dx, offset valuebuffer+8
  jmp printstring
;-------------------------------------------------------
spotcalc:                       ; IN:  dx = [spot]
  push ax                       ; OUT: dx = [xy]
  mov ax, dx

  cmp byte ptr [displaymode], BINARY
  je binaryspotcalc
    shr dx, 4                   ; for use with hex view
    inc dl                      ; ---calculates where the current
    mov dh, dl                  ; hex byte should be put on the
                                ; screen for the buffer offset ax
    and al, 00001111b

    mov dl, al                  ; dl = al*3 + al/4 + 10
    add dl, al
    add dl, al
    shr al, 2
    add dl, al
    add dl, 10
    jmp donespotcalc
  binaryspotcalc:
    shr dl, 2
    and dl, 00011111b
    mov dh, dl
    inc dh
    and al, 00000011b

    mov ah, 13
    mul ah
    mov dl, al
    add dl, 11
  donespotcalc:
  pop ax
  ret
;-------------------------------------------------------
getyn:                          ; prints [Y/N] on the screen
  mov dx, offset ynmsg          ; carry flag set if 'Y'
  call printstring
  getyn2:
  call cursorgetkey
  cmp al,'A'
  jb @F
  or al,20h
@@:
  cmp al, 'y'
  je returny
  cmp al, ENTER_KEY
  je returny
  cmp al, 'n'
  je returnn
  cmp al, ESCAPE_KEY
  jne getyn2
  returnn:
    clc
  ret
  returny:
    stc
    doret:
  ret
;-------------------------------------------------------
quit:
  mov dx, offset quitmsg
  call printbottom
  call getyn
  jnc doret
  doquit:

;--- japheth: exit vdd on nt platforms
  call exitvdd
if 0
  mov ax, 500h	;select active page
  int 10h
  mov ax, 1200h ;get EGA info
  mov bl, 10h
  xor cx, cx
  int 10h
  or cx, cx
  jz doneset
  mov bl, 30h
  mov ax, 1202h
  int 10h
  mov ax, 7
  or bh, bh
  jnz label2
  mov al, 3
label2:
  int 10h
else
  mov ah, 01h         ;set cursor shape
  mov cx, 0808h
  int 10h
  mov cl,[vidcols]    ;clear bottom line on screen (just 80 rows)
  mov bl,[vidrows]
  dec bl
  mov al,bl
  mul cl
  shl ax,1
  mov di,ax
  mov es,[vidseg]
  mov ax,07*100h+SPACE;07=white on black
  mov cx,80
  rep stosw
  mov ah,2            ;set cursor pos to bottom line
  mov bh,[vidpg]
  mov dh,bl
  mov dl,0
  int 10h
endif
  doneset:

  mov ax, 2524h
  mov dx, word ptr [old24h]
  mov ds, word ptr [old24h+2]
  int 21h

  mov ax, 4c00h
  int 21h
;-------------------------------------------------------
savedata:
;
; IN:   dd:[value]      number of sectors to save
;       eax             starting sector
;
; OUT:  disk is read and sectors are dumped to [filehandle]
;       dw:[filehandle] handle of file to write to
;

  mov edx, eax
  add edx, dword ptr [value]
  jc invalidperror
  dec edx
  cmp edx, dword ptr [dataend]
  ja invalidperror

  mov edx, dword ptr [value]    ; the plan here is to convert
  mov cx, word ptr [bps]        ; "value" into the number of 512-byte
  shr cx, 10                    ; pieces it contains by shifting it left
  shl edx, cl                   ; if BPS is > 512

  cmp edx, 400000h
  ja toobig

  push ax
  call createfile
  pop ax
  cmp byte ptr [status], ERROR
  jne dosavedata
    donesavedata:
    ret
  dosavedata:
  call writefile
  call closefile

  call updatescreen

  cmp byte ptr [status], ERROR
  je donesavedata

  mov dx, offset donemsg
  jmp printerror
;-------------------------------------------------------
  toobig:
;    mov bx, offset filetoobig
;    mov al, byte ptr [fileflag]
;    mov byte ptr [bx+24], al
;    mov dx, bx
    mov dx, offset filetoobig
  jmp printerror
;-------------------------------------------------------
invalidperror:
  mov dx, offset invalidpmsg
  jmp printerror
;-------------------------------------------------------
printfilemenu:
  mov byte ptr [chainflag], NO_CHAIN

  cmp byte ptr [drivetype], PHYSICAL
  jne logicalrfo
    mov dx, offset pdfilemenu
    jmp printmenu
  logicalrfo:

  mov dx, offset ldfilemenu
  mov eax, dword ptr [reserved]
  cmp dword ptr [sector], eax
  jb printmenu

  mov eax, dword ptr [spf]
  movzx ebx, byte ptr [fats]
  mul ebx
  mov dx, offset ldfilemenu
  add eax, dword ptr [reserved]
  cmp dword ptr [sector], eax
  jb dochain

  checkdir:
  mov si, offset readbuffer
  xor bx, bx
  call finddirectory
  jc printmenu                  ; dir not found

  mov byte ptr [chainflag], FILE_CHAIN
  jmp dochain2

  dochain:
  mov byte ptr [chainflag], FAT_CHAIN

  dochain2:
    mov dx, offset chainmenu
      ;-------------------------------------------------------
printmenu:
  mov word ptr [xy], 2a01h
  mov si, dx
  mov ah, byte ptr [si]         ; number of items in the menu
  inc si
  movzx cx, byte ptr [si]       ; number of spaces between each item

  nextmenuitem:
    inc si
    mov bl, byte ptr [si]
    mov di, offset menuitems

  foundnextitem:
    cmp bl, 0
    je printitem

  findnextitem:
    inc di
    cmp byte ptr [di], 0
    jne findnextitem
  inc di
  dec bl
  jmp foundnextitem

  printitem:
    mov dl, 'F'
    call printchar
    mov dl, '1'
    add dl, ch
    call printchar
    mov dl, '-'
    call printchar
    mov dx, di
    call printstring
    mov al, SPACE
    call printchar2
    add byte ptr [xy], cl
  inc ch
  cmp ch, ah
  jne nextmenuitem
  jmp clearbottom
;-------------------------------------------------------
getstring:                              ; in: nothing
  mov dx, offset stringmsg              ; out: stringbuffer filled
  call printbottom                      ;      cx = # of bytes entered
  mov di, offset stringbuffer
  xor cx, cx

  getkeyagain9:
  call cursorgetkey

  cmp al, BACKSPACE_KEY
  jne nobackspacestring
  jcxz getkeyagain9
  dec cx

  call backcommon

  dec di
  jmp getkeyagain9
  nobackspacestring:

  cmp al, ESCAPE_KEY
  je abortgetstring

  cmp al, ENTER_KEY
  je donegetstring

  cmp cx, 70
  je getkeyagain9

  cmp al, 0
  je getkeyagain9

  mov dl, al
  call printchar
  call setxy

  push cs
  pop es
  stosb

  inc cx
  jmp getkeyagain9
  abortgetstring:
  xor cx, cx
  donegetstring:
  ret
;-------------------------------------------------------
backcommon:
  dec byte ptr [xy]
  mov dl, SPACE
  call printchar
  dec byte ptr [xy]
  jmp setxy
;-------------------------------------------------------
movecursor:             ; IN:   ax = new [spot]
                        ;       dl = new [hl]
  push word ptr [cxy]
  pop word ptr [xy]
  call decolorchar
  mov word ptr [spot], ax
  mov byte ptr [hl], dl
  mov dx, ax
  call spotcalc
  add dl, byte ptr [hl]
  mov word ptr [cxy], dx
  jmp printoffset
;-------------------------------------------------------
checkabort:             ; sets equal flag if escape key was pressed
  push ax
  push dx
    mov ah, 06h                   ; direct input is used since it takes
    mov dl, 0ffh                  ; keys off the keybuffer
    int 21h
    cmp al, ESCAPE_KEY
  pop dx
  pop ax
  ret
;-------------------------------------------------------
; sets viewmode to DL
checksetview:
  cmp byte ptr [viewmode], dl                   ; check if the "view" mode
  je abortviewmode0                             ; is already set.

  mov byte ptr [viewmode], dl                   ; set new view
; push 0b800h                                   ; clear the view area to
; pop es                                        ; prepare for new view
  mov es,[vidseg]
  mov cl,[vidcols]
  mov ch,0
  mov ax,34
  shl cx,1
  mul cx
  mov di,ax
  mov dl,8
@@:
  push di
  push cx
  mov ax, DEFAULTCOLOR*100h + SPACE
  mov cx,80
  rep stosw
  pop cx
  pop di
  add di,cx
  dec dl
  jnz @B

  abortviewmode0:
  ret
;-------------------------------------------------------
getnos:                                 ; 'get number of sectors' from the
  pushad                                ; user; check for equality, if so
    mov eax, dword ptr [dataend]        ; then abort.
    sub eax, dword ptr [sector]
    inc eax
    mov dx, offset sectorsmsg
    call inputvalue
    test ecx, ecx
    jnz goodval
      mov byte ptr [status], ERROR
    goodval:
    cmp byte ptr [status], ERROR
  popad
  ret
;-----------------------------------------------------
displaybinary:                          ; AL = bits to display
  mov dh, 8
  printbitsloop:
    cmp dh, 4                           ; 4th bit?  put a space.
    jne dontaddspace
      inc byte ptr [xy]
    dontaddspace:
    rol al, 1
    mov dl, '0'
    jnc bitnotone
      inc dl
    bitnotone:
    call printchar
    dec dh
  jnz printbitsloop
  ret
;-------------------------------------------------------
getfilesize:                            ; out: eax & [filesize] = filesize
  mov ah, 2fh                           ; gets the current dta
  int 21h
  mov eax, dword ptr es:[bx+1Ah]
  mov dword ptr [filesize], eax
  ret
;-------------------------------------------------------
printbottom:
  mov word ptr [xy], 2a01h
  mov word ptr [lastbottomtext], dx
  call printstring
  call setxy
      ;-------------------------------------------------------
clearbottom:
  pusha
    mov cl, 80
    sub cl, byte ptr [xy]
    mov al, SPACE
    call printchar2
  popa
  ret
;-------------------------------------------------------
findfile:                       ; IN: filename = pointer to filename
  pusha                         ; OUT: carry flag set if no file found
    mov byte ptr [status], SUCCESS
    mov ax, 4e00h               ; findfirst
    mov cx, 47h
    mov dx, offset filename
    int 21h
  popa
  ret
;-------------------------------------------------------
copybuffer:
  pusha
    mov si, offset readbuffer
    mov di, offset writebuffer
    push cs
    pop es

    mov cx, 2352
    rep movsb
  popa
  ret
;-------------------------------------------------------
closefile:
  mov ah, 3eh
  mov bx, word ptr [filehandle]
  int 21h
  ret
;-------------------------------------------------------
writefile:                      ; in: dword [value] = number of sectors
  push dword ptr [sector]       ;                     to save
  mov dword ptr [sector], eax   ;     eax           = start sector
   mov dx, offset writingmsg 
   call printbottom          
   writefileloop:

  call checkabort
  jne keepwritingfile

     mov dx, offset abortfmsg
     jmp printwferror

  keepwritingfile:

   call printcounts
   mov byte ptr [handling], QUERY_FILL
   call rwsect
   mov byte ptr [handling], ABORT_OPERATION
   cmp byte ptr [status], ERROR
   je errorwritefile

   mov cx, word ptr [bps]               ; bytes to write
   mov byte ptr [status], SUCCESS
   mov bx, word ptr [filehandle]
   mov dx, offset readbuffer
   mov ah, 40h                          ; write to file
   int 21h
   jnc donewritefile

     mov dx, offset filewerror
     jmp printwferror
   diskfullerr:
     mov dx, offset diskfullmsg
     printwferror:
     call printerror
     jmp errorwritefile

   donewritefile:
   cmp ax, cx
   jb diskfullerr

   inc dword ptr [sector]
   dec dword ptr [value]
   jnz writefileloop
   errorwritefile:
   pop dword ptr [sector]

   push word ptr [status]
   call rwsect
   pop word ptr [status]
   ret
;-------------------------------------------------------
openfile:
  mov dx, 1
  screatefile:
  mov ax, 6c00h
  mov bx, 3002h
  mov si, offset filename
  xor cx, cx
  int 21h

  mov word ptr [filehandle], ax
  ret
;-------------------------------------------------------
createfile:
  mov byte ptr [status], SUCCESS
  call findfile
  jnc fileexists

  ccreatefile:
    mov dx, 10010b
    call screatefile

  mov dx, offset fileerror
  jc printerror
  mov word ptr [filehandle], ax
  ret

  fileexists:
  mov dx, offset owmsg
  call printbottom

  getaoc:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je doabortf
    cmp ah, SCAN_C
    je doabortf
    cmp ah, SCAN_O
    je ccreatefile
    cmp ah, SCAN_A
    jne getaoc
  call openfile                 ; append
    mov bx, ax                  ; seek from end of file
    xor dx, dx
    xor cx, cx
    mov ax, 4202h
    int 21h
    ret
  doabortf:
  mov dx, offset abortfmsg
  jmp printerror
;-------------------------------------------------------
; IN:  nothing
; OUT: variables are wiped
wipemem:
  mov al, 0
  mov di, offset mode          ; wipe mem
  push cs
  pop es
  mov cx, offset dirarray-offset mode
  rep stosb
  ret
;-----------------------------------------------------------------
;       IN:  nothing
;       OUT: seeds filled
;
setseeds1:
  mov bx, offset seed1
  jmp seed
setseeds2:
  mov bx, offset seed2
  seed:
  mov ah, 00h
  int 1Ah

  mov word ptr [bx], dx
  mov word ptr [bx+4], cx
  ret
;-----------------------------------------------------------------
backhex:
  mov dl, byte ptr [xy]                 ; can't backspace any further then the
  cmp byte ptr [maxleft], dl            ; x-coord after string printed
  je getkeyagain10

  call backcommon

  cmp byte ptr [commandflag], GET_STRING
  je backstring
    shr ebx, 4
    jmp getkeyagain10

  backstring:
    cmp bl, 0
    je loworder2
    mov bl, 0
    jmp getkeyagain10

  loworder2:
    dec si
    and byte ptr [stringbuffer+si], 0F0h
    mov bl, 1
    jmp getkeyagain10
;-----------------------------------------------------------------
;
; Returns the hex value obtained from the user.
;
; IN:           commandflag: GET_STRING
;                            GET_VALUE
;               EAX:         maxvalue (for GET_VALUE only)
;               DX:          offset to string to display for query
;
; OUT:          carry flag clear if successful (no escape pressed)
;               CX = count of characters entered for GET_STRING
;               EBX = value gotten (for GET_VALUE)
;               stringbuffer = hex string gotten (for GET_STRING)
;
gethexstring:
  mov byte ptr [commandflag], GET_STRING
  jmp dogethex
gethex:
  mov byte ptr [commandflag], GET_VALUE
  dogethex:
  mov dword ptr [maxvalue], eax         ; back up max value
  call printbottom
  mov dl, byte ptr [xy]                 ; x-coordinate preserved so that
  mov byte ptr [maxleft], dl            ; backspace does not go too far
  xor ebx, ebx
  xor si, si
  getkeyagain10:
    call cursorgetkey
    cmp al, ENTER_KEY
    je donegethex
    cmp al, ESCAPE_KEY
    jne noabortgetkey10
      stc
      ret
    noabortgetkey10:

    cmp al, BACKSPACE_KEY
    je backhex

  cmp byte ptr [xy], 79
  je getkeyagain10

  mov dl, al

  cmp al, '0'
  jb getkeyagain10

  cmp al, '9'
  jbe numhex

  cmp al, 'A'
  jb getkeyagain10
  cmp al, 'F'
  jbe lethex

  sub dl, 32

  cmp al, 'a'
  jb getkeyagain10
  cmp al, 'f'
  ja getkeyagain10
       ;-------------------------------------------------
lethex:
  add al, 9

numhex:
  and al, 0Fh
  cmp byte ptr [commandflag], GET_STRING
  je stringhex

  cmp al, 0
  jne notestnec
  mov dh, byte ptr [xy]                 ; get x-coord on screen
  cmp byte ptr [maxleft], dh            ; characters already been typed?
  je getkeyagain10                      ; yes, skip this
  notestnec:                            ; abort if we type a 0 (first)

  test ebx, 0F0000000h                  ; cannot exceed FFFFFFFFh
  jnz getkeyagain10

  shl ebx, 4
  or bl, al

  cmp ebx, dword ptr [maxvalue]         ; value smaller or equal to maximum?
  jbe hexok                             ; accept it.
  shr ebx, 4
  jmp getkeyagain10                     ; abort.

stringhex:
  cmp bl, 1
  je lownibble
    shl al, 4
    mov byte ptr [stringbuffer+si], al
    mov bl, 1
  jmp hexok

  lownibble:
    or byte ptr [stringbuffer+si], al
    xor bl, bl
    inc si

  hexok:
    call printchar
    call setxy
  jmp getkeyagain10
;-----------------------------------------------------------------
donegethex:
  cmp byte ptr [commandflag], GET_STRING
  jne retgethex
  cmp bl, 0
  je noadjust
;   mov bx, offset stringbuffer         ; AAB -> AAB0
;   add bx, si                          ; instead of
;   mov cx, si                          ; AAB -> 0AAB
;   shr word ptr [bx], 4
  inc si
  noadjust:
    mov cx, si
    mov word ptr [stringbuffer+74], bx
  retgethex:
    clc                                 ; success
  ret
;-----------------------------------------------------------------
spotinbx:                               ; this function figures out what
  mov bl, byte ptr [subsector]          ; byte [spot] should actually be
  shl bx, 9                             ; pointing to within the buffer.
  add bx, word ptr [spot]
  ret
;------------------------------------------------------
getcurrententry:                ; IN:  nothing
  call getentrynumber           ; OUT: eax = data stored at current entry
  mov ebx, eax                  ;      ebx = current entry #
  jmp getfatentry               ;      other reg's corrupted
;-------------------------------------------------------
; rand is a random number generator (eax)
; Concatenation of 16-bit multiply with carry generators:
;   x(n)=a*x(n-1)+carry mod 2^16 and
;   y(n)=b*y(n-1)+carry mod 2^16
; Where a and b are any of the following two:
;
;   18000 18030 18273 18513 18879 19074 19098 19164 19215 19584
;   19599 19950 20088 20508 20544 20664 20814 20970 21153 21243
;   21423 21723 21954 22125 22188 22293 22860 22938 22965 22974
;   23109 23124 23163 23208 23508 23520 23553 23658 23865 24114
;   24219 24660 24699 24864 24948 25023 25308 25443 26004 26088
;   26154 26550 26679 26838 27183 27258 27753 27795 27810 27834
;   27960 28320 28380 28689 28710 28794 28854 28959 28980 29013
;   29379 29889 30135 30345 30459 30714 30903 30963 31059 31083
;
; Code based on math and examples from Glenn Rhoads, Ph.D.
;

rand:
  mov eax, 21723
  movzx ebx, word ptr [seed1]
  mul ebx
  mov bx, word ptr [seed2]
  add eax, ebx
  mov dword ptr [seed1], eax

  mov ecx, eax

  mov eax, 30714
  mov bx, word ptr [seed3]
  mul ebx
  mov bx, word ptr [seed4]
  add eax, ebx
  mov dword ptr [seed3], eax

  shl ecx, 16
  and eax, 0FFFFh
  add eax, ecx
  ret
;-----------------------------------------------------------------

;--- japheth: code to access WDEVDD on NT platforms.

    include wdent.inc





;-------------------------------------------------------
;-------------------------------------------------------
ifdef DEBUG

debugviewmode:
  push edx

  mov word ptr [xy], 2201h
  mov dx, offset eaxmsg
  call printstring
  call printregister

  mov word ptr [xy], 2301h
  mov dx, offset ebxmsg
  call printstring
  mov eax, ebx
  call printregister

  mov word ptr [xy], 2401h
  mov dx, offset ecxmsg
  call printstring
  mov eax, ecx
  call printregister

  mov word ptr [xy], 2501h
  mov dx, offset edxmsg
  call printstring
  pop eax
  call printregister

  mov word ptr [xy], 2601h
  mov dx, offset simsg
  call printstring
  movzx eax, si
  call printregister

  mov word ptr [xy], 2701h
  mov dx, offset dimsg
  call printstring
  movzx eax, di
  call printregister

  mov word ptr [xy], 2801h
  mov dx, offset spmsg
  call printstring
  movzx eax, sp
  call printregister

  mov word ptr [xy], 2222h
  mov dx, offset storedeaxmsg
  call printstring
  mov eax, dword ptr [storedeax]
  call printregister

  mov word ptr [xy], 2322h
  mov dx, offset storedebxmsg
  call printstring
  mov eax, dword ptr [storedebx]
  call printregister

  mov word ptr [xy], 2422h
  mov dx, offset storedecxmsg
  call printstring
  mov eax, dword ptr [storedecx]
  call printregister

  mov word ptr [xy], 2522h
  mov dx, offset storededxmsg
  call printstring
  mov eax, dword ptr [storededx]
  call printregister

  mov word ptr [xy], 2622h
  mov dx, offset storedsimsg
  call printstring
  movzx eax, word ptr [storedsi]
  call printregister

  mov word ptr [xy], 2722h
  mov dx, offset storeddimsg
  call printstring
  movzx eax, word ptr [storeddi]
  call printregister

  ret


printregister:
  call printcount
  mov dx, offset valuebuffer
  call printstring
  mov dl, SPACE
  call printchar
  mov dl, '('
  call printchar
  call printhex
  mov dx, offset valuebuffer+1
  call printstring
  mov dl, ')'
  call printchar
  ret


storedebugdata:
  mov dword ptr [storedeax], eax
  mov dword ptr [storedebx], ebx
  mov dword ptr [storedecx], ecx
  mov dword ptr [storededx], edx
  mov word ptr [storedsi], si
  mov word ptr [storeddi], di
  ret

endif
;-------------------------------------------------------
;-------------------------------------------------------



;-------------------------------------------------------
int24h:         ; this is the new int 24h to catch any critical errors
  mov al, 3     ; abort operation code
  iret          ; int 24h would otherwise crash WDe with Abort/Retry/Fail
;-----------------------------------------------------------------

initialmenu     db 7                    ; 7 items in this menu
                db 3                    ; 3 spaces between each
                db 0,1,2,3,4,5,6        ; items to display

jumpmenu        db 7
                db 2
                db 7,8,9,10,11,12,13

cdjumpmenu      db 1
                db 0
                db 7

viewmenu        db 7
                db 2
                db 25,17,9,39,40,41,26

searchmenu      db 6
                db 3
                db 27,28,17,9,31,26

fillmenu        db 6
                db 3
                db 28,27,32,33,42,34

idmenu          db 4
                db 3
                db 35,36,37,38

filemenu        db 2
                db 3
                db 14,15

cdfilemenu      db 2
                db 3
                db 14,24


pdfilemenu      db 6
                db 2
                db 16,17,18,19,20,21

ldfilemenu      db 6
                db 3
                db 16,9,10,11,12,22

chainmenu       db 7
                db 2
                db 16,9,10,11,12,22,23

funcmenu        db 4
                db 3
                db 30,29
        ifndef BASIC
                db 44,43
        endif

introtext       db 'WDe V0.33',0
copyright       db 'Copyright(C)2005 Ben Cadieux',0

owmsg           db 'File Exists - Append/Overwrite/Cancel [A/O/C]? ',0
fhdmsg          db 'Floppy/Hard Disk [F/H]? ',0
cdrcmsg         db 'Raw/Cooked Mode [R/C]? ',0
plmsg           db 'Physical/Fat [P/F]? ',0
abmsg           db 'Above/Below [A/B]? ',0
;fomsg           db 'New File/Abort [F/A]? ',0
truncatemsg     db 'Truncate To Filesize',0
diskfullmsg     db 'Disk Full',0
quitmsg         db 'Quit',0
ynmsg           db ' [Y/N]? ',0

unknownmsg      db 'Unknown',0
active          db 'Active',0

part00          db 'Unused',0
part050F        db 'Ext Fat',0
part07          db 'NTFS',0
part83          db 'Linux',0
partA5          db 'FreeBSD',0
;partA8          db 'OS-X',0
;partA6          db 'OpenBSD',0
;partA9          db 'NetBSD',0
;partEB          db 'BeOS',0

parthid         db 'Hid Fat',0 ;16,1B,1C,1E,8D,90,91,92,97,98,9A,9B

menuitems       db 'Save',0                             ; 0
                db 'File Ops',0                         ; 1
                db 'Goto',0                             ; 2
                db 'View',0                             ; 3
                db 'Find',0                             ; 4
                db 'Functions',0                        ; 5
                db 'Disk',0                             ; 6
                db 'Sector',0                           ; 7
                db 'Cluster',0                          ; 8
                db 'Boot Sector',0                      ; 9
                db 'Fat1',0                             ; 10
                db 'Fat2',0                             ; 11
                db 'Root',0                             ; 12
                db 'Data Area',0                        ; 13
                db 'Save Sectors',0                     ; 14
                db 'Restore Sectors',0                  ; 15
                db 'Input',0                            ; 16
                db 'MBR',0                              ; 17
                db 'Partition1',0                       ; 18
                db 'Partition2',0                       ; 19
                db 'Partition3',0                       ; 20
                db 'Partition4',0                       ; 21
partition       db 'Partition',0                        ; 22
                db 'Chain',0                            ; 23
                db 'Dump CD As ISO',0                   ; 24
                db 'Default',0                          ; 25
                db 'Directory',0                        ; 26
                db 'String',0                           ; 27
                db 'Hex',0                              ; 28
                db 'Fill',0                             ; 29
                db 'Restrict',0                         ; 30
                db 'Fat',0                              ; 31
                db 'Incremental',0                      ; 32
                db 'Decremental',0                      ; 33
                db 'Random',0                           ; 34
                db '8Bit',0                             ; 35
                db '12Bit',0                            ; 36
                db '16Bit',0                            ; 37
                db '32Bit',0                            ; 38
part01          db 'Fat12',0                            ; 39
part04060E      db 'Fat16',0                            ; 40
part0B0C        db 'Fat32',0                            ; 41
                db 'Inverse',0                          ; 42
        ifndef BASIC
                db 'UnDelete',0                         ; 43
                db 'UnFormat',0                         ; 44
        endif

mbps            db 'Bytes Per Sector',0
mspc            db 'Sectors Per Cluster',0
mreserved       db 'Reserved Sectors',0
mfats           db 'Number Of Fats',0
mrootentries    db 'Maximum Root Entries',0      ; FAT1x only
msip            db 'Sectors In Partition',0      ; bootsector & mbr
mspf            db 'Sectors Per Fat',0
mhs             db 'Partition Start',0
mrootc          db 'Root Start Cluster',0        ; FAT32 only
mfsis           db 'FSInfo Sector Number',0      ; FAT32 only
mbackup         db 'Backup B.S. Location',0
mldn            db 'Hard Disk Number',0
mdb             db 'Media Descriptor',0

fcs             db 'Total Free Clusters: ',0
sfc             db 'First Free Cluster:  ',0

mfixed          db ' (HD)',0
mremovable      db ' (FD)',0

startchs        db 'S-CHS',0
endchs          db 'E-CHS',0
startlba        db 'S-LBA',0
mboot           db 'Boot  ',0
mtype           db 'Type  ',0
psize           db 'Sects ',0

searchingmsg    db 'Searching...',0
writingmsg      db 'Writing File...',0
readingdrive    db 'Reading Drive...',0
readingmsg      db 'Writing To Disk...',0
recursemsg      db 'Recursing Chain...',0

ifndef BASIC
        undeletingmsg   db 'UnDeleting...',0
        scanningfatmsg  db 'Scanning Fat...',0
        rfilesmsg       db 'Recovering Files...',0
        fdirsmsg        db 'Finding Directories...',0
        rdirsmsg        db 'Recovering Directories...',0
        fat1to2msg      db 'Copying Fat-1 to Fat-2...',0

        doneufmsg       db 'Finished UnFormatting',0
        doneudmsg       db 'Finished UnDeleting File',0

        fileexceeded    db 'File Chain Exceeds FAT',0

        dnfmsg          db 'Fat Table Not Blank',0
        rnbmsg          db 'Root Not Blank',0
        nodirsmsg       db 'No Directories Found',0

        firstcharmsg    db 'New First Character: ',0
endif

stringerror     db 'No Matches Found',0
abortfmsg       db 'Aborted Writing File',0
abortdmsg       db 'Aborted Writing to Disk',0

donemsg         db 'Finished Writing File',0
donermsg        db 'Finished Writing to Disk',0

toosmall        db 'File Too Small',0
filenotfound    db 'File Not Found',0
nofirstcluster  db 'File Too Corrupt',0
filetoobig      db 'File Size Cannot Exceed 2GB',0

errorread       db 'Error Reading File',0
filewerror      db 'Error Writing File',0
fileerror       db 'Error Creating File',0

invalidpmsg     db 'Invalid Sector Range',0

sectorrerror    db 'Error Reading Sector',0
sectorrerror2   db ' - Abort/Zero-Fill [A/Z]? ',0
sectorrerror3   db ' - Abort/Skip/Ignore All [A/S/I]? ',0
sectorwerror    db 'Error Writing Sector',0
greatmsg        db 'Invalid Start Cluster',0
nochainmsg      db 'Recursive Link Not Found',0
errormsg        db ' - Press Any Key',0

inmbrmsg        db '[MBR]',0
infatmsg        db '[Fat-',0
inrootmsg       db '[Root]',0
indatamsg       db '[Data]',0
inreservedmsg   db '[Boot/Reserved]',0

hexmsg          db 'Hex: ',0
chsmsg          db 'CHS: ',0
partmsg         db 'Part: ',0
sizemsg         db 'Size: ',0
entrymsg        db 'Entry:',0
drivemsg        db 'Drive: ',0
offsetmsg       db 'Offset: ',0
stringmsg       db 'String: ',0
sectormsg       db 'Sector: ',0
clustermsg      db 'Cluster: ',0
createdmsg      db 'Created: ',0
accessedmsg     db 'Accessed: ',0
modifiedmsg     db 'Modified: ',0
filenamemsg     db 'Filename: ',0
attributesmsg   db 'Attributes: ',0
sectorsmsg      db 'Number Of Sectors: ',0

ifdef DEBUG
  eaxmsg        db 'EAX: ',00h
  ebxmsg        db 'EBX: ',00h
  ecxmsg        db 'ECX: ',00h
  edxmsg        db 'EDX: ',00h
  simsg         db 'SI:  ',00h
  dimsg         db 'DI:  ',00h
  spmsg         db 'SP:  ',00h
  storedeaxmsg  db 'Stored EAX: ',00h
  storedebxmsg  db 'Stored EBX: ',00h
  storedecxmsg  db 'Stored ECX: ',00h
  storededxmsg  db 'Stored EDX: ',00h
  storedsimsg   db 'Stored SI:  ',00h
  storeddimsg   db 'Stored DI:  ',00h
  storedeax     dd ?
  storedebx     dd ?
  storedecx     dd ?
  storededx     dd ?
  storedsi      dd ?
  storeddi      dd ?
endif


old24h          dd ?

; drivepacket is for use with int 25h/26h and int 21h/ax=7305h
drivepacket     dd ? ; sector number to start reading at read/write
                dw ? ; +4 = number of sectors to read/write
                dw ? ; +6 = offset of sector memory
                dw ? ; +8 = segment of sector memory

vidseg          dw ? ; video buffer segment
vidcols         db ?
vidrows         db ?
vidpg           db ?,?
cxy             dw ? ; cursor xy position

mode            db ? ; what mode WDe is in; preparation for future features
rw              db ? ; distinguish between read/write
drive           db ? ; drive number
subsector       db ? ; because [spot] goes from 0-511, if we have sectors
                     ; that are >512 bytes, subsector keeps track of what
                     ; 512-byte piece we're working with
hl              db ? ; keeps track of whether we're editing high or low nibble
spot            dw ? ; keeps count of what byte we're editing 0-511
fattype         db ? ; type of fat
spf             dd ? ; sectors per fat
fatend          dd ? ; end of fat
spc             db ? ; sectors per cluster
reserved        dd ? ; reserved sectors (start of fat)
fats            db ? ; number of fats
rootentries     dw ? ; number of root entries
hdnumber        db ? ; hard drive number partition belongs to
sector          dd ? ; sector for read/writes
sector2         dd ? ; high sector dword for int13h
backupbs        dd ? ; backup boot sector location
rootsectors     dw ? ; number of root sectors
dataend         dd ? ; end of data
; dataend2        dd ? ; high dword for int13h HUGE hds
datastart       dd ? ; start of data
spcmd           db ? ; sectors per cluster for doing bitshifts
lastcluster     dd ? ; total # of clusters on the drive
root            dd ? ; root directory
rootc           dd ? ; root cluster
fsinfo          dw ? ; fsinfo sector
rwfunction      db ? ; what read/write function to use
drivetype       db ? ; logical/physical/etc
xy              dw ? ; xy position on screen
fromfat         db ? ; fat to use for getfatentry/putfatentry
region          db ? ; what part of the disk we're in
value           dd ?
maxvalue        dd ?
status          db ? ; error in called function?
maxleft         db ?
filesize        dd ?
lastbottomtext  dw ? ; printbottom backs up string pointer for rwsect
                     ; to reprint it when there's a sector error

; "viewmode" defines what the section at the bottom of the screen just above
; the menu is used to display (for additional information)
;          0: unset
;          1: bootsector
;          2: fat12
;          3: fat16
;          4: fat32
;          5: root
;          6: data (scan for directory)
;          7: mbr
;          9: fsinfo

; viewmode+1:            0 = dynamically choose view mode
;                        1 = force current view
viewmode        dw ?
displaymode     db ? ; hex or binary

highlight       dd ? ; area to highlight with viewmode

oldfunction     dw ? ; when changing drives to edit, we need to keep
olddrive        db ? ; track of these variables in case the drive can't
oldbps          dw ? ; be accessed (has to default to previous drive)

editmode        db ? ; what mode being edited in (ascii/default)
cluster         dd ?
; ldcluster       dd ? ; don't remember
bpc             dd ? ; bytes per cluster
bps             dw ? ; bytes per sector
spcc            db ? ; sectors per cluster counter
sbackup         dd ? ; sector backup
handling        db ? ; how to handle errors:
                     ;  3: ignore errors
                     ;  2: query user with "skip"
                     ;  1: query user with "fill with zero"
                     ;  0: abort by default

seed1 dw ?
seed2 dw ?
seed3 dw ?
seed4 dw ?

p1 dd ?
p2 dd ?
p3 dd ?
p4 dd ?

filename        db 69 dup(?)
stringbuffer    db 76 dup(?)
diskinfobuffer  db 1Ah dup(?)       ; buffer for int13h "get drive info"
diskrwbuffer    db 10h dup(?)       ; buffer for int13h extended read/write
fat12fix        db 5 dup(?)         ; stores first borrowed byte for fat12
	align 4
readbuffer      db 2352 dup(?)      ; read buffer for sector reading
fat12fix2       db ?                ; stores last borrowed byte for fat12/CD
	align 4
writebuffer     db 2352 dup(?)      ; write buffer for sector writing
cdheader        db 27 dup(?)        ; cd device request header
; cblock          db 5 dup(?)         ; not sure if this is necessary

drivestart      dd ?                ; used for sector restriction
fat12start      dd ?                ; stores the sector number when fat12
                                    ; view mode was selected
cylinders       dw ?
heads           db ?
sectors         db ?

valuebuffer     db 11 dup(?)
rembytes        dw ?                ; remaining bytes when dealing with
                                    ; non-standard sized sectors

area            db ?            ; specifies where on a drive we are

rwhandle        dw ?            ; read/write file handle
rwfilesize      dd ?            ; read/write filesize
filehandle      dw ?
calladdress     dw ?
fillflag        dw ?
srflag          db ?
undelflag       db ?            ; 
driveflag       db ?            ; setdrive gets File or Drive? 0/1 respective
commandflag     db ?            ; used by unformat & gethex
chainflag       db ?            ; dictates what type of chain to save
                                ; fat links/file

; unformat
lostdirs        dw ?            ; total lost directories found
rootdirs        dw ?            ; total root directories found
dirs            dw ?            ; total dirs found
maxsize         dd ?            ; maximum filesize to recover
minsize         dd ?            ; minimum filesize to recover
nextsize        dd ?            ; next smallest filesize to recover

dirarray        db ?

WDE ends
END Start
