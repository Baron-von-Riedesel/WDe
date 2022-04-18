;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux
;
;-------------------------------------------------------
ROOTLINKED_DIRECTORY    EQU 00000001b
REGULAR_DIRECTORY       EQU 00000010b
UNLINKED_DIRECTORY      EQU 00000100b
UNTERMINATED_DIRECTORY  EQU 00001000b
PROCESSABLE_DIRECTORY   EQU 00010000b
PROCESSED_DIRECTORY     EQU 00100000b
SUB_DIRECTORY           EQU 01000000b
VALID_DIRECTORY         EQU 10000000b


UFDIR struct
bFlags    db ?
dwCluster dd ?
UFDIR ends

; commandflag for checkDirValidity function

VALIDATE                EQU 1
PROCESS                 EQU 2
FILE_RECOVERY           EQU 3

; writerootentry function

ROOT_DIRECTORY          EQU 1
LOST_DIRECTORY          EQU 2

;--- step1: scan clusters, must all be zero or 0ffffff7h
;--- step2: scan root directory, must be zero (just first entry is checked)
;--- step3: 
;
; flaws:
;   - there can be a blank sector in the middle of a directory cluster
;     with the remaining sectors filled.
;   - should check if [wDirs] > 65535
;     it should allocate more memory at ~8000 directories
;   - error handling missing for out of root entry problems

unformat proc

    mov eax, [dwCurSector]
    mov [dwSecBackup], eax
    mov [fromfat], 1                  ; always use fat 1
    mov dx, CStr('Scanning Fat...')
    call printbottom
    mov eax, 2                        ; start at cluster 2
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
    jne unformatError                 ; no, not acceptable
entryisok:
    inc eax                           ; cluster++
    cmp eax, [dwLastcluster]
    jbe continuefatscan

unffatok:
    mov eax, [dwRoot]                 ; jump to the root directory
    mov [ioreq.dwSector], eax
    call rwsectx
    jc abortUnformat
    mov dx, CStr('Root Not Blank')
    cmp byte ptr [sectbuffer], 0      ; check if first root entry is blank
    jne unformatError

;---------------------------------------------------------
;----------------------------------- scan for directories
;---------------------------------------------------------

    mov [dwCluster], 1                  ; start at cluster 1 (actually will be 2)
    mov [wDirs], 0                      ; init directory count

nextCluster:
    inc [dwCluster]

    mov eax, [dwCluster]
    cmp eax, [dwRootcluster]            ; matches root cluster?
    je nextCluster                      ; next cluster.

    call cluster2sector                 ; read first sector in cluster

    mov cl, [bSpc]

nextSectorOfCluster:
    call checkabort
    je abortUnformat

    cmp eax, [dwDataend]
    ja doneFindDirs

    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr('Searching Directories... (cluster %lX, directories %u)'), [dwCluster], [wDirs]
    call printbottom

    mov [ioreq.dwSector], eax
    call rwsectx                        ; need error checking b4 & after

    mov si, offset sectbuffer
    xor bx, bx
    call finddirectory
    jnc isDirectory
    cmp cl, [bSpc]                      ; if the first sector in a cluster
    je nextCluster                      ; is not a directory...scan next
                                        ; cluster
    mov bx, [wBps]
verifySectorNull:                       ; if the first sector of the cluster
    lodsb                               ; was a directory then check the
    test al, al                         ; remaining sectors if they're null
    jnz nextCluster                     ; (unused directory entries)
    dec bx
    jnz verifySectorNull

isDirectory:

    mov eax, [dwCurSector]
    inc eax                             ; increase sector # in cluster
    dec cl                              ; if there are sectors left, loop
    jnz nextSectorOfCluster

    mov bx, [wDirs]                     ; dirs*5 to find array position
    lea ebx,[ebx*4+ebx]                 ; sizeof UFDIR is 5
    add bx, [_mem]
    jc outofmemory                      ; 64 kB limit of DGROUP exceeded?
    cmp bx, - sizeof UFDIR
    jnc outofmemory
    inc [wDirs]

    mov [bx].UFDIR.bFlags, 0            ; zero this clusters attributes

    cmp cl, 0                           ; last sector in cluster?
    jne notLastSect
    mov si, [wBps]            
    cmp byte ptr [sectbuffer-32+si], 0        ; if the first byte of the
    je notLastSect                            ; last entry is not null, then
    or [bx].UFDIR.bFlags, UNTERMINATED_DIRECTORY  ; directory is unterminated
