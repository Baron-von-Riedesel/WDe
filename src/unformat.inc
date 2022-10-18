;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux, 2022 japheth
;
;-------------------------------------------------------

;--- unformat didn't work for FAT32 until v0.99,
;--- because subdirectories of root have an ".." entry with
;--- cluster# 0000000, but root has a cluster# != 0.

;--- the disk is scanned for directories. Each directory is
;--- stored on the heap in a UFDIR structure.

UFDIR struct
bFlags    db ?
dwCluster dd ?
UFDIR ends

;--- values for bFlags field in UFDIR

ROOTLINKED_DIRECTORY    EQU 00000001b  ; cluster# of ".." matches that of root
REGULAR_DIRECTORY       EQU 00000010b  ; cluster# of ".." isn't that of root
UNLINKED_DIRECTORY      EQU 00000100b  ; directory without "." and ".." entry
UNTERMINATED_DIRECTORY  EQU 00001000b
PROCESSABLE_DIRECTORY   EQU 00010000b
PROCESSED_DIRECTORY     EQU 00100000b
SUB_DIRECTORY           EQU 01000000b
VALID_DIRECTORY         EQU 10000000b

; commandflag for checkDirValidity function

VALIDATE                EQU 0
PROCESS                 EQU 1
FILE_RECOVERY           EQU 2

; writerootentry function

ROOT_DIRECTORY          EQU 1
LOST_DIRECTORY          EQU 2

;--- 1.: scan FAT entries, must all be zero or 0ffffff7h
;--- 2.: scan root directory, must be zero (just first entry is checked)
;--- 3.: scan clusters for directories
;--- 4.: process all found directories in foundProcessed()
;--- 5.: file recovery - files larger than 1 cluster
;
; known bugs:
;   - there can be a blank sector in the middle of a directory cluster
;     with the remaining sectors filled.
;   - error handling missing for "out of root entries" problems
; also: too many directories may cause an "out of memory" error. The heap
; is located in DGROUP, free space about 50 kB, that's room for 10000 dirs.

unformat proc

    push bp
    mov bp, sp
    sub sp, 3*4+3*2

maxsize    equ <dword ptr [bp-4]>  ; maximum filesize to recover
minsize    equ <dword ptr [bp-8]>  ; minimum filesize to recover
nextsize   equ <dword ptr [bp-12]> ; next smallest filesize to recover
lostdirs   equ < word ptr [bp-14]> ; total lost directories found
rootdirs   equ < word ptr [bp-16]> ; total root directories found
wDirs      equ < word ptr [bp-18]> ; total dirs found

    mov [fromfat], FF_FAT1            ; always use fat 1
    mov dx, CStr('Scanning Fat...')
    call printbottom

;--- scan the whole FAT, beginning with entry 2, for values != 0 or ffffff7.
;--- For FAT32, start at 3 ( assuming root dir is at 2, size 1 cluster )

    mov eax, 2                        ; start at cluster 2
    test [filesys], FS_FAT32
    jz @F
    inc eax                           ; for FAT32, start at cluster 3
@@:
continuefatscan:
    call checkabort
    je abortUnformat
    push eax
    call getfatentry                  ; get fat data for this cluster
    mov edx, eax
    pop eax
    jc abortUnformat
    test edx, edx                     ; blank fat entry?
    jz entryisok                      ; yes, acceptable.
    cmp edx, 0FFFFFF7h                ; bad cluster?
    mov dx, CStr('Fat Table Not Blank')
    jne unformatError1                ; no, not acceptable
entryisok:
    inc eax                           ; cluster++
    cmp eax, [dwLastCluster]
    jbe continuefatscan

unffatok:
    mov eax, [dwRootSect]             ; jump to the root directory
    mov [ioreq.dwSector], eax
    call diskaccess_read
    jc abortUnformat
    mov dx, CStr('Root Not Blank')
    cmp byte ptr [sectbuffer], 0      ; check if first root entry is blank
    jne unformatError2

    @dprintfln "unformat: fat & root scan ok"

;---
;--- scan for directories
;---

    call scandirectories
    jc unformatError4
    @dprintfln "unformat: directory searching done"