notLastSect:

    mov eax, [dwCluster]                ; set the cluster
    mov [bx].UFDIR.dwCluster, eax

    call cluster2sector

    cmp [dwCurSector], eax              ; if it's already the current sector
    je dontReRead                       ; don't re-read it.

    mov [ioreq.dwSector], eax           ; read first sector of cluster
    call rwsectx

dontReRead:
    cmp word ptr [sectbuffer], 202Eh            ; has "." entry?
    jne unlinkeddirectory
    cmp dword ptr [sectbuffer+32], 20202E2Eh    ; has ".." entry?
    jne unlinkeddirectory

    mov ax, word ptr [sectbuffer+32+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [sectbuffer+32+DIR_CLUST_LOW]

;--- the clusternumber may have been cleared!
;--- in that case only "regular" may be found - and nothing is recovered!

    cmp eax, [dwRootcluster]            ; check if directory was in the root
    jne regulardirectory

    or [bx].UFDIR.bFlags, ROOTLINKED_DIRECTORY OR PROCESSABLE_DIRECTORY
    jmp nextCluster

regulardirectory:
    or [bx].UFDIR.bFlags, REGULAR_DIRECTORY
    jmp nextCluster

unlinkeddirectory:
    or [bx].UFDIR.bFlags, UNLINKED_DIRECTORY
    jmp nextCluster

;---------------------------------------------------------
;------------------------ processing of directories
;---------------------------------------------------------
doneFindDirs:

    xor ax, ax
    mov [lostdirs], ax                  ; zero lost directory count
    mov [rootdirs], ax                  ; zero root directory count
    cmp [wDirs], ax
    mov dx, CStr('No Directories Found')
    je unformatError

    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr('Directories found: %u - recovering...'), [wDirs]
    call printbottom

dirsFound:

    mov ah, PROCESSABLE_DIRECTORY       ; the default is to search for
                                        ; processable directories
dirsFound2:                             ; <--- with ah=UNLINKED_DIRECTORY
    mov al, 0

    mov cx, [wDirs]
    mov bx, [_mem]

;--- the following loop sets all 'ah' directories to "processed"

processedLoop:
    call checkabort
    je abortUnformat
    test [bx].UFDIR.bFlags, PROCESSED_DIRECTORY
    jnz continueProcessedLoop
    test [bx].UFDIR.bFlags, ah
    jz continueProcessedLoop
    jmp foundProcessed
rejoinProcessedLoop:
    mov al, 1                   ; at least one processable directory found
continueProcessedLoop:
    dec cx
    jz findMoreProcessables     ; out of processed directories; find more
    add bx, sizeof UFDIR
    jmp processedLoop
findMoreProcessables:
    test al, al
    jnz dirsFound
    jmp dirProcessing

foundProcessed:

    or [bx].UFDIR.bFlags, PROCESSED_DIRECTORY

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
    jz nextSubDir

    and [bx].UFDIR.bFlags, NOT SUB_DIRECTORY
    cmp al, 1
    je nextSubDir

    or [bx].UFDIR.bFlags, PROCESSABLE_DIRECTORY

nextSubDir:
    add bx, sizeof UFDIR
    dec cx
    jnz checkForSubdirs
    pop bx
    pop cx
    cmp al, 1
    pop ax
    je rejoinProcessedLoop
    push ax

    or [bx].UFDIR.bFlags, VALID_DIRECTORY ; recover files from this directory
                                          ; in the next stage, since it's valid
    test [bx].UFDIR.bFlags, ROOTLINKED_DIRECTORY
    jz notRootLinked
    mov al, ROOT_DIRECTORY
    call writeRootEntry
notRootLinked:

    push bx                             ; terminate the current directory
    mov ebx, [dwCluster]                ; in the fat
    mov eax, 0FFFFFFFh
    call putfatentry
    pop bx
    mov [commandflag], PROCESS
    call checkDirValidity

    test [bx].UFDIR.bFlags, UNLINKED_DIRECTORY
    pop ax
    jz rejoinProcessedLoop

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
findUnterminated:
    cmp cx, [wDirs]               ; couldn't find an unterminated dir?
    je writeLDEntry               ; write "LOST0001" in the root

    inc cx
    sub bx, sizeof UFDIR          ; check previous item in the array

    test [bx].UFDIR.bFlags, UNTERMINATED_DIRECTORY
    jz findUnterminated

    ; found an unterminated directory, so remove unterminated bit
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

    jmp rejoinProcessedLoop

dirProcessing:

    cmp ah, UNLINKED_DIRECTORY  ; did we already search for unlinked dirs?
    je recoverFiles             ; yes, done.
    mov ah, UNLINKED_DIRECTORY  ; search for unlinked directories
    jmp dirsFound2

;---------------------------------------------------------
;- all files/subdirs of this directory must be in free space
;---------------------------------------------------------
checkDirValidity:
    push bx
    push cx
    mov eax, [dwCluster]          ; get cluster number for this directory
    call cluster2sector
    mov [dwCurSector], eax        ; get matching sector number

    mov dh, [bSpc]                ; number of sectors per cluster
            
checkNextSector:

    ;
    ; Error checking?
    ;

    call rwsect                 ; read the data in
    mov dl, 16                  ; 16 32-byte entries per directory sector
    xor si, si                  ; pointer to the entry being worked with

processNextEntry:
    cmp byte ptr [sectbuffer+si], 00            ; no entries left
    je validDir
    cmp word ptr [sectbuffer+si], 202Eh         ; skip "." entry
    je skipThisEntry
    cmp dword ptr [sectbuffer+si], 20202E2Eh    ; skip ".." entry
    je skipThisEntry

    cmp byte ptr [sectbuffer+si+DIR_ATTRIBUTES], 0Fh
    je skipThisEntry                            ; skip long filenames.

  ; acquire the cluster number of the file/directory entry
    mov ax, word ptr [sectbuffer+si+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [sectbuffer+si+DIR_CLUST_LOW]
    ;
    ; error checking for cluster # needed here
    ;

    cmp [commandflag], FILE_RECOVERY
    je doRecoverFiles
    cmp [commandflag], PROCESS
    je doSetEntryFatData

    cmp eax, [dwCluster]        ; cluster # of any entries within the
    je invalidDir               ; directory cannot match parent #
    push eax
    call getfatentry            ; get the matching fat entry
    test eax, eax               ; test to see if it's 0
    pop eax
    jnz invalidDir              ; if not, skip.

    test byte ptr [sectbuffer+si+DIR_ATTRIBUTES], DIRECTORY
    jz skipThisEntry            ; jump if not a directory

    cmp byte ptr [sectbuffer+si], 0E5h
    je skipThisEntry            ; jump if directory is deleted

    mov cx, [wDirs]
    mov bx, [_mem]

findClusterMatch:
    cmp [bx].UFDIR.dwCluster, eax   ; compare the starting cluster number of 
    je foundClusterMatch            ; the subdirectory with the list of detected
    add bx, sizeof UFDIR            ; directories.
    loop findClusterMatch

  ; If the subdirectories in the directory being checked for validity
  ; were not found scanning the entire hard drive, then the directory
  ; must be invalid --- it could be a false positive or directory information
  ; stored on a disk image saved on this drive (or something similar).

invalidDir:
    mov al, 1                   ; invalid directory
    jmp doneValidation

foundClusterMatch:
    or [bx].UFDIR.bFlags, SUB_DIRECTORY ; specify it's a located subdirectory
skipThisEntry:

    add si, 32                  ; check next entry
    dec dl
    jnz processNextEntry

    dec dh                      ; check next sector
    jz validDir                 ; finished if out of sectors

    inc [dwCurSector]
    jmp checkNextSector

doRecoverFiles:
    mov [dwCluster], eax        ; file cluster #
    mov ebx, dword ptr [sectbuffer+si+DIR_FILESIZE]
    mov [dwFilesize], ebx

    mov eax, [maxsize]
    cmp ebx, eax                        ; filesize smaller then maxsize?
    jbe skipSetNextSize                 ; too small.
    cmp [dwNextsize], eax               ; nextsize is smaller than maxsize?
    jb setNextSize                      ; set filesize as nextsize.
    cmp ebx, [dwNextsize]               ; filesize bigger than nextsize?
    jae skipSetNextSize                 ; abort.
setNextSize:
    mov [dwNextsize], ebx
skipSetNextSize:

    cmp ebx, [minsize]                  ; file must be bigger than minsize
    jbe skipThisEntry
    cmp ebx, [maxsize]                  ; file must be smaller/equal maxsize
    ja skipThisEntry

    call UndeleteCore

    jmp skipThisEntry

doSetEntryFatData:
    mov ebx, eax
    mov eax, 0FFFFFFFh
    call putfatentry
    jmp skipThisEntry

validDir:
    mov al, 0

doneValidation:
    pop cx
    pop bx
    ret

;---------------------------------------------------------
;------------------------ root directory entry re-writing
;---------------------------------------------------------
writeRootEntry:                         ; IN: si = offset sectbuffer

    push bx
    push cx

    mov ebx, [dwRoot]

    mov ch, [bSpc]                      ; start at the first root sector
    xor dx, dx                          ; zero the checked root entry count

checkNextRootSect:
    mov [ioreq.dwSector], ebx           ; error checking needed
    call rwsectx
    mov cl, 16                          ; 16 entries per sector
    mov si, offset sectbuffer           ; start with entry at offset 0

checkNextEntry:
    cmp byte ptr [si], 0                ; first byte of the entry is 0?
    je writeEntry
    add si, 32                          ; next entry
    dec cl
    jnz checkNextEntry

    add dx, 16                          ; add to total number of processed
                                        ; directory entries (dx)
    inc ebx                             ; increase sector #

    cmp [fattype], FT_FAT32
    jne maxEntryCheck
    dec ch                              ; spc processed < spc?
    jnz checkNextRootSect

      ;
      ; needs to find an empty cluster
      ;

maxEntryCheck:
    cmp dx, [rootentries]               ; reached maximum # of root entries?
    jb checkNextRootSect

      ;
      ; out of entries error handling
      ;

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
    and eax, 0000FFFFh

    call rendernumdec                           ; decimal representation
    mov eax, dword ptr [valuebuffer+6]          ; of the lost/root dir count
    or eax,'0000'                               ; since rendernumdec does no longer emit leading zeros
    mov dword ptr [si+04h], eax                 ; ("WDIR0001" etc)

    mov ax, word ptr [dwCluster+2]              ; high word of cluster #
    mov word ptr [si+DIR_CLUST_HIGH], ax
    mov ax, word ptr [dwCluster+0]              ; low word of cluster #
    mov word ptr [si+DIR_CLUST_LOW], ax

    mov dword ptr [si+08h], 10202020h           ; extension+attribs

    call writesect
    ;
    ; error checking
    ;
    pop cx
    pop bx
    ret

;---------------------------------------------------------
;------------------------ file recovery
;---------------------------------------------------------
recoverFiles:
    mov dx, CStr('Recovering Files...')
    call printbottom

    mov [minsize], eax

    mov eax, [dwBpc]            ; all single cluster files were recovered,
    mov [maxsize], eax          ; so set the minimum file recovery size
    add [maxsize], eax          ; to the minimum number of bytes required
                                ; to consume 2 clusters, and the maximum
    mov [minsize], eax          ; to the maximum required to fill 2 clusters.
  ; the file must be bigger than minsize and smaller or equal to maxsize

restartRecoveryLoop:

    mov bx, [_mem]
    mov cx, [wDirs]

RecoveryLoop:
    call checkabort
    je abortUnformat
    test [bx].UFDIR.bFlags, VALID_DIRECTORY
    jnz recoverValidFiles
continueRecoveryLoop:
    dec cx
    jz adjustMinMax
    add bx, sizeof UFDIR
    jmp RecoveryLoop

recoverValidFiles:

    mov eax, [bx].UFDIR.dwCluster
    mov [dwCluster], eax
    mov [commandflag], FILE_RECOVERY
    call checkDirValidity
    jmp continueRecoveryLoop

adjustMinMax:
    mov eax, [dwNextsize]
    cmp [maxsize], eax             ; nextsize is smaller or equal to maxsize,
    jae finishedUnformat           ; so no bigger files were found.

    mov edx, [dwBpc]
continueAdjustMinMax:
    add [minsize], edx
    add [maxsize], edx
    cmp [maxsize], eax
    jb continueAdjustMinMax
    jmp restartRecoveryLoop

finishedUnformat:
    cmp [bFats], 2
    jb noCopyF1toF2
    mov dx, CStr('Copying Fat-1 to Fat-2...')
    call printbottom
    mov eax, [dwReserved]
    mov ecx, [dwSpf]
    mov edx, [dwFatend]

f1tof2loop:
    mov [ioreq.dwSector], eax
    call rwsectx
    mov [ioreq.dwSector], edx
    call writesect
    inc eax
    inc edx
    dec ecx
    jnz f1tof2loop
noCopyF1toF2:

    mov eax, [dwSecBackup]
    mov [ioreq.dwSector], eax
    call rwsectx
    mov dx, CStr('Finished UnFormatting')
unformatError:
    call printerror
    ret
outofmemory:
    mov dx, CStr('Out of memory')
    jmp unformatError

abortUnformat:
    call updatescreen
    ret

unformat endp
;---------------------------------------------------------