;---
;--- processing of directories
;---

    xor ax, ax
    mov [lostdirs], ax                  ; zero lost directory count
    mov [rootdirs], ax                  ; zero root directory count
    cmp [wDirs], ax
    mov dx, CStr('No Directories Found')
    je unformatError3

    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr('Directories found: %u - recovering...'), [wDirs]
    call printbottom

dirsFound:

    mov ah, PROCESSABLE_DIRECTORY       ; the default is to search for
                                        ; processable directories
dirsFound2:
    mov al, 0
    mov cx, [wDirs]
    mov bx, [_mem]
    @dprintfln "unformat: start dirscan, ax=%X, wDirs=%u, bx=%X", ax, cx, bx

;--- the following loop sets all 'ah' directories to "processed"

processedLoop:
    call checkabort
    je abortUnformat
    test [bx].UFDIR.bFlags, PROCESSED_DIRECTORY
    jnz @F
    test [bx].UFDIR.bFlags, ah
    jz @F
    call foundProcessed
    mov al, 1                   ; at least one processable directory found
@@:
    add bx, sizeof UFDIR
    dec cx
    jnz processedLoop

    test al, al
    jnz dirsFound
    cmp ah, UNLINKED_DIRECTORY  ; did we already search for unlinked dirs?
    mov ah, UNLINKED_DIRECTORY
    jnz dirsFound2              ; if no, do now, else done.

;---
;--- file recovery. recover all files that are larger than 1 cluster
;---

    @dprintfln "unformat: recoverFiles"

    mov dx, CStr('Recovering Files...')
    call printbottom
                                  
;--- the strategy is to recover files from small sizes to larger sizes.
;--- for that 3 variables - minsize, maxsize, newsize - are maintained.

    mov eax, [dwBpC]            ; all single cluster files were recovered,
    mov [minsize], eax          ; so set the min. recovery size to [dwBpC]
    shl eax, 1
    mov [maxsize], eax          ; and the max to twice [dwBpC].

restartRecoveryLoop:
    mov bx, [_mem]
    mov cx, [wDirs]
recovernextdir:
    call checkabort
    je abortUnformat
    test [bx].UFDIR.bFlags, VALID_DIRECTORY
    jz @F
    @dprintfln "unformat: calling checkDirValidity(3), cluster=%lX", [bx].UFDIR.dwCluster
    mov eax, [bx].UFDIR.dwCluster
    mov [dwCluster], eax
    mov [commandflag], FILE_RECOVERY
    call checkDirValidity
@@:
    add bx, sizeof UFDIR
    dec cx
    jnz recovernextdir
    mov eax, [nextsize]
    cmp [maxsize], eax             ; nextsize is smaller or equal to maxsize,
    jae finishedUnformat           ; so no bigger files were found.
    mov edx, [dwBpC]
@@:
    add [minsize], edx
    add [maxsize], edx
    cmp [maxsize], eax
    jb @B
    jmp restartRecoveryLoop

;--- finished unformat

finishedUnformat:
    cmp [bFats], 2
    jb noCopyF1toF2
    mov dx, CStr("Copying Fat-1 to Fat-2...")
    call printbottom
    mov eax, [dwReserved]
    mov ecx, [dwSpF]
    mov edx, [dwFat1end]

f1tof2loop:
    mov [ioreq.dwSector], eax
    call diskaccess_read
    mov [ioreq.dwSector], edx
    call diskaccess_write
    inc eax
    inc edx
    dec ecx
    jnz f1tof2loop

noCopyF1toF2:
    mov dx, CStr('Finished UnFormatting')
unformatError1:
unformatError2:
unformatError3:
unformatError4:
    and dx, dx
    jz @F
    call printerror
@@:
abortUnformat:
    call readcursect

    mov sp, bp
    pop bp
    ret

unformat endp

;--- process a directory

foundProcessed proc

    or [bx].UFDIR.bFlags, PROCESSED_DIRECTORY

    @dprintfln "foundProcessed: processing dir (cx=%u, bx=%X), check for subdirectories", cx, bx

    ; check the directory for subdirectories.
    ; any subdirectories will have the 'SUB_DIRECTORY' bit set.
    ; any files/subdirectories will not have their first cluster used.
    push ax
    mov eax, dword ptr [bx].UFDIR.dwCluster
    mov [dwCluster], eax
    mov [commandflag], VALIDATE
    call checkDirValidity

    ; if the directory is deemed invalid, then AL=1,
    ; so any subdirectories are invalid and cannot be set to 'processed'
    push cx
    push bx
    mov cx, [wDirs]
    mov bx, [_mem]

checkForSubdirs:
    test [bx].UFDIR.bFlags, SUB_DIRECTORY
    jz @F
    and [bx].UFDIR.bFlags, NOT SUB_DIRECTORY
    cmp al, 1
    je @F
    or [bx].UFDIR.bFlags, PROCESSABLE_DIRECTORY
@@:
    add bx, sizeof UFDIR
    dec cx
    jnz checkForSubdirs
    pop bx
    pop cx
    cmp al, 1
    pop ax
    je done_foundProcessed
    push ax

    or [bx].UFDIR.bFlags, VALID_DIRECTORY ; recover files from this directory
                                          ; in the next stage, since it's valid
    test [bx].UFDIR.bFlags, ROOTLINKED_DIRECTORY
    jz @F
    mov al, ROOT_DIRECTORY
    call writeRootEntry
@@:

    @dprintfln "foundProcessed: terminate directory, cluster %lX", [dwCluster]
    push bx                             ; terminate the current directory
    mov ebx, [dwCluster]                ; in the fat
    mov eax, 0FFFFFFFh
    call putfatentry
    pop bx
    mov [commandflag], PROCESS
    call checkDirValidity

    test [bx].UFDIR.bFlags, UNLINKED_DIRECTORY
    pop ax
    jz done_foundProcessed

    ; Next we deal with pieces of directories that have so many files
    ; that some of the directory data is placed further on the drive.
    ; This is done by recursing the array searching for a directory
    ; that is an UNTERMINATED_DIRECTORY, then connecting it to the next
    ; unlinked directory in the fat.

    ; unlinked directory will now be processed, so remove the
    ; unlinked bit and set it as a regular directory

    and [bx].UFDIR.bFlags, NOT UNLINKED_DIRECTORY
    or [bx].UFDIR.bFlags, REGULAR_DIRECTORY

    push ax
    push cx
    push bx
@@:
    cmp cx, [wDirs]               ; couldn't find an unterminated dir?
    je writeLDEntry               ; write "LOST0001" in the root
    inc cx
    sub bx, sizeof UFDIR          ; check previous item in the array
    test [bx].UFDIR.bFlags, UNTERMINATED_DIRECTORY
    jz @B

;--- found an unterminated directory, so remove unterminated bit
    and [bx].UFDIR.bFlags, NOT UNTERMINATED_DIRECTORY
                                      
    mov eax, [dwCluster]          ; link the unlinked directory
    mov ebx, [bx].UFDIR.dwCluster ; with the unterminated directory
    call putfatentry
    jmp foundUnterminated

writeLDEntry:
    mov al, LOST_DIRECTORY
    call writeRootEntry
foundUnterminated:
    pop bx
    pop cx
    pop ax
done_foundProcessed:
    ret

foundProcessed endp

;---------------------------------------------------------
;--- root directory entry re-writing
;--- IN: AL = ROOT_DIRECTORY (1), LOST_DIRECTORY (2)

writeRootEntry proc

    @dprintfln "writeRootEntry enter, ax=%X", ax

    push bx
    push cx

;--- scan root directory for an empty entry

    mov ebx, [dwRootSect]
    mov ch, [bSpC]                      ; start at the first root sector
    xor dx, dx                          ; zero the checked root entry count

checkNextRootSect:
    mov [ioreq.dwSector], ebx           ; error checking needed
    call diskaccess_read
    @dprintfln "unformat: writeRootEntry, root sector %lu read", ebx
    mov cl, 512 / DIRENTSIZE            ; 16 entries per sector
    mov si, offset sectbuffer           ; start with entry at offset 0

checkNextEntry:
    cmp byte ptr [si], 0                ; first byte of the entry is 0?
    je writeEntry
    add si, DIRENTSIZE                  ; next entry
    dec cl
    jnz checkNextEntry

    add dx, 512 / DIRENTSIZE            ; add to total number of processed
                                        ; directory entries (dx)
    inc ebx                             ; increase sector #

    test [filesys], FS_FAT32            ; FAT12/FAT16?
    je maxEntryCheck
    dec ch                              ; spc processed < spc?
    jnz checkNextRootSect
      ;
      ; todo: needs to find an empty cluster
      ;
    @dprintfln "unformat: writeRootEntry FAT32 out of root entries"
    jmp wre_exit
maxEntryCheck:
    cmp dx, [rootentries]               ; reached maximum # of root entries?
    jb checkNextRootSect
      ;
      ; todo: out of entries error handling
      ;
    @dprintfln "unformat: writeRootEntry FAT1X out of root entries"
    jmp wre_exit
writeEntry:
    cmp al, LOST_DIRECTORY
    je writeLostDir
    mov dword ptr [si], 'RIDW'          ; "WDIR"
    inc [rootdirs]
    mov ax, [rootdirs]
    jmp writtenDirType
writeLostDir:
    mov dword ptr [si], 'TSOL'          ; "LOST"
    inc [lostdirs]
    mov ax, [lostdirs]
writtenDirType:
    movzx eax, ax
    add ax, 10000                       ; ensure there are "leading zeros" generated

    call rendernumdec                           ; decimal representation
    mov eax, dword ptr [valuebuffer+6]          ; of the lost/root dir count
    mov dword ptr [si+04h], eax                 ; ("WDIR0001" etc)

    mov eax, [dwCluster]
    mov word ptr [si+DIR_CLUST_LOW], ax
    shr eax, 16
    mov word ptr [si+DIR_CLUST_HIGH], ax
    mov dword ptr [si+08h], 10202020h           ; extension+attribs

    call diskaccess_write                       ; write [ioreq.dwSector]

    @dprintfln "writeRootEntry: exit, root dir (sec %lu) entry written: >%s<", [ioreq.dwSector], si
wre_exit:
    pop cx
    pop bx
    ret

writeRootEntry endp

;--- scan the whole partition for directories

scandirectories proc

    mov [dwCluster], 1                ; start at cluster 1 (actually will be 2)
    mov [wDirs], 0                    ; init directory count

nextCluster:
    inc [dwCluster]

    mov eax, [dwCluster]
    cmp eax, [dwRootCluster]          ; matches root cluster?
    je nextCluster                    ; next cluster.

    call checktime
    jc @F

    call checkabort
    je abort

    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr('Searching Directories... (cluster %lX, directories %u)'), [dwCluster], [wDirs]
    call printbottom
    call darkclr3
@@:

    call cluster2sector                 ; read first sector in cluster

    mov cl, [bSpC]

nextSectorOfCluster:

    cmp eax, [dwDataend]
    ja doneFindDirs

    mov [ioreq.dwSector], eax
    call diskaccess_read                ; need error checking b4 & after

    mov si, offset sectbuffer
    call IsDirectory
    jnc directory_found
    cmp cl, [bSpC]                      ; if the first sector in a cluster
    je nextCluster                      ; is not a directory...scan next
                                        ; cluster
    mov bx, [wBps]
verifySectorNull:                       ; if the first sector of the cluster
    lodsb                               ; was a directory then check the
    test al, al                         ; remaining sectors if they're null
    jnz nextCluster                     ; (unused directory entries)
    dec bx
    jnz verifySectorNull

directory_found:

    mov eax, [ioreq.dwSector]
    inc eax                             ; increase sector # in cluster
    dec cl                              ; if there are sectors left, loop
    jnz nextSectorOfCluster

    mov bx, [wDirs]                     ; dirs*5 to find array position
    lea ebx,[ebx*4+ebx]                 ; sizeof UFDIR is 5
    add bx, [_mem]
    jc outofmemory                      ; 64 kB limit of DGROUP exceeded?
    cmp bx, - sizeof UFDIR
    jnc outofmemory

    @dprintfln "unformat: directory found at cluster %lX, cnt=%u, mem=%X", [dwCluster], [wDirs], bx

    inc [wDirs]

    mov [bx].UFDIR.bFlags, 0            ; zero this clusters attributes

    cmp cl, 0                           ; last sector in cluster?
    jne notLastSect
    mov si, [wBps]            
    cmp byte ptr [sectbuffer-DIRENTSIZE+si], 0; if the first byte of the
    je notLastSect                            ; last entry is not null, then
    or [bx].UFDIR.bFlags, UNTERMINATED_DIRECTORY  ; directory is unterminated
notLastSect:

    mov eax, [dwCluster]                ; set the cluster
    mov [bx].UFDIR.dwCluster, eax

    call cluster2sector

    cmp [ioreq.dwSector], eax           ; if it's already the current sector
    je dontReRead                       ; don't re-read it.

    mov [ioreq.dwSector], eax           ; read first sector of cluster
    call diskaccess_read

dontReRead:
    cmp word ptr [sectbuffer], 202Eh            ; has "." entry?
    jne unlinkeddirectory
    cmp dword ptr [sectbuffer+DIRENTSIZE], 20202E2Eh    ; has ".." entry?
    jne unlinkeddirectory

    mov ax, word ptr [sectbuffer+DIRENTSIZE+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [sectbuffer+DIRENTSIZE+DIR_CLUST_LOW]

;--- v0.99: the clusternumber of the ".." is 0000000 for subdirs of root in FAT32!
;--- in that case only "regular" may be found - and nothing is recovered!

    cmp [filesys], FS_FAT32
    jnz @F
    cmp eax, 0
    jz rootlinked
@@:
    cmp eax, [dwRootCluster]            ; check if directory was in the root
    jne regulardirectory
rootlinked:
    @dprintfln "unformat: directory marked ROOTLINKED or PROCESSABLE (cluster# of '..' is %lX)", eax
    or [bx].UFDIR.bFlags, ROOTLINKED_DIRECTORY OR PROCESSABLE_DIRECTORY
    jmp nextCluster

regulardirectory:
    @dprintfln "unformat: directory marked REGULAR, (cluster# of '..' is %lX)", eax
    or [bx].UFDIR.bFlags, REGULAR_DIRECTORY
    jmp nextCluster

unlinkeddirectory:
    @dprintfln "unformat: directory marked UNLINKED"
    or [bx].UFDIR.bFlags, UNLINKED_DIRECTORY
    jmp nextCluster

doneFindDirs:
    ret
outofmemory:
    mov dx, CStr('Out of memory')
    stc
    ret
abort:
    xor dx, dx
    stc
    ret
scandirectories endp

;---
;--- checkDirValidity
;--- in: [dwCluster]   : start of directory
;---     [commandflag] : what to do exactly
;---
;--- all files/subdirs of the directory must be in free space
;---

checkDirValidity proc
    push bx
    push cx

    .const
cmdvecs label word
    dw validatecmd
    dw processcmd
    dw recoverfilescmd
    .code

    @dprintfln "checkDirValidity enter, commandflag[lobyte]=%X", word ptr [commandflag]
    mov eax, [dwCluster]        ; cluster number for this directory
    call cluster2sector         ; get matching sector number
    mov edi, eax
    mov dh, [bSpC]              ; number of sectors per cluster
            
checkNextSector:

    mov [ioreq.dwSector], edi
    call diskaccess_read        ; read the data into sectbuffer
    ;
    ; jc doneValidation
    ;
    mov dl, 512 / DIRENTSIZE
    mov si, offset sectbuffer   ; pointer to the entry being worked with

processNextEntry:
    cmp byte ptr [si], 00       ; no entries left?
    je validDir
    cmp word ptr [si], " ."     ; skip "." & ".." entries
    je entrydone
    cmp dword ptr [si], "  .."
    je entrydone
    cmp byte ptr [si], 0E5h
    je entrydone                ; skip deleted entries
    cmp byte ptr [si+DIR_ATTRIBUTES], 0Fh
    je entrydone                ; skip LFNs

;--- get the cluster number of the entry

    mov ax, word ptr [si+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [si+DIR_CLUST_LOW]
    ;
    ; error checking for cluster # missing here
    ;
    movzx bx,[commandflag]
    shl bx, 1
    call [bx+cmdvecs]
    jc doneValidation
entrydone:
    add si, DIRENTSIZE          ; check next entry
    dec dl
    jnz processNextEntry
    inc edi
    dec dh                      ; check next sector
    jnz checkNextSector
validDir:
    mov al, 0
doneValidation:
    @dprintfln "checkDirValidity exit, ax=%X", ax
    pop cx
    pop bx
    ret

;-----------------------------

validatecmd:
    @dprintfln "checkDirValidity: VALIDATE [name=%s, cluster=%lX]", si, eax

    cmp eax, [dwCluster]        ; cluster # of any entries within the
    je invalidDir               ; directory cannot match parent #
    push eax
    call getfatentry            ; get the matching fat entry
    test eax, eax               ; test to see if it's 0
    pop eax
    jnz invalidDir              ; if not, skip.

    test byte ptr [si+DIR_ATTRIBUTES], DA_DIRECTORY
    jz validate_done            ; jump if not a directory

    mov cx, [wDirs]
    mov bx, [_mem]
@@:
    cmp [bx].UFDIR.dwCluster, eax   ; compare the starting cluster number of 
    je foundClusterMatch        ; the subdirectory with the list of detected
    add bx, sizeof UFDIR        ; directories.
    loop @B

  ; If the subdirectories in the directory being checked for validity
  ; were not found scanning the entire hard drive, then the directory
  ; must be invalid --- it could be a false positive or directory information
  ; stored on a disk image saved on this drive (or something similar).

invalidDir:
    mov al, 1                   ; invalid directory
    stc
    ret
foundClusterMatch:
    or [bx].UFDIR.bFlags, SUB_DIRECTORY ; specify it's a located subdirectory
validate_done:
    clc
    ret

;-----------------------------

recoverfilescmd:

    mov [dwCluster], eax        ; file start cluster#
    mov ebx, [si+DIR_FILESIZE]
    mov [dwFilesize], ebx

    mov eax, [maxsize]
    cmp ebx, eax                        ; filesize <= maxsize?
    jbe skipSetNextSize                 ; ignore for setting nextsize

;--- v0.99: a small bug, resulting in premature end of file recovery:
;--- if nextsize == maxsize, the larger filesize is ignored
    cmp [nextsize], eax                 ; nextsize <= maxsize?
;    jb setNextSize
    jbe setNextSize                     ; set filesize as nextsize.

    cmp ebx, [nextsize]                 ; filesize >= nextsize?
    jae skipSetNextSize                 ; ignore for setting nextsize
setNextSize:
    mov [nextsize], ebx
skipSetNextSize:

    @dprintfln "checkDirValidity: FILE_RECOVERY [name=%s, cluster=%lX, size=%lu] min/max/next=%lu/%lu/%lu", si, [dwCluster], ebx, [minsize], [maxsize], [nextsize]

    cmp ebx, [minsize]                  ; filesize must be > minsize
    jbe done_recoverfiles
    cmp ebx, [maxsize]                  ; filesize must be <= maxsize
    ja done_recoverfiles

    @dprintfln "checkDirValidity: FILE_RECOVERY, calling UndeleteCore"
    mov al, 1
    call UndeleteCore
done_recoverfiles:
    clc
    ret

;-----------------------------

processcmd:
    @dprintfln "checkDirValidity: PROCESS [name=%s, cluster=%lX]", si, eax
    mov ebx, eax
    mov eax, 0FFFFFFFh
    call putfatentry
    clc
    ret

checkDirValidity endp

maxsize    equ <>
minsize    equ <>
nextsize   equ <>
lostdirs   equ <>
rootdirs   equ <>
wDirs      equ <>

;---------------------------------------------------------
