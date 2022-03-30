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
; the binary was originally created with tasm32 5.3 and tlink 7.1.32.2,
; now it's done using jwasm; alternately, Masm + MS link may be used.
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

	.model tiny
	option casemap:none ;symbols are case sensitive
	.dosseg             ;segment order: _TEXT, _DATA, CONST, _BSS
	.386


;        _DEBUG           EQU 1 ; uncomment to assemble in debug mode
;        ?BASIC           EQU 1 ; uncomment to disable extended functionality
        UNDEFINED        EQU 0
        ?VDD             EQU 1  ; 1=winXP VDD supported
        ?LFN             EQU 0  ; try to use LFN functions

        CD_SECTOR_OFFSET EQU 10h  ; can't read first 16 sectors of CDs

; "bRW" variable
        READ             EQU 0
        WRITE            EQU 1

; "fattype" variable
        FAT32            EQU 4
        FAT16            EQU 2
        FAT12            EQU 1

; "bRegion" variable for figuring out what section we're on in the drive
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
        EM_DEFAULT       EQU 0
        EM_ASCII         EQU 1

; "displaymode" variable
        DM_HEX           EQU 0
        DM_BINARY        EQU 1

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
        SR_SAVE          EQU 0
        SR_RESTORE       EQU 1

; "chainflag" variable
        NO_CHAIN         EQU 0
        FILE_CHAIN       EQU 1
        FAT_CHAIN        EQU 2

; "commandflag" variable for gethex
        GET_VALUE        EQU 0
        GET_STRING       EQU 1


;--- define a string in .const
CStr macro text:vararg
local sym
    .const
sym db text,0
    .code
    exitm <offset sym>
endm

;--- display string on the windows debug terminal.
;--- this works only if running in a WinXP/Vista DOS-Box.
@DbgOut macro text
local xxx
ifdef _DEBUG
    call dbgout
    jmp xxx
    db text,0
xxx:
endif
endm

;--- struct BPB, located in boot sector

BPB struct
    db 11 dup (?)
bytes_sector     dw ?   ;+0
sectors_cluster  db ?
reserved_sectors dw ?   ;+3
num_fats         db ?
root_entries     dw ?   ;+6
sectors_fat12    dw ?   ;(sectors total FAT12)
media_byte       db ?
sectors_fat      dw ?   ;+11 (sectors/fat for fat12/fat16)
sectors_track    dw ?
no_of_tracks     dw ?
hidden_sectors   dd ?   ;+17
sectors_fat16    dd ?   ;+21 (sectors total FAT16/32)
BPB ends

;--- FAT12/FAT16 extended BIOS parameter block
EBPB struct
    BPB <>
phys_drive      db ?    ;+0x19
                db ?
ext_boot_sig    db ?    ;=0x29
volume_id       dd ?
volume_label    db 11 dup (?)
fs_type         db 8 dup (?)
EBPB ends

EBPB_FAT32 struct
    BPB <>
sectors_fat32   dd ?    ;+0x19 (sectors/fat for fat32)
flags           dw ?
version         dw ?
root_startcl    dd ?    ;+0x21
fs_info_start   dw ?    ;+0x25 start sector of FS information sector
bs_copy_start   dw ?
    db 12 dup (?)
phys_drive      db ?    ;+0x35
                db ?
ext_boot_sig    db ?    ;+0x37
volume_id       dd ?
volume_label    db 11 dup (?)   ;if boot_sig is != 0x28
fs_type         db 8 dup (?)    ;"FAT32   "
EBPB_FAT32 ends

;--- HD access for int 13h, ah=42h/43h

DAP struct
bSize       db ?    ;+0 size of structure
bRes        db ?    ;+1 reserved
wNumSec     dw ?    ;+2 sectors to transfer
union
dwBuffer    dd ?    ;+4 transfer buffer SSSS:OOOO
struct
wBufferOfs  dw ?
wBufferSeg  dw ?
ends
ends
union
dqStartSector dq ?  ;+8
struct
dwStartLow  dd ?    ;+8  start sector low
dwStartHigh dd ?    ;+12 start sector high
ends
ends
;dqAddr     dq ?    ;EDD 3.0: 64bit flat transfer buffer address if dwBuffer is FFFF:FFFF
DAP ends

;--- extended disk io structure for int 25h/26h, int 21h ax=7305h

DISKIO struct
startsec dd ?
sectors  dw ?
buffofs  dw ?
buffseg  dw ?
DISKIO ends

	.const

initialmenu     db 3                    ; 3 spaces between each
                db 0,1,2,3,4,5,6,-1

jumpmenu        db 2
                db 7,8,9,10,11,12,13,-1

cdjumpmenu      db 0
                db 7,-1

viewmenu        db 2
                db 25,17,9,39,40,41,26,-1

searchmenu      db 3
                db 27,28,17,9,31,26,-1

fillmenu        db 3
                db 28,27,32,33,42,34,-1

idmenu          db 3
                db 35,36,37,38,-1

filemenu        db 3
                db 14,15,-1

cdfilemenu      db 3
                db 14,24,-1


pdfilemenu      db 2
                db 16,17,18,19,20,21,-1

ldfilemenu      db 3
                db 16,9,10,11,12,22,-1

chainmenu       db 2
                db 16,9,10,11,12,22,23,-1

funcmenu0       db 3
                db 30,29,-1
ifndef ?BASIC
funcmenu1       db 3
                db 30,29,44,-1
funcmenu2       db 3
                db 30,29,44,43,-1
endif

introtext       db 'WDe V0.33',0
copyright       db 'Copyright(C) 2005 Ben Cadieux',0

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

menustrings     db 'Save',0                             ; 0
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
szPartition     db 'Partition',0                        ; 22
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
        ifndef ?BASIC
                db 'UnDelete',0                         ; 43
                db 'UnFormat',0                         ; 44
        endif


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

;--- a dword-aligned _BSS segment is needed,
;--- hence simplified segment directive .data? cannot be used.
_BSS segment dword public 'BSS'
startbss label byte
_BSS ends
DGROUP group _BSS

_BSS segment

old24h          dd ?
stackbot        dw ? ; stack bottom
vidseg          dw ? ; video buffer segment
vidcolsize      dw ?
vidrows         db ?
vidpg           db ?
scrn_xy         label word ; xy position on screen
scrn_col        db ?
scrn_row        db ?
crsr_xy         dw ? ; cursor xy position
maxleft         db ?
bRW             db ? ; distinguish between read/write
subsector       db ? ; because [spot] goes from 0-511, if we have sectors
                     ; that are >512 bytes, subsector keeps track of what
                     ; 512-byte piece we're working with
bHL             db ? ; keeps track of whether we're editing high or low nibble
spot            dw ? ; keeps count of what byte we're editing 0-511

	align dword
bDrive          db ? ; drive number
fattype         db ? ; type of fat
bSpc            db ? ; sectors per cluster
bFats           db ? ; number of fats
dwSpf           dd ? ; sectors per fat
dwFatend        dd ? ; end of fat
dwReserved      dd ? ; reserved sectors (start of fat)
rootentries     dw ? ; number of root entries
wRootsectors    dw ? ; number of root sectors
dwSector        dd ? ; sector for read/writes
;dwSectorHigh    dd ? ; high sector dword for int13h
dwDataend       dd ? ; end of data
; dwDataendHigh   dd ? ; high dword for int13h HUGE hds
dwDatastart     dd ? ; start of data
dwLastcluster   dd ? ; total # of clusters on the drive
dwRoot          dd ? ; root directory
dwRootcluster   dd ? ; root cluster (FAT32)
dwValue         dd ?
dwMaxvalue      dd ?
dwFilesize      dd ?
dwCluster       dd ?
dwBpc           dd ? ; bytes per cluster
dwSecBackup     dd ? ; sector backup
partitions      dd ?,?,?,? ; partition start sectors

hdnumber        db ? ; hard drive number partition belongs to
spcmd           db ? ; sectors per cluster for doing bitshifts
backupbs        dw ? ; backup boot sector location (FAT32)
fsinfo          dw ? ; fsinfo sector (FAT32)

;--- accessed as WORD!
rwfunction      db ? ; what read/write function to use
drivetype       db ? ; logical/physical/etc

fromfat         db ? ; fat to use for getfatentry/putfatentry
bRegion         db ? ; what part of the disk we're in
status          db ?,? ; error in called function? (2 bytes defined, since this var is pushed/poped)
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
viewmode        db ?,?
displaymode     db ? ; hex or binary
editmode        db ? ; what mode being edited in (ascii/default)

; [highlight]: 11223333h
;        11: Number of bytes to highlight on screen
;        22: Number of bytes deviating from [spot] to highlight for
;        3333: Starting [spot] to highlight from

highlight       label dword ; area to highlight with viewmode
highlight_ofs   dw ? ;starting spot (offset)
highlight_size  db ? ;size of spot
highlight_scsiz db ? ;num of cells to highlight on screen

wBps            dw ? ; bytes per sector
spcc            db ? ; sectors per cluster counter
handling        db ? ; how to handle errors:
                     ;  3: ignore errors
                     ;  2: query user with "skip"
                     ;  1: query user with "fill with zero"
                     ;  0: abort by default

seed12          label dword
seed1           dw ?
seed2           dw ?
seed34          label dword
seed3           dw ?
seed4           dw ?

rwhandle        dw ?            ; read/write file handle
dwRwfilesize    dd ?            ; read/write filesize
wFilehandle     dw ?
wCalladdress    dw ?
fillflag        db ?,?
area            db ?            ; specifies where on a drive we are
srflag          db ?            ; "file ops" menu flag
undelflag       db ?            ; 
driveflag       db ?            ; setdrive gets File or Drive? 0/1 respective
commandflag     db ?            ; used by unformat & gethex
chainflag       db ?            ; dictates what type of chain to save
                                ; fat links/file
dwDrivestart    dd ?            ; used for sector restriction
dwFat12start    dd ?            ; stores the sector number when fat12
                                ; view mode was selected
cylinders       dw ?
heads           db ?
sectors         db ?

; unformat
maxsize         dd ?            ; maximum filesize to recover
minsize         dd ?            ; minimum filesize to recover
dwNextsize      dd ?            ; next smallest filesize to recover
lostdirs        dw ?            ; total lost directories found
rootdirs        dw ?            ; total root directories found
dirs            dw ?            ; total dirs found

ifdef _DEBUG
  storedeax     dd ?
  storedebx     dd ?
  storedecx     dd ?
  storededx     dd ?
  storedsi      dd ?
  storeddi      dd ?
endif

rembytes        dw ?            ; remaining bytes when dealing with
                                ; non-standard sized sectors
filename        db 69 dup(?)
stringbuffer    db 76 dup(?)
diskinfobuffer  db 1Ah dup(?)   ; buffer for int13h "get drive info"
fat12fix        db 5 dup(?)     ; stores first borrowed byte for fat12
	align 4
readbuffer      db 2352 dup(?)  ; read buffer for sector reading
fat12fix2       db ?            ; stores last borrowed byte for fat12/CD
	align 4
writebuffer     db 2352 dup(?)  ; write buffer for sector writing
cdheader        db 27 dup(?)    ; cd device request header
; cblock          db 5 dup(?)   ; not sure if this is necessary

valuebuffer     db 11 dup(?)

;--- used by unformat. expected to be the last item
;--- in _BSS, since it will modify the region behind this var!
dirarray        db ?

_BSS ends

	.code

	org 100h

Start:

	call init            ;clear .data?, check video mode, init screen
	mov [stackbot],sp

;--- scan command line
	mov si,80h
	movzx cx,byte ptr [si]
	inc si
@@:
	jcxz donecmdline
	lodsb
	dec cl
	cmp al,' '
	jbe @B
	mov ah,[si]
	cmp al,'0'
	jb donecmdline
	cmp al,'9'
	jbe maybedrive
	mov bx, FAT*100h + OLDINT25
	or al,20h
	cmp al,'a'
	jb donecmdline
	cmp al,'z'
	ja donecmdline
	sub al,'a'
	cmp ah,':'
	jz drive_entered
	jmp donecmdline
maybedrive:
	mov bx, PHYSICAL*100h + NEWINT13
	sub al,'0'
	or al,80h
	cmp ah,13
	jz drive_entered
	or ah,20h
	cmp ah,'h'
	jz drive_entered
	and al,7fh
	cmp ah,'f'
	jz drive_entered

donecmdline:
	call setdrive
	jnc drive_entered
	call quit
	jmp donecmdline
drive_entered:
	call trydevice
	jc donecmdline
	call clearsecarea           ; clear sector rectangle (contains copyright msg)

drive_ok:
	call setvariables           ; set all obtainable parameter variables
	call printoffset            ; print current offset

mainmenu proc

	mov sp,[stackbot]
	push offset mainmenu
	mov [handling], ABORT_OPERATION
	call updatescreen
	mov dx, offset initialmenu
	call printmenu

getkeyagain:
	call printview              ; print view may change with cursor moves

	mov ax, [crsr_xy]           ; set [scrn_xy] to cursor coordinates so that
	mov [scrn_xy], ax           ; functions like changemode color the right
                                ; spot on the screen
	call getkey

  cmp al, ESCAPE_KEY
  je quit

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

  cmp ah, F1_KEY
  je savetodisk

  cmp ah, F2_KEY                      ; different menu for CDRoms
  je submenu_fileops

  cmp ah, F3_KEY
  je submenu_jumpto

  cmp ah, F4_KEY
  je submenu_view

  cmp ah, F5_KEY
  je submenu_find

  cmp ah, F6_KEY
  je submenu_functions

  cmp ah, F7_KEY
  je submenu_disk

  cmp ah, TAB_KEY
  je changemode

  push offset getkeyagain
  cmp ah, LEFT_KEY
  je moveleft

  cmp ah, RIGHT_KEY
  je moveright

  cmp ah, UP_KEY
  je moveup

  cmp ah, DOWN_KEY
  je movedown

mainmenu endp

;--- fall thru!
;--- "normal" key processing in main menu

domod proc

  cmp ah, DEL_KEY       ; allow writing of null when using the delete key
  je @F                 ; in ascii editing mode
  cmp al, 0             ; don't write null values in ascii for certain
  je skipmod            ; extended keys (F8-F12 for example)
@@:
  cmp [editmode], EM_ASCII
  je modascii
skipmod:
  cmp [displaymode], DM_BINARY
  je modbinary

  mov dl, al            ; back up the key pressed for printing

  sub al, '0'           ; subtract 48, so '0'-'9' becomes 0-9
  cmp al, 9
  jbe number            ; below or equal to 9?  a number was typed.

  sub al, 17            ; 'A'-'0' = 17, so make A-F = 0-5

  cmp al, 5             ; below or equal to 'F'?
  jbe cletter           ; then a hex letter was typed

  cmp al, 37            ; check again
  ja done

  sub dl, 32            ; possibly lower case, which are 32 bytes higher
  sub al, 32            ; so subtract 32 bytes for printing/use

cletter:

  add al, 10            ; A-F are currently 0-5, so make them 10-15
;-------------------------------------------------------
number:
  call printchar

modifybuffer:
  mov dx, [spot]

  call aspotcalc
  mov [scrn_xy], dx
  call spotinbx
  mov dl, byte ptr [readbuffer+bx]      ; get the byte to be edited from
                                        ; the buffer

  cmp [bHL], 0
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
done:
  ret
domod endp

;--- try a new device
;--- AL = drive number
;--- BL = access
;--- BH = PHYS/FAT/CDROM

trydevice proc
  mov dx, offset readingdrive
  call printbottom

  push [dwSector]               ; if drive switching is unsuccessful
  push word ptr [bDrive]        ; the original drive/sector has to
  push word ptr [rwfunction]    ; be restored
  push [dwDrivestart]

  mov [subsector], 0            ; rwfunction is the 'read/write'
  mov [dwSector], 0             ; function being used.  2 for CDrom,
  mov [dwDrivestart], 0
  mov [rwfunction], bl          ; type of read/write functions
  mov [drivetype], bh
  mov [bDrive], al              ; attempt to read sector 0
  call rwsect
  cmp [status], ERROR           ; failed?
  je driveerror

; if the drive could be set just fine,
; then the pushed data (last drive, etc) can be skiped
  add sp, 12
  ret

driveerror:

  pop [dwDrivestart]
  pop word ptr [rwfunction]     ; restore original drive settings
  pop word ptr [bDrive]         ; if reading the new drive failed
  pop [dwSector]
  stc
  ret
trydevice endp

;--- enter a disk/drive/image filename
;--- exit: C if ESC pressed or a ""-filename was entered
;---       NC, then drive in AL, modes in BX

setdrive proc
	cmp [driveflag], 0
	jne fnreq
	mov dx, offset drivemsg     ; "Drive:"
	call printbottom            ; print on the bottom of the screen
getkeyagain:
	call cursorgetkey           ; cursorgetkey turns the cursor on, gets
                                ; a key and then shuts the cursor back off
                                ; again (for normal editing)
	cmp al, ESCAPE_KEY
	je abort
	cmp ah, TAB_KEY
	je handle_tabkey

	sub al, '0'                 ; subtract 48, so '0' becomes 0, '1' = 1, etc
	cmp al, 9                   ; if the value is <= 9, the key pressed was
	jbe hdphysical              ; a drive number, 0-9

	mov bx, FAT*100h + OLDINT25
	sub al, 17                  ; 17 is the 65-48, so 'A' = 0, 'B' = 1, etc
	cmp al, 26                  ; if the value is > 26, a non-letter
	jbe done                    ; was pressed (non-valid drive letter)

	sub al, 32                  ; 32 is 'a'-'A', so 'a' = 0, 'b' = 2, etc
	cmp al, 26                  ; same concept as above
	jbe done
	jmp getkeyagain

hdphysical:                     ; this is for setting up the
                                ; editing for a physical
                                ; rather than logical drive
	mov cl, al                  ; back up drive number
	mov dx, offset fhdmsg       ; choose between floppy and HD
	call printbottom
@@:
	call cursorgetkey
	cmp al, ESCAPE_KEY
	je setdrive
	cmp ah, SCAN_F
	je readasfd
	cmp ah, SCAN_H
	jne @B
	add cl, 80h                 ; physical hard drive.
readasfd:
	mov al, cl
;--- al: 80h+ = hard drive
;--- al: 00h+ = floppy
	mov bx, PHYSICAL*100h + NEWINT13
	jmp done

abort:
	stc
	ret
handle_tabkey:
	xor [driveflag], 1
	jmp setdrive

fnreq:
	call getfilename
	cmp ah, TAB_KEY
	je handle_tabkey
	jcxz abort                  ; no chars entered, or ESC pressed
	call findfile
	jnc @F
	mov dx, offset filenotfound
	call printerror
	jmp fnreq
@@:
	call getfilesize
;	mov eax, [dwFilesize]      ; file must be 1+ sectors in size
	cmp eax, 512
	jnc @F
	mov dx, offset toosmall
	call printerror
	jmp fnreq
@@:
	mov [dwRwfilesize], eax
	call openfile
	mov ax, [wFilehandle]
	mov [rwhandle], ax
	mov bx, PHYSICAL*100h + FILEFUNC
	mov al, 0FFh
done:
	clc
	ret
setdrive endp

;--- submenu "disk"

submenu_disk proc
@@:
  call setdrive
  jc done
  call trydevice
  jnc drive_ok
  jmp @B
done:
  ret
submenu_disk endp

;-------------------------------------------------------
;--- rewrite current sector
savetodisk proc
    mov dx, offset readingmsg
    call printbottom
    call copybuffer                     ; copy readbuffer to writebuffer
    push word ptr [subsector]           ; remember subsector number
    mov [bRW], WRITE                    ; set to write sector
    call rwsect                         ; write it.
    pop word ptr [subsector]
    cmp [status], ERROR
    je @F
    mov dx, offset donermsg
    call printerror
@@:
    ret
savetodisk endp
;-------------------------------------------------------
restrictsectors proc
  mov dx, offset abmsg
  call printbottom
rsgetkeys:
  call cursorgetkey
  cmp al, ESCAPE_KEY
  je submenu_functions
  cmp ah, SCAN_A
  je restrictabove
  cmp ah, SCAN_B
  jne rsgetkeys
restrictbelow:
    mov eax, [dwSector]                 ; set the current sector as the
    mov [dwDataend], eax                ; last sector of the drive
    ret
restrictabove:
    mov eax, [dwSector]                 ; set the current sector as the
    add [dwDrivestart], eax             ; first sector; this is added to
    sub [dwDataend], eax                ; [dwSector] for r/w, so adjust the
    xor eax, eax                        ; final sector accordingly
    mov [dwSector], eax
      mov dx, offset plmsg
      call printbottom
      rsgetkeys2:
      call cursorgetkey
      cmp al, ESCAPE_KEY
      je submenu_functions
      mov dl, PHYSICAL
      cmp ah, SCAN_P
      je donesetpl
      cmp ah, SCAN_F
      jne rsgetkeys2
      mov dl, FAT
    donesetpl:
      mov [drivetype], dl
      call setvariables
      ret
restrictsectors endp
;-------------------------------------------------------
submenu_functions proc
  mov dx,offset funcmenu0

  ifndef ?BASIC
    cmp [drivetype], FAT
    jne nlfdf

    mov si, offset readbuffer
    xor bx, bx
    call finddirectory 

    mov dx,offset funcmenu1

    jc nlfdf                      ; dir not found
    call spotinbx               ; if a directory is found, check to see if
    and bl, 11100000b           ; the very first entry of the current file
                                ; we're in (cur_byte / 32) is equal to
                                ; E5h, if so, we should display the option
                                ; to undelete

    cmp byte ptr [readbuffer+bx], 0E5h
    jne nlfdf

    mov dx,offset funcmenu2

    nlfdf:
  endif

  push dx
  call printmenu
  pop dx

getkeyagain13:
  call getkey

  cmp al, ESCAPE_KEY
  je done

  cmp ah, F1_KEY
  je restrictsectors

  cmp ah, F2_KEY
  je fillfunctions

  ifndef ?BASIC
    cmp dx, offset funcmenu0
    je getkeyagain13

    cmp ah, F3_KEY
    je unformat

    cmp dx, offset funcmenu1
    je getkeyagain13

    cmp ah, F4_KEY
    je undelete
  endif
    jmp getkeyagain13
done:
    ret

submenu_functions endp

ifndef ?BASIC
;------------------------------------------------------
include UNDELETE.INC
;------------------------------------------------------
include UNFORMAT.INC
;------------------------------------------------------
endif

fillstring:
  call getstring

dofill:

  jcxz fillfunctions
  call getnos
  je fillfunctions

    mov dx, offset readingmsg
    call printbottom
  push [dwSector]
  push ds
  pop es
  mov di, offset readbuffer

  mov ax, [wBps]
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

    mov ax, [wBps]
  jmp cfloop

;--- submenu "fill"
fillfunctions:
  mov dx, offset fillmenu
  call printmenu

getkeyagain14:
  call getkey

  cmp al, ESCAPE_KEY
  je submenu_functions

  cmp ah, F1_KEY
  je fillhex

  cmp ah, F2_KEY
  je fillstring

  cmp ah, F4_KEY
  je decremental

  mov [fillflag+1], INCREMENT

  cmp ah, F3_KEY
  je incremental

  mov [fillflag], INVERSE

  cmp ah, F5_KEY
  je fillinvrand

  mov [fillflag], RANDOM

  cmp ah, F6_KEY
  je fillinvrand

  jmp getkeyagain14
;-----------------------------------------------------
decremental:
  mov [fillflag+1], DECREMENT
incremental:
  mov dx, offset idmenu
  call printmenu
  getkeyagain15:
  call getkey

  cmp al, ESCAPE_KEY
  je fillfunctions

  mov dx, offset hexmsg

  xor ecx, ecx

  mov [fillflag], BIT8
  mov cl, 0FFh
  cmp ah, F1_KEY
  je fillamount

  mov [fillflag], BIT12
  mov ch, 0Fh                           ; ECX=0FFFh
  cmp ah, F2_KEY
  je fillamount

  mov [fillflag], BIT16
  mov ch, 0FFh                          ; ECX=0FFFFh
  cmp ah, F3_KEY
  je fillamount

  mov [fillflag], BIT32
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
  push ds
  pop es

  push [dwSector]
  mov di, offset readbuffer
  keeprandomfill:
  mov cx, [wBps]                        ; \Fixed?/

  cmp [fillflag], BIT12
  je do12fill
  cmp [fillflag], BIT8                  ; writing byte at a time?
  je dontshift                          ; then dont divide by 2
    shr cx, 1                           ; divide by 2 to write words
  cmp [fillflag], BIT16                 ; if we're writing 32-bits at a time
  je dontshift
    shr cx, 1                           ; divide by 2 again
  dontshift:
  cmp [fillflag], INVERSE
  jne randomloop                        ; inverse function requires reading
    mov si, di                          ; every sector to reverse that data
    call rwsect
    cmp [status], ERROR
  je fillerror

  randomloop:
    cmp [fillflag], INVERSE
    jne tryrandfill
      lodsd                             ; reverse a dword at a time
      not eax
    jmp continuerandinv
    tryrandfill:
    cmp [fillflag], RANDOM
    jne continuerandinv
      push cx
      call rand                         ; generate random value (eax)
      pop cx
    continuerandinv:
    cmp [fillflag], BIT16
    je fill16bit
    cmp [fillflag], BIT8
    je fill8bit
    stosd

    cmp [fillflag], BIT32               ; inverse/random are finished
    jne doriloop
    fill32bit:
      cmp [fillflag+1], DECREMENT
      je decdword
        inc eax
        jmp doriloop
      decdword:
        dec eax
        jmp doriloop

    fill16bit:
      stosw
      cmp [fillflag+1], DECREMENT
      je decword
        inc ax                          ; increment word
        jmp doriloop
      decword:
        dec ax                          ; decrement word
        jmp doriloop

    fill8bit:                           ; byte
      stosb
      cmp [fillflag+1], DECREMENT
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
  pop [dwSector]
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
    mov cx, [wBps]              ; \Fixed?/

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
    mov cx, [wBps]              ; \Fixed?/

  n2s22:
    mov ax, dx
    shr ax, 4
    stosb

  loop n3s22
    call fillcommon
    jc fillerror
    jz donefillrand
    mov cx, [wBps]              ; \Fixed?/

  n3s22:
    mov ax, dx
    call cax12
  jmp do12fill
;-----------------------------------------------------
fillerror:
    pop [dwSector]
    push word ptr [status]
    call rwsect
    call updatescreen
    pop word ptr [status]
    cmp [status], ERROR
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
  mov [bRW], WRITE
  call rwsect
  cmp [status], ERROR
  je commonfillerror
  dec [dwValue]
  jz donefillinc
  inc [dwSector]
  call printcounts
  push ds
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
  cmp [fillflag+1], INCREMENT
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

;--- main menu: key entered in binary mode
modbinary proc
  call spotinbx                 ; get the current cursor position
  mov cl, [bHL]
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
  jne done
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

  mov dx, bx                            ; set [scrn_xy] to the next bit
  call aspotcalc
  mov [scrn_xy], dx
  mov dl, byte ptr [readbuffer+bx]      ; replace the ascii on the screen
  call printchar
  jmp moveright
done:
  ret
modbinary endp

;--- main menu: character entered in ascii mode

modascii proc
  call spotinbx
  mov byte ptr [readbuffer+bx], al
  mov bx, [spot]
  mov dx, bx
  call spotcalc
  mov [scrn_xy], dx

  cmp [displaymode], DM_HEX
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
    mov [scrn_xy], dx

    mov cl, 1
    call printchar2
  jmp moveright
modascii endp

;--- main menu tab & shift-tab keys
changemode proc
  cmp al, 0                     ; shift+tab?
  je @F
  xor [editmode], 1             ; switch between ascii/regular editing
  call colorchar
  ret
@@:
  xor [displaymode], 1          ; switch between hex/binary editing
  call clearsecarea
  xor dl, dl
  mov ax, [spot]
  call movecursor
  ret
changemode endp

;--- main menu ctrl-enter

retfat proc
  cmp [drivetype], FAT               ; won't work with non-logical drives
  jne done
  mov eax, [dwSector]
  test eax, eax                      ; if we're on a logical drive, attempt
  jz log2phys                        ; to jump to respective phys. drive

  test [bRegion], DATA_AREA
  jz done

;retcluster:
  call sector2cluster
  call go2entry
  call rwsect
done:
  ret
log2phys:                            ; jump from logical drive
  mov al, [hdnumber]                 ; to parent physical drive
  mov bx, PHYSICAL*100h + NEWINT13
  call trydevice
  jnc drive_ok
  ret

retfat endp

;--- main menu ctrl-left

recursechain proc
  cmp [bRegion], FAT_AREA
  jne done

  call getcurrententry                  ; ebx = current entry number

  mov eax, ebx                          ; no where to recurse from
  cmp ebx, 2                            ; starting (2nd) cluster
  jbe done

  push [scrn_xy]
  mov dx, offset recursemsg
  call printbottom
  pop [scrn_xy]

recurse:
    call checkabort
    je done

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
done:
  ret
recursechain endp

;--- main menu ctrl-right key
jumpcluster proc
  cmp [bRegion], FAT_AREA
  je jumpfatcluster
  test [bRegion], DATA_AREA
  jz done
;jumpdatacluster:
  mov eax, [dwSector]
  mov [fromfat], 1
  call sector2cluster                   ; get respective cluster number
  call getfatentry                      ; read fat entry
  cmp [status], ERROR
  je done

  jmp jumptoeax                         ; jump to the cluster number read
;-------------------------------------------------------
jumpfatcluster:

  call getcurrententry
  cmp [status], ERROR
  je done

dochainjump::

  cmp eax, 2            ; disregard ebx, which is the current entry #
  jb done               ; we only care about eax, the value stored there.
;  cmp eax, 0FFFFFF7h
;  jae done

  cmp eax, [dwLastcluster]
  ja done
  push [dwSector]
  call go2entry
  pop edx
  cmp edx, [dwFatend]           ; bad coding.  doesn't support 3+ fats
  jb nsf
  mov ecx, [dwSpf]
  add [dwSector], ecx
nsf:
  cmp [dwSector], edx           ; don't read the same sector twice
  je done
  call rwsect
done:
  ret
jumpcluster endp

;--- main menu enter key
entercluster proc
  cmp [drivetype], FAT
  jne done

  cmp [viewmode], ROOTVIEW
  je enterfiledir

  call getentrynumber                   ; get the cluster number for current
jumptoeax::                             ; offset
  cmp eax, 2
  jb done
  call cluster2sector                   ; multiply it out to get the
  cmp eax, [dwDataend]                  ; corresponding sector number
  ja done                               ; verify that it's a valid sector
  mov [dwSector], eax
  call rwsect
  jmp done
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
done:
  ret
entercluster endp

;-------------------------------------------------------
submenu_view proc
  mov dx, offset viewmenu
  call printmenu

getkeyagain1:
  call getkey

  cmp al, ESCAPE_KEY
  je done

  cmp ah, F1_KEY
  je defaultview
  jb getkeyagain1

  mov al, ah
  sub al, 59

ifdef _DEBUG                             ; extra view for registers
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

  mov eax, [dwSector]
  mov [dwFat12start], eax

  dsf12s:
  call checksetview
  ret
;-------------------------------------------------------
defaultview:
  mov byte ptr [viewmode+1], AUTODETECT
  call printcounts
done:
  ret
submenu_view endp

;-------------------------------------------------------
submenu_find proc
  mov dx, offset searchmenu
  call printmenu

  mov [handling], QUERY_SKIP

getkeyagain8:
  call getkey

  cmp al, ESCAPE_KEY
  je done

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
@@:
  xor bx, bx
  call finddirectory
  jnc done
  call findcommon
  jmp @B
done:
  ret
;-------------------------------------------------------
findbs:
  mov si, offset readbuffer
findbsnext:
  cmp dword ptr [si+1fch], 0AA550000h           ; check for boot sig ++
  jne findbs2
  cmp byte ptr [si], 0EBh                       ; check for jmp
  je done
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
  je done
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
  je done                               ; no, MBR found.

  findmbr2:
  call findcommon
  jmp findmbrnext

;-------------------------------------------------------
findhex:
  mov dx, offset hexmsg
  call gethexstring
  jc submenu_find

  test cx, cx
  jz submenu_find

  mov dx, offset searchingmsg
  call printbottom
  jmp stringsearch

submenu_find endp

;-------------------------------------------------------
updatescreen proc

  call printcounts
  call printsector

    cmp byte ptr [viewmode+1], AUTODETECT       ; detect the view type
    jne continueprintview
    mov dl, [bRegion]

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
      cmp [dwSector], 0
      je setbsview
      movzx eax, [backupbs]
      cmp [dwSector], eax
      je setbsview
      movzx edx, [fsinfo]
      cmp [dwSector], edx               ; in the fsinfo sector?
      je setfsview                      ; then set fsinfo view
      add edx, eax                      ; checks if we're in the backup
      cmp [dwSector], edx               ; fsinfo sector...but it assumes
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
  cmp [fattype], FAT12
  jne tryfat16view

    mov eax, [dwReserved]
    add eax, [dwSpf]
    cmp eax, [dwSector]
    jbe okasis12
      sub eax, [dwSpf]
okasis12:
    mov [dwFat12start], eax

    mov dl, FAT12VIEW
tryfat16view:
    cmp [fattype], FAT16
    jne tryfat32view
    mov dl, FAT16VIEW
tryfat32view:
    cmp [fattype], FAT32
    jne donechoosingfat
    mov dl, FAT32VIEW
donechoosingfat:
  jmp dontscanfordir
updatescreen endp

;--- menu item "find string"
findstring proc
  call getstring

  jcxz abortfindstring
    mov dx, offset searchingmsg
    call printbottom
stringsearch::
    mov word ptr [stringbuffer+74], cx  ; save length in last 2 bytes of buffer
    xor bx, bx
    xor si, si

nextbyte:
    mov al, byte ptr [stringbuffer+si]
    cmp al, byte ptr [readbuffer+bx]
    je comparenextbyte
    cmp bx, si                          ; if so much of the string matched
    jae dontgolastsect                  ; until now that a sector was crossed
      add bx, 512

      dec [subsector]                   ; then back up to continue search
      jnz dontgolastsect

      dec [dwSector]
      call rwsect
dontgolastsect:
      sub bx, si
      xor si, si

continuefindstring0:
    inc bx                              ; next byte in sector

    cmp bx, [wBps]                      ; last byte?
    je nextfindsector                   ; jump to next sector
    mov ah, bh
    shr ah, 1                           ; calculate our current subsector
    mov [subsector], ah

    jmp nextbyte

comparenextbyte:
  inc si                                ; next byte
  cmp si, word ptr [stringbuffer+74]    ; end of string?
  jne continuefindstring0
  ret                                   ; found string. return to main menu

nextfindsector:
  mov eax, [dwDataend]
  cmp eax, [dwSector]
  je stringnotfound
  inc [dwSector]
  call rwsect
  cmp [status], ERROR
  je abortfindstring

  call checkabort
  je abortfindstring

  call printcounts
  xor bx, bx
  jmp nextbyte
findstring endp

abortfindstring:
  call updatescreen
  jmp submenu_find
stringnotfound:
  mov dx, offset stringerror
  call printerror
  jmp submenu_find

;--- file submenu

submenu_fileops proc

  mov [srflag], SR_SAVE
;--- for CDROMs, there's no "restore", so skip this menu
  cmp [drivetype], CDROM
  je srfileoptions

  mov dx, offset filemenu  ; save/restore sectors
  call printmenu
getkeyagain5:
  call getkey
  cmp al, ESCAPE_KEY
  je done

  push offset submenu_fileops
  cmp ah, F1_KEY
  setne [srflag]           ; set SR_SAVE (=0) mode if equal, otherwise SR_RESTORE
  je srfileoptions
  cmp ah, F2_KEY
  je srfileoptions
  pop ax
  jmp getkeyagain5
done:
  ret
submenu_fileops endp
;-------------------------------------------------------

savechain proc
  mov [fromfat], 1
  call srcommon

  mov [dwFilesize], 0
  cmp [chainflag], FAT_CHAIN
  je begincsave

    call spotinbx
    and bl, 11100000b                    ; chop off 0-31 bytes to set bx to
    add bx, offset readbuffer            ; the start of the current entry
    mov eax, dword ptr [bx+DIR_FILESIZE] ; filesize
    mov [dwFilesize], eax
    mov ax, word ptr [bx+DIR_CLUST_HIGH] ; high cluster word
    shl eax, 16
    mov ax, word ptr [bx+DIR_CLUST_LOW]  ; low cluster word

    mov [dwSecBackup], eax               ; back the cluster number up
    cmp eax, 2
    jb f2great                           ; outside of valid cluster range
    call cluster2sector
    cmp eax, [dwDataend]
    ja f2great
    push eax
    mov eax, [dwSecBackup]
    call getfatentry
    mov [dwSecBackup], eax
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
  mov [dwSecBackup], eax                ; current entry's data
  mov eax, ebx
  call cluster2sector
  cmp eax, [dwDataend]
  ja f2great                            ; current entry is beyond data end

startchainsaving:
  push ax
  call createfile
  pop ax
  cmp [status], ERROR
  je srfileoptions

chainsaveloop:
  movzx ebx, [bSpc]                     ; save sectors per cluster worth of
  mov [dwValue], ebx                    ; sectors.
  call writefile
  cmp [status], ERROR
  je srfileoptions

  mov eax, [dwSecBackup]
  call cluster2sector
  cmp eax, [dwDataend]
  ja donechainsave

  push eax
  mov eax, [dwSecBackup]
  call getfatentry
  mov [dwSecBackup], eax
  pop eax
  jmp chainsaveloop

donechainsave:
  cmp [dwFilesize], 0
  je notruncate

  mov ax, 4201h                         ; seek from current file position
  mov bx, [wFilehandle]
  xor cx, cx
  xor dx, dx
  int 21h

  shl edx, 16
  mov dx, ax

  cmp edx, [dwFilesize]
  jbe notruncate

  mov dx, offset truncatemsg
  call printbottom
  call getyn
  jnc notruncate

    mov ax, 4200h                       ; seek from start of file
    mov bx, [wFilehandle]
    mov dx, word ptr [dwFilesize+0]
    mov cx, word ptr [dwFilesize+2]
    int 21h

    xor cx, cx                          ; write to file, 0 bytes (truncate)
    mov ah, 40h
    mov bx, [wFilehandle]
    int 21h

notruncate:


  call closefile
  call rwsect
  mov dx, offset donemsg
  call printerror

  jmp srfileoptions
savechain endp

;-------------------------------------------------------

restchain proc
  call srcommon

  mov eax, [dwSector]
  mov [dwSecBackup], eax

  call getcurrententry
  cmp [chainflag], FAT_CHAIN
  je restclusts
    mov [fromfat], 1
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

  mov [dwCluster], eax
  call cluster2sector                   ; fix?  checking needed for sector.
  mov [dwSector], eax
  mov al, [bSpc]
  mov byte ptr [spcc], al

dornsb:

  mov ah, 3Fh
  mov bx, [wFilehandle]
  mov cx, [wBps]
  mov dx, offset writebuffer
  int 21h
  jc disperread

  cmp ax, cx
  je docwrite
    call rwsect
    cmp [status], ERROR
    je srfileoptions
    push ds                             ; preserve bytes at end of sector
    pop es
    sub cx, ax
    mov si, offset readbuffer
    add si, ax
    mov di, offset writebuffer
    add di, ax
    rep movsb
docwrite:
  mov [bRW], WRITE
  call rwsect
  cmp [status], ERROR
  je srfileoptions
  cmp ax, cx
  jne donerestchain

  dec byte ptr [spcc]
  jz restnextclust
  inc [dwSector]
  jmp dornsb
restnextclust:

  mov eax, [dwCluster]
  call getfatentry
  cmp eax, 0FFFFFF7h
  jae donerestchain
  cmp eax, 2
  jae rbuhs

donerestchain:

    mov eax, [dwSecBackup]
    mov [dwSector], eax
    call rwsect

    mov dx, offset donermsg
    call printerror

  jmp srfileoptions
disperread:
    mov dx, offset errorread
    call printerror
    jmp srfileoptions
restchain endp

;-------------------------------------------------------
srcommon proc
  push ax
  call getfilename
  pop ax
  jcxz srskip
  cmp [srflag], SR_RESTORE
  jne skipffsr
  call findfile
  jnc filefound2
  mov dx, offset filenotfound
  call printerror
srskip:
  add sp,2  ;skip return address
  jmp srfileoptions
filefound2:
skipffsr:
  ret
srcommon endp
;-------------------------------------------------------
savefile proc
  call srcommon
  call getnos

  cmp [status], ERROR
  je srfileoptions

  mov eax, [dwSector]
  jmp endsavedrive
savefile endp

;--- submenu file options
srfileoptions proc

;  cmp [srflag], SR_SAVE
;  jne startfileops

  cmp [drivetype], CDROM
  jne startfileops
  mov dx, offset cdfilemenu
  call printmenu
  jmp getkeyagain0

startfileops:
    call printfilemenu
getkeyagain0:
    call getkey
    cmp al, ESCAPE_KEY
    je done

    cmp [srflag], SR_RESTORE
    je crfile
      cmp ah, F1_KEY
      je savefile
crfile:
      cmp ah, F1_KEY
      je restfile

    cmp [drivetype], CDROM
    je cdf2check

    cmp ah, F2_KEY      ; bootsect
    je srsector0

    cmp [drivetype], PHYSICAL
    je hdsfcheck

    cmp ah, F3_KEY
    je srfat1
    cmp ah, F4_KEY
    je srfat2
    cmp ah, F5_KEY
    je srroot
    cmp [srflag], SR_RESTORE
    je crdrive
      cmp ah, F6_KEY
      je dumpiso
    crdrive:
      cmp ah, F6_KEY
      je restdrive

    cmp [chainflag], NO_CHAIN
    je getkeyagain0

    cmp [srflag], SR_RESTORE
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
    mov si, offset partitions

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

  jmp getkeyagain0
done:
  ret
srfileoptions endp

;-------------------------------------------------------
srroot:
  call srcommon

  mov eax, [dwRoot]
  xor edx, edx

  cmp [fattype], FAT32
  jne userootsects
    mov dl, [bSpc]
    jmp dorootsr
  userootsects:
    mov dx, [wRootsectors]

  dorootsr:
  mov [dwValue], edx
  cmp [srflag], SR_SAVE
  je endsavedrive
  jmp endrestsectors
;-------------------------------------------------------
restdrive:
  mov eax, [dwDataend]
  mov [dwValue], eax

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

  push [dwSector]
  xor edx, edx
  mov [dwSector], edx
  call rwsect
  mov ebx, dword ptr [readbuffer+bx]
  mov [dwValue], ebx
  pop [dwSector]
  cmp [srflag], SR_RESTORE
  je endrestsectors
;-------------------------------------------------------
endsavedrive:
  call savedata
  jmp srfileoptions
;-------------------------------------------------------
srfat1:
  mov eax, [dwReserved]
  jmp srfat
;-------------------------------------------------------
srfat2:
  cmp [bFats], 2
  jb srfat1
  mov eax, [dwFatend]
      ;-------------------------------------------------------
srfat:
  call srcommon
    mov edx, [dwSpf]
    mov [dwValue], edx
  cmp [srflag], SR_SAVE
  je endsavedrive
  jmp endrestsectors
;-------------------------------------------------------
srsector0:
  call srcommon
  xor eax, eax
  mov [dwValue], 1
  cmp [srflag], SR_SAVE
  je endsavedrive
  jmp endrestsectors
;-------------------------------------------------------
restfile:
  call srcommon
  call getfilesize
  movzx ebx, [wBps]
  cmp eax, ebx
  jae filesizeok
  toosmallerr:

  mov dx, offset toosmall
  call printerror

  jmp srfileoptions

  filesizeok:  

;  mov eax, [dwFilesize]

  xor edx, edx
  div ebx

  mov ebx, [dwDataend]
  sub ebx, [dwSector]
  inc ebx

  cmp eax, ebx                          ; if there are more sectors in the
  jbe mvok                              ; file than there are remaining
    xchg eax, ebx                       ; on the partition; then set number
  mvok:                                 ; of partition sectors remaining
                                        ; as maxvalue
  mov dx, offset sectorsmsg
  call inputvalue

  cmp [status], ERROR
  je srfileoptions

  mov eax, [dwSector]
  jmp endrestsectors

;--- submenu "Goto" for physical disk

submenu_jumpto_phys proc
  mov dx, offset pdfilemenu
  call printmenu

getkeyagain11:
  call getkey

  cmp al, ESCAPE_KEY
  je done
  cmp ah, F1_KEY
  je jumptosector
  cmp ah, F2_KEY
  je jumptobootsector

  mov ebx, [partitions+0]
  cmp ah, F3_KEY
  je donejump

  mov ebx, [partitions+4]
  cmp ah, F4_KEY
  je donejump

  mov ebx, [partitions+8]
  cmp ah, F5_KEY
  je donejump

  mov ebx, [partitions+12]
  cmp ah, F6_KEY
  je donejump

  jmp getkeyagain11
done:
  ret
submenu_jumpto_phys endp

;--- submenu goto

submenu_jumpto proc
  cmp [drivetype], PHYSICAL
  je submenu_jumpto_phys

  mov dx, offset jumpmenu
  cmp [drivetype], CDROM
  jne @F
  mov dx, offset cdjumpmenu
@@:
  call printmenu

getkeyagain2:
  call getkey

  cmp al, ESCAPE_KEY
  je done
  cmp ah, F1_KEY
  je jumptosector

  cmp [drivetype], CDROM
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
    mov ebx, [dwDatastart]
    jmp donejump
jumptocluster:
  mov eax, [dwLastcluster]
  mov dx, offset clustermsg
  call gethex
  jc done
  mov eax, ebx
  jmp jumptoeax

jumptobootsector::
    xor ebx, ebx
    jmp donejump
jumptofat1:
    mov ebx, [dwReserved]
    jmp donejump
jumptofat2:
    cmp [bFats], 2
    jb jumptofat1
    mov ebx, [dwFatend]
    jmp donejump
jumptoroot::
    mov ebx, [dwRoot]

donejump::
  cmp [dwDataend], ebx
  jb @F
  mov [dwSector], ebx
  call rwsect
@@:
done:
  ret
;-------------------------------------------------------
jumptosector::
  mov eax, [dwDataend]
  mov dx, offset sectormsg
  call inputvalue
  cmp [status], ERROR
  je submenu_jumpto

  mov ebx, [dwValue]
  jmp donejump
;-------------------------------------------------------
jumptolastsect::
  mov ebx, [dwDataend]
  jmp donejump
submenu_jumpto endp

;--- main menu csr-up
moveup:
  xor ax, ax
  mov dl, [bHL]
  cmp [editmode], EM_ASCII
  je regularmoveup
  cmp [displaymode], DM_BINARY
  je binarymoveup
regularmoveup:
  sub ax, 12
binarymoveup:
  sub ax, 4
  jmp domove
;--- main menu csr-down
movedown:
  xor ax, ax
  mov dl, [bHL]
  cmp [editmode], EM_ASCII
  je regularmovedown
  cmp [displaymode], DM_BINARY
  je binarymovedown
regularmovedown:
  add al, 12          ; see moveup
binarymovedown:
  add al, 4
  jmp domove
;--- main menu csr-left
moveleft:
  mov dl, [bHL]
  xor ax, ax
  cmp [editmode], EM_ASCII
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
    cmp [displaymode], DM_HEX
    je dohexaddonly
      mov dl, 7
    dohexaddonly:
    inc dl
    deconly:
    dec ax
  jmp domove
;--- main menu csr-right
moveright:
  mov dl, [bHL]
  xor ax, ax
  cmp [editmode], EM_DEFAULT
  jne sr_iax

  cmp [displaymode], DM_HEX
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
domove proc
  add ax, [spot]
  cmp ax, 512
  jae done

  push [spot]                   ; back old cursor spot up
  call movecursor               ; spot is changed to ax
  pop ax

  cmp [displaymode], DM_BINARY
  jne dontchangescreens
    mov bx, [spot]              ; figures out if we've crossed a 128-byte
    shl ax, 1                   ; barrier by checking if the high bits have
    shl bx, 1                   ; changed.  if so, then we need to redraw,
    cmp bh, ah                  ; otherwise there's no need to waste CPU.
    je dontchangescreens
    call printsector
dontchangescreens:
  call printoffset
done:
  ret
domove endp
;-------------------------------------------------------
; viewmode; see the variable definition for details

printview:

  mov al,[viewmode]
;  mov bx, offset viewmode
  cmp al, BOOTSECTORVIEW
  je bsview
  cmp al, FAT12VIEW
  je fat12viewmode
  cmp al, FAT16VIEW
  je fat16viewmode
  cmp al, FAT32VIEW
  je fat32viewmode
  cmp al, ROOTVIEW
  je dirview
  cmp al, MBRVIEW
  je hd0view
  cmp al, FSINFOVIEW
  je fsinfoviewmode

ifdef _DEBUG
  cmp al, DEBUGVIEW
  je debugviewmode
endif

;  call clearview

  ret
;-------------------------------------------------------
readbufferinsi:         ; OUT:  si -> offset to current subsector buffer
  movzx ax, [subsector]
  shl ax, 9
  mov si, offset readbuffer
  add si, ax
  ret
;-------------------------------------------------------
fsinfoviewmode proc
  mov [scrn_xy], 2201h

  call readbufferinsi

  mov [highlight], 0A0401E8h
  mov dx, CStr('Total Free Clusters: ')

  dofcssfc: 
  call printstring
  mov bx, [highlight_ofs]
; dec bx

  mov eax, dword ptr [si+bx]
  cmp eax, 0FFFFFFFFh
  jne vbik
    mov [highlight_scsiz], 07h
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

  mov [highlight_scsiz], 0Ah
  mov byte ptr [highlight_ofs], 0ECh	;gives 1ECh as offset
  mov dx, CStr('First Free Cluster:  ')
  jmp dofcssfc
fsinfoviewmode endp

;-------------------------------------------------------
dirview proc
  mov [scrn_xy], 2201h

  call readbufferinsi

  mov cx, [spot]

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

  mov [highlight], 0601000Bh
  add [highlight_ofs], bx
  call bshighlight

  mov al, byte ptr [si+bx+DIR_ATTRIBUTES]

  mov dx, 'A' + (100h * ARCHIVE)
  call testattrib

  mov dx, 'D' + (100h * DIRECTORY)
  call testattrib

  mov dx, 'V' + (100h * VOLUME)
  call testattrib

  mov dx, 'S' + (100h * SYSTEM)
  call testattrib
  
  mov dx, 'H' + (100h * HIDDEN)
  call testattrib

  mov dx, 'R' + (100h * READONLY)
  call testattrib

  add [scrn_col], 9

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

  mov [highlight], 0101000Dh
  add [highlight_ofs], bx
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

  add [scrn_col], 5

  mov dx, offset clustermsg
  call printstring

  mov [highlight], 03020014h
  add [highlight_ofs], bx
  call bshighlight

  mov ax, word ptr [si+bx+DIR_CLUST_HIGH]
  call printhex
  mov dx, offset valuebuffer+6
  call printstring

  mov [highlight_scsiz], 04
  add [highlight_ofs], 6
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

  add [scrn_col], 5

  mov dx, offset modifiedmsg    ; last modified
  call printstring

  push bx
  add bx, 18h
  call printdate
  xor dx, dx
  sub bx, 02h
  call printtime
  pop bx


  add [scrn_col], 7

  mov dx, offset sizemsg
  call printstring

  mov [highlight], 0A04001Ch
  add [highlight_ofs], bx
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
; IN: AL = attribute bits
;     DH = bit to test for
;     DL = character to print if bit is set in AL
;
testattrib:
  test al, dh
  jnz printchar
    mov dl, '-'
  jmp printchar

dirview endp

;-------------------------------------------------------
fat32viewmode proc
  mov [scrn_xy], 2204h
  mov [highlight], 07040000h

  call readbufferinsi

  mov bx, 144

  loopline2:
  cmp [spot], bx
  jb donesetline2

    add si, 36
    add bx, 36
    add [highlight_ofs], 36

  cmp bx, 432
  jne loopline2

  donesetline2:

  mov cl, 9
  mov ch, 7

  fat32loop:

  call bshighlight
  add [highlight_ofs], 4

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

  mov [scrn_col], 4
  inc [scrn_row]
  mov cl, 9

  dec ch
  jnz fat32loop

  ret
fat32viewmode endp
  
;-------------------------------------------------------
fat16viewmode proc
  mov [scrn_xy], 2203h
  mov [highlight], 04020000h

  call readbufferinsi

  mov bx, 120

  loopline:
  cmp [spot], bx
  jb donesetline

    add si, 30
    add bx, 30
    add [highlight_ofs], 30

  cmp bx, 450
  jne loopline

  donesetline:

  mov cl, 15
  mov ch, 7

  fat16loop:

  call bshighlight
  add [highlight_ofs], 2

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

  mov [scrn_col], 3
  inc [scrn_row]
  mov cl, 15

  dec ch
  jnz fat16loop

  ret
fat16viewmode endp
;-------------------------------------------------------
fat12viewmode proc

  mov [highlight], 03020000h

  xor ax, ax                            ; this little loop figures out
  mov bx, [spot]                        ; where to start displaying
  buf12fix:                             ; fat12 entries, since an entire
  cmp bx, 108                           ; subsector (512 bytes) of 3-nibbles
  jb donebuffix                         ; won't fit in the view area.
    sub bx, 27
    add ax, 27
    add [highlight_ofs], 27
    cmp ax, 300
    jbe buf12fix
  donebuffix:

  movzx dx, [subsector]                 ; displaying fat12 entries, we
  mov si, offset readbuffer             ; need to figure out what subsector
  shl dx, 9                             ; we're looking at. (subsector*512)
  add si, dx

  call fat12pad

  add si, ax

  mov eax, [dwSector]

  mov ebx, [dwFat12start]
  cmp ebx, eax
  ja dodec12
  sub eax, ebx
  jmp donesub12
  dodec12:
    dec eax
  donesub12:

    movzx ebx, [subsector]
    add eax, ebx
    mov cx, [wBps]
    shr cx, 10
    shl eax, cl

  xor edx, edx
  mov ebx, 3
  div ebx

  mov [scrn_xy], 2203h

  cmp dl, 0
  je fat12loop
  dec [highlight_ofs]
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
    inc [highlight_ofs]

  jmp fat12loop
print12bits:
  mov dl, SPACE
  call printchar
  call bshighlight
  inc [highlight_ofs]
  call printhex
  mov dx, offset valuebuffer+6
  call printstring
  cmp [scrn_col], 75
  jne rp12
  mov [scrn_col], 3
  inc [scrn_row]
rp12:
  mov cx, 2903h
  cmp [scrn_xy], cx
  jb rp13
    mov al, SPACE
    mov cl, 4
    pop dx
    jmp printchar2
rp13:
  ret
fat12viewmode endp

;-------------------------------------------------------
hd0common:
  mov al, 20
  mul cl
  inc al
  mov [scrn_col], al
  inc [scrn_row]
  ret
;-------------------------------------------------------
hd0view proc
  mov [scrn_col], 01h
  xor cx, cx

  call readbufferinsi

  nextpart:
  mov [scrn_row], 22h

  mov dx, offset szPartition
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
  mov [highlight_ofs], bx
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
  mov [highlight_ofs], bx
  add [highlight_ofs], 4

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
  mov [highlight_ofs], bx
  add [highlight_ofs], 4
  call bshighlight

  mov eax, dword ptr [si+bx+04h]
  call printcount
  mov dx, offset valuebuffer
  call printstring

  call hd0common

  mov dx, offset psize
  call printstring

  mov word ptr [highlight+2], 0A04h
  mov [highlight_ofs], bx
  add [highlight_ofs], 8
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
hd0view endp
;-------------------------------------------------------
bsview proc
  mov [scrn_xy], 2201h


  call readbufferinsi

  mov bx, offset highlight

  movzx eax, [si].BPB.bytes_sector
  mov dx, CStr('Bytes Per Sector')
  mov dword ptr [bx], 0502000Bh
  call basicbs

  mov al, [si].BPB.sectors_cluster
  mov dx, CStr('Sectors Per Cluster')
  mov dword ptr [bx], 0301000Dh
  call basicbs

  mov ax, [si].BPB.reserved_sectors
  mov dx, CStr('Reserved Sectors')
  mov dword ptr [bx], 0502000Eh
  call basicbs

  mov al, [si].BPB.num_fats
  mov dx, CStr('Number Of Fats')
  mov dword ptr [bx], 03010010h
  call basicbs

  mov ax, [si].BPB.root_entries
  mov dx, CStr('Maximum Root Entries')      ; FAT1x only
  mov dword ptr [bx], 05020011h
  call basicbs

  mov ax, [si].BPB.sectors_fat12
  mov word ptr [bx], 0013h
  test ax, ax
  jnz @F
  mov eax, [si].BPB.sectors_fat16
  mov dword ptr [bx], 0A040020h
@@:
  mov dx, CStr('Sectors In Partition')      ; bootsector & mbr
  call basicbs

  mov al, [si].BPB.media_byte
  mov dx, CStr('Media Descriptor')
  mov dword ptr [bx], 03010015h
  call basicbs

  mov ax, [si].BPB.sectors_fat
  mov dword ptr [bx], 0A020016h
  test ax, ax
  jnz @F
  mov eax, [si].EBPB_FAT32.sectors_fat32
  mov dword ptr [bx], 0A040024h
@@:
  mov dx, CStr('Sectors Per Fat')
  call basicbs

  mov eax, [si].BPB.hidden_sectors
  mov dx, CStr('Partition Start')
  mov dword ptr [bx], 0A04001Ch
  call basicbs

  cmp [si].BPB.sectors_fat,0
  jnz @F

  mov eax, [si].EBPB_FAT32.root_startcl
  mov dx, CStr('Root Start Cluster')        ; FAT32 only
  mov word ptr [bx], 002Ch
  call basicbs

  mov ax, [si].EBPB_FAT32.fs_info_start
  mov dx, CStr('FSInfo Sector Number')      ; FAT32 only
  mov dword ptr [bx], 05020030h
  call basicbs

  mov ax, [si].EBPB_FAT32.bs_copy_start     ; FAT32 only
  mov dx, CStr('Backup B.S. Location')
  mov word ptr [bx], 0032h
  call basicbs
@@:
  mov al, [si].EBPB.phys_drive
  mov dword ptr [bx], 03010024h
  cmp [si].BPB.sectors_fat, 0
  jne @F
  mov al, [si].EBPB_FAT32.phys_drive
  mov word ptr [bx], 0040h
@@:
  mov dx, CStr('Hard Disk Number')

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

;  mov al, byte ptr [si].BPB.media_byte
;  mov dx, offset mdb
;  mov dword ptr [bx], 03010016h

  cmp word ptr [bx], 0015h
  jne npldn2
  mov al, byte ptr [si].BPB.media_byte
  cmp al, 0F0h
  jb npldn2
  mov dx, CStr(' (HD)')
  cmp al, 0F8h
  je @F
  mov dx, CStr(' (FD)')
@@:
  call printstring

  add cl, 5
npldn2:

  cmp [si].BPB.sectors_fat, 0
  je isldn
  cmp word ptr [bx], 0024h
  jne isldn
  mov al, [si].EBPB.phys_drive
  jmp isldn2

isldn:
  cmp word ptr [bx], 0040h
  jne npldn
  mov al, [si].EBPB_FAT32.phys_drive
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
;nextviewline:
  cmp [scrn_col], 55
  ja gotonextline
  mov [scrn_col], 40
  ret
gotonextline::
  mov [scrn_col], 1
  inc [scrn_row]
  ret

bsview endp

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
  sub al, [scrn_col]
  jc @F
  cmp al, cl
  jnc @F
  mov cl, al
@@:

  mov al, DEFAULTCOLOR
  call colorize
  mov cl, [highlight_scsiz]

  movzx bx, [highlight_size]
  mov dx, [highlight_ofs]
  cmp [spot], dx
  jb notonspot
  add dx, bx
  cmp [spot], dx
  jae notonspot
    mov al, HIGHLIGHTCOLOR
    notonspot:
    call colorize
  popa
  ret

;--- main menu pgup, pgdown, ctrl-pgup, ctrl-pgdown keys

nextsect1000:
  mov eax, [dwSector]
  add eax, 100
  jmp donextsect

;--- pagedown
nextsect:
  inc [subsector]
checkcursorbounds:
  movzx dx, [subsector]                 ; subsector * 512
  shl dx, 9
  mov ax, [wBps]                        ; if (subsector*512 <= bps), then
  cmp ax, dx                            ; we've not paged down completely
  jbe dorns
  sub ax, dx
  dec ax
  cmp [spot], ax
  jbe @F
  call movecursor
@@:
  ret
dorns:
  mov eax, [dwSector]
  inc eax
donextsect:
  cmp eax, [dwDataend]
  jbe @F
  sub eax, [dwDataend]
  dec eax
@@:
  mov [dwSector], eax
  call rwsect
  ret
;-------------------------------------------------------
lastsect:
  sub [subsector], 1
  jnc @F
  mov eax, [dwSector]
  dec eax
  jmp dolastsect
@@:
  ret
;-------------------------------------------------------
lastsect1000:
  mov eax, [dwSector]
  sub eax, 100
;-------------------------------------------------------
dolastsect:
  cmp eax, [dwSector]
  jb golastsect
  not eax

  mov ebx, [dwDataend]
  sub ebx, eax
  mov eax, ebx
golastsect:
  mov [dwSector], eax
  call rwsect
  mov dx, [wBps]
  dec dx
  shr dx, 9
  mov [subsector], dl
  jmp checkcursorbounds

;-------------------------------------------------------
setcdvar:
  mov bx, 50h
  cmp [rwfunction], CDCOOKED
  je norawadjust
    add bx, 18h
norawadjust:
  mov eax, dword ptr [readbuffer+bx]
  sub eax, CD_SECTOR_OFFSET+1
  mov [dwDataend], eax
  ret
;-------------------------------------------------------
setvariables proc
  call setseeds2

  cmp [drivetype], CDROM
  je setcdvar
  test [rwfunction], CRW
  jz cdbpsset
    mov [wBps], 512
cdbpsset:
  cmp [drivetype], PHYSICAL
  jne logicalsetvars

    push ds                             ; sets variables p1-p4
    pop es                              ; for jumping to partitions
    mov di, offset partitions           ; on physical drives
    mov si, offset readbuffer + 1c6h
    mov cx, 4
@@:
    movsd
    add si, 0Ch
    loop @B

  cmp [rwfunction], FILEFUNC            ; file read?
  je setffparam
  test [rwfunction], PRW                ; non-physical function?
  jnz donesetphysvars

    mov ah, 08h
    mov dl, [bDrive]
    xor di, di                          ; ES:DI=0000:0000 (bios bug)
    mov es, di
    call int13
    inc dh
    mov [heads], dh
    mov [sectors], cl
    and [sectors], 00111111b
    and cl,3
    xchg cl,ch
    mov [cylinders], cx

    movzx eax, [cylinders]              ; CHS -> LBA
    movzx ebx, dh                       ; heads*cylinders
    mul ebx
    add eax, ebx                        ; + heads
    mov bl, [sectors]
    mul ebx                             ; * sectors
    dec eax                             ; - 1
    sub eax, [dwDrivestart]
    mov [dwDataend], eax

  cmp [rwfunction], NEWINT13
  jne donesetphysvars

    mov si, offset diskinfobuffer
    mov word ptr [si], 1Ah
    mov dl, [bDrive]
    mov ah, 48h                         ; get drive parameters

    call int13                          ; call bios code

    mov eax, dword ptr [si+10h]
    dec eax                             ; remove for HUGE hd support?
    sub eax, [dwDrivestart]
    mov [dwDataend], eax

    mov ax, word ptr [si+18h]
    mov [wBps], ax

;     mov eax, dword ptr [si+14h]
;     mov [dwDataendHigh], eax          ; uncomment for (some) support
;     dec [dwDataend]                   ; for HDs that are HUGE
;     sbb [dwDataendHigh], 0            ; this should never be required
;                                       ; as it goes beyond 2tb
donesetphysvars:
  ret

logicalsetvars:
    xor eax, eax
    mov [dwRootcluster], eax            ; default root cluster = 0
    mov al, [readbuffer].BPB.sectors_cluster   ; sectors per cluster
    mov [bSpc], al

    mov dl, 0FFh
@@:
    inc dl
    shr al, 1
    jnz @B
    mov [spcmd], dl

    mov ax, [readbuffer].BPB.reserved_sectors ; number of reserved sectors
    mov [dwReserved], eax
    mov al, [readbuffer].BPB.num_fats   ; number of fat tables
    mov [bFats], al
    mov ax, word ptr [readbuffer+11h]   ; maximum number of root entries
    mov word ptr [rootentries], ax
    shr ax, 4                           ; 16 entries in one sector
    mov [wRootsectors], ax              ; # of entries/16 = # of sectors

    mov ax, word ptr [readbuffer+16h]   ; sectors per fat
    test ax, ax
    jnz setspf
      mov eax, dword ptr [readbuffer+36]
      mov [dwSpf], eax
setspf:
    mov [dwSpf], eax

    movzx eax, word ptr [readbuffer+13h]        ; sectors in partition
    test ax, ax
    jnz lessthan32mb
      mov eax, dword ptr [readbuffer+20h]
lessthan32mb:
    dec eax
    mov [dwDataend], eax

      sub eax, [dwSpf]
      cmp [bFats], 2
      jb skipsub2
        sub eax, [dwSpf]
skipsub2:
      sub eax, [dwReserved]

      movzx ebx, [wRootsectors]
      sub eax, ebx
      mov cl, [spcmd]
      shr eax, cl

      mov [fattype], FAT32
      cmp eax, 65525
      jae goodnumcluster                ; jump if not fat16 or less
      mov [fattype], FAT16
      cmp eax, 4085
      jae goodnumcluster                ; jump if not fat12
      mov [fattype], FAT12
goodnumcluster:
      add eax, 2
      mov [dwLastcluster], eax

    mov eax, [dwSpf]
    movzx ebx, [bFats]
    mul ebx
    add eax, [dwReserved]               ; spf * fats + reserved = root
    mov [dwRoot], eax

    cmp [fattype], FAT32
    jne not_fat32

    push eax
      mov al, byte ptr [readbuffer+40h] ; hard drive number
      mov [hdnumber], al
      mov ax, word ptr [readbuffer+32h] ; backup boot sector
      mov [backupbs], ax
      mov ax, word ptr [readbuffer+30h] ; file system info sector
      mov [fsinfo], ax
      movzx ax, [bSpc]
      mov [wRootsectors], ax
      mov eax, dword ptr [readbuffer+44]
      mov [dwRootcluster], eax

      sub eax, 2
      jc wrongrootc
      mov cl, [spcmd]
      shl eax, cl
      add [dwRoot], eax
wrongrootc:
    pop eax
    jmp isfat32

not_fat32:

    mov al, byte ptr [readbuffer+24h]   ; hard drive number
    mov [hdnumber], al
    movzx eax, [wRootsectors]
    add eax, [dwRoot]                   ; calculate start of data area

isfat32:

  cmp eax, [dwRoot]
  jne datastartiscorrect
    mov bl, [bSpc]
    add eax, ebx
datastartiscorrect:
    mov [dwDatastart], eax

    mov eax, [dwReserved]
    add eax, [dwSpf]
    mov [dwFatend], eax                 ; calculate end of fat 1 area

    movzx eax, [wBps]                   ; calculate bytes per cluster
    mov bl, [bSpc]
    mul ebx
    mov [dwBpc], eax

    test [rwfunction], LRW
    jnz donegetvars

    ; lock partition
    mov cx, 084Ah
    cmp [fattype], FAT32
    jne fat1xlock
      mov ch, 48h
fat1xlock:

if ?VDD
;--- windows complains if drive is an USB memory stick.
;--- hence don't lock if running on NT!
    cmp [hVdd],-1
    jnz donegetvars
endif
    mov bl, [bDrive]
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
    mov eax, [dwRwfilesize]
    shr eax, 9                          ; \Fix/ ?
    jz donesetff
    dec eax
  donesetff:
    sub eax, [dwDrivestart]
    mov [dwDataend], eax
  ret

setvariables endp

;------------------------------------------------------------
dumpiso proc
  call srcommon
  call createfile
  cmp [status], ERROR
  je srfileoptions
  cmp [drivetype], CDROM
  jne drivedump

  push ds
  pop es
  mov di, offset readbuffer
  mov cx, [wBps]
  mov al, 0
  rep stosb

  mov cx, [wBps]
  mov dx, offset readbuffer
  mov bx, [wFilehandle]
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
  mov edx, [dwDataend]
  inc edx
  mov [dwValue], edx
  call writefile
  cmp [status], ERROR
  pushf
    call closefile
    call updatescreen
  popf
  je srfileoptions

    mov dx, offset donemsg
    call printerror

  jmp srfileoptions
dumpiso endp
;-------------------------------------------------------

;*******************************************************
; CALLS
;*******************************************************
include FATFS.INC
;-------------------------------------------------------

printchs proc
  call printstring
  mov dl, SPACE
  call printchar
  movzx eax, byte ptr [si+bx+3]
  mov ah, byte ptr [si+bx+2]
  shr ah, 6

  mov word ptr [highlight+2], 0402h
  mov [highlight_ofs], bx
  add [highlight_ofs], 2

  call bshighlight

  call printcount
  mov dx, offset valuebuffer+6
  call printstring

  mov dl, '/'
  call printchar

  mov word ptr [highlight+2], 0301h
  dec [highlight_ofs]

  call bshighlight

  movzx eax, byte ptr [si+bx+1]
  call printcount
  mov dx, offset valuebuffer+7
  call printstring
  mov dl, '/'
  call printchar

  mov [highlight_scsiz], 02h
  inc [highlight_ofs]
  call bshighlight

  movzx eax, byte ptr [si+bx+2]
  and al, 111111b
  call printcount
  mov dx, offset valuebuffer+8
  jmp printstring
printchs endp

;-------------------------------------------------------
finddirectory proc                  ;IN: SI=readbuffer
  push cx                       ;    BX=offset in readbuffer

                                ; not found: carry set
                                ; found    : carry cleared
  cmp byte ptr [si+bx], 0
  je notfound

  flok:
;  mov ch, byte ptr [wBps+1]             ; 16 entries every 512 bytes
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
;  mov [subsector], al

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
finddirectory endp

;--- common routine for find cmds

findcommon proc
  pop [wCalladdress]
  mov dx, offset searchingmsg
  call printbottom

  call checkabort
  je abortfindstring

  call printcounts
  mov si, offset readbuffer
  mov ax, [wBps]
  dec ax
  shr ax, 9
  cmp [subsector], al
  jb dontrw
    mov eax, [dwDataend]
    cmp [dwSector], eax
    je stringnotfound
    inc [dwSector]
    call rwsect
    cmp [status], ERROR
    je abortfindstring

  jmp dontinc
dontrw:

  inc [subsector]
  mov al, [subsector]
  shl ax, 9
  add si, ax

dontinc:
  push [wCalladdress]
  ret
findcommon endp

;-------------------------------------------------------
spaceandcolon:                  ; i don't like this function, it was created
  mov dl, ':'                   ; for optimal code size instead of clean,
  call printchar                ; reusable code
  mov dl, SPACE
  mov cl, 63                    ; it places the cursor in the right position
  cmp [scrn_col], 47            ; to display the next string when showing
  ja loopwipeview               ; the bootsector view
  mov cl, 23
  loopwipeview:
  call printchar
  cmp [scrn_col], cl
  jb loopwipeview
  ret
;-------------------------------------------------------
readfile proc                   ; IN: eax start sector
  mov dx, offset readingmsg     ;     d:[dwValue] # of sectors to write
  call printbottom              ; OUT: sectors written to disk from file

  mov edx, eax
  add edx, [dwValue]
  jc invalidperror
  dec edx
  cmp edx, [dwDataend]
  ja invalidperror

  push eax
  call getfilesize
    mov eax, [dwValue]
    movzx edx, [wBps]
    mul edx
    cmp [dwFilesize], eax
  pop eax

  mov dx, offset toosmall
  jb printerror

  mov [handling], QUERY_SKIP
  push [dwSector]
  mov [dwSector], eax
  call openfile

  readfileloop:

  mov ah, 3Fh                           ; read 512 bytes of the file
  mov bx, [wFilehandle]                 ; directly into the write buffer
  mov cx, [wBps]                        ; bad idea?
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

  mov [bRW], WRITE
  call rwsect

  cmp [status], ERROR
  je donefileread

  inc [dwSector]
  call printcounts

  dec [dwValue]
  jnz readfileloop

  donefileread:
  call closefile
  mov [handling], ABORT_OPERATION
  pop [dwSector]
  push word ptr [status]
  call rwsect
  pop word ptr [status]
  call updatescreen

  mov dx, offset donermsg
  cmp [status], ERROR
  jne printerror
  ret
readfile endp

;-------------------------------------------------------
printentry:                             ; prints the fat entry the cursor
  cmp [bRegion], FAT_AREA               ; is currently in, in the top
  jne abortentry                        ; right of the screen

    call getentrynumber
    call printhex

    mov [scrn_col], 34h
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
inputvalue proc                 ; IN:
  mov [dwMaxvalue], eax         ;      EAX: maximum allowed value
  call printbottom              ; OUT:
  mov dl, [scrn_col]            ;      ECX / [dwValue]: returned value
  mov [maxleft], dl
  call clearbottom
  xor ecx, ecx
  getkeyagain7:
  mov [dwValue], ecx
  call cursorgetkey

  cmp al, ESCAPE_KEY
  sete [status]                 ; set an error if you hit escape
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

  cmp ebx, [dwMaxvalue]
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
  mov al, [maxleft]
  cmp [scrn_col], al
  je getkeyagain7

  call backcommon

  xor edx, edx
  mov eax, ecx
  mov ecx, 10
  div ecx
  mov ecx, eax

  jmp getkeyagain7
inputvalue endp
;------------------------------------------------------
printcounts proc
  pushad
  mov [scrn_xy], 0021          ; print the current sector
  mov [bRegion], UNDEFINED
  mov eax, [dwSector]          ; the string "Sector:"
  call printcount              ; isn't printed for efficiency
  mov dx, offset valuebuffer
  call printstring

  inc [scrn_col]               ; prints subsector in this manner: [1]
  mov dl, '['
  call printchar
  mov dl, [subsector]
  add dl, '1'
  call printchar
  mov dl, ']'
  call printchar

  mov [scrn_col], 36

  mov eax, [dwSector]

  cmp [drivetype], PHYSICAL
  je inphysical
  cmp [drivetype], CDROM
  je indata

  mov edx, [dwReserved]
  cmp eax, edx
  jb inreserved

  movzx cx, [bFats]
  jcxz notinfat
  anotherfat:
    add edx, [dwSpf]
  loop anotherfat
  cmp eax, edx
  jb infat

  notinfat:
  mov edx, [dwRoot]
  cmp eax, edx
  jb indata
  movzx ebx, [wRootsectors]
  add edx, ebx
  cmp eax, edx
  jae indata

  mov [bRegion], ROOT_AREA
  mov dx, offset inrootmsg

  cmp [fattype], FAT32
  je dispclust

  continuecount:
  call printstring
  abortdc:

  mov cl, 61                            ; clear to column 61
  cmp [drivetype], PHYSICAL
  je noclearchs
    mov cl, 79                          ; clear to column 79
  noclearchs:
  sub cl, [scrn_col]
  mov al, SPACE
  call printchar2

  cmp [drivetype], PHYSICAL
  jne doneprintcounts
    call getchs
    movzx eax, ch                        ; the following block of code
    mov ah, cl                           ; prints "CHS: xx/xxx/xxxx" in the
    shr ah, 6                            ; top right corner for ah=02h/int13h

    push dx
    mov [scrn_xy], 003Fh
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
    mov [bRegion], RESERVED_AREA
    mov dx, offset inreservedmsg
    jmp continuecount

  infat:
    mov [bRegion], FAT_AREA
    push [scrn_xy]
    call printentry
    pop [scrn_xy]
    mov dx, offset infatmsg 
    call printstring
    mov dl, '1'
    mov eax, [dwFatend]
    cmp [dwSector], eax
    jb firstfat
    mov dl, '2'
    firstfat:
    call printchar
    mov dl, ']'
    call printchar
    mov al, SPACE
    mov cl, 2
    call printchar2

    cmp [fattype], UNDEFINED
    je abortdc

    mov [scrn_col], 2Dh
    mov dx, offset entrymsg
    call printstring
    mov [scrn_col], 3Ch
  jmp abortdc

  setmbrview:
    mov [bRegion], MBRVIEW
    mov dx, offset inmbrmsg
    call printstring
  jmp abortdc

  inphysical:
   cmp [bDrive], 80h                           ; lower than 80h?
   jb indata                                   ; not an hd - no mbr.
    test eax, eax
    jz setmbrview

  indata:
    mov dx, offset indatamsg
    dispclust:

    call printstring
    mov dl, SPACE
    call printchar

    cmp [drivetype], FAT
    jne abortdc

      or [bRegion], DATA_AREA

      mov dx, offset clustermsg         ; display cluster number
      call printstring

      mov eax, [dwSector]
      call sector2cluster

      mov dx, offset valuebuffer+1
      call printhex
    jmp continuecount
;-------------------------------------------------------
printcounts endp
printhex proc                           ; takes whats in eax
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
printhex endp
;-------------------------------------------------------
cursorgetkey:
  pusha
  mov ah, 01h
  mov cx, 0808h
  int 10h
  popa
  call getkey
cursoroff:
  pusha
  mov ah, 01h
  mov cx, 2000h
  int 10h
  popa
  ret

;--- print string: ds:dx -> string
printstring proc
  pusha
  mov si, dx
  call cbuffer_offset    ;setup ES:DI to current screen pos
printstrloop:
  lodsb
  cmp al, 0
  je abortprintstr
  inc [scrn_col]
  stosb
  inc di
  jmp printstrloop

abortprintstr:
  call setxy
  popa
  ret
printstring endp

;-------------------------------------------------------
printsector proc                ; this routine prints out all the
                                ; bytes in the read buffer
  call readbufferinsi

  mov dx, [wBps]
  sub dx, ax
  mov [rembytes], dx

  cmp [spot], dx
  jb notsignificant

    dec dx
    mov ax, dx
    mov dl, [bHL]

  notsignificant:

  xor eax, eax
  xor cx, cx

  displaynextchar:
    lodsb

    mov dx, cx
    call aspotcalc
    mov [scrn_xy], dx
    mov dl, al
    cmp cx, [rembytes]
    jb nntps
      mov dl, SPACE
    nntps:
    call printchar

    mov dx, cx
    call spotcalc
    mov [scrn_xy], dx

    cmp [displaymode], DM_BINARY
    je displaybinval
      cmp cx, [rembytes]
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
      mov dx, [spot]
      and dl, 10000000b
      add dx, 128
      cmp cx, dx
      jae donextdispbyte
      mov dx, [spot]
      and dl, 10000000b
      cmp cx, dx
      jb donextdispbyte

      cmp cx, [rembytes]
      jb pscontinue2
        mov al, '-'
        push cx
          mov cl, 4
          call printchar2
          add [scrn_col], 5
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
;printaddresses:
  mov [scrn_col], 1
  mov [scrn_row], 00h
  mov dx, offset offsetmsg
  call printstring
  mov [scrn_col], 13
  mov dx, offset sectormsg
  call printstring
  movzx eax, [subsector]
  shl ax, 9

  mov bx, 10h                           ; 16 bytes per line (hex)
  mov cx, 32                            ; 32 vertical lines for editing
  cmp [displaymode], DM_BINARY
  jne nextaddress

  mov dx, [spot]
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
printsector endp

;---------------------------------------------------------------
printoffset proc
  mov [scrn_xy], 0009
  call spotinbx
  movzx eax, bx

  call printhex
  mov dx, offset valuebuffer+6
  call printstring

  call printentry

  mov ax, [crsr_xy]
  mov [scrn_xy], ax
  jmp colorchar
printoffset endp

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

  cmp [editmode], EM_DEFAULT
  je ecolor1
    xchg al, ah
  ecolor1:
  mov byte ptr es:[di+1], al

  push [scrn_xy]
  mov dx, [spot]
  call aspotcalc
  mov [scrn_xy], dx

  call cbuffer_offset
  mov byte ptr es:[di+1], ah
  pop [scrn_xy]
  popa
  ret
;-------------------------------------------------------
printchar2:
  pusha
  call cbuffer_offset
@@:
  stosb
  inc di
  dec cl
  jnz @B
  popa
  ret
;-------------------------------------------------------
printchar:
  pusha
  call cbuffer_offset
  mov byte ptr es:[di], dl
  inc [scrn_col]
  popa
  ret

;--- clear sector area (lines 1-32, colums 9-61)
clearsecarea proc
    mov es,[vidseg]
    mov bx,[vidcolsize]
    mov di,bx
    add di,2*9
    mov ax, DEFAULTCOLOR*100h+SPACE
    mov dl, 32
@@:
    mov cx, 52
    push di
    rep stosw
    pop di
    add di,bx
    dec dl
    jnz @B
    ret
clearsecarea endp
;-------------------------------------------------------
; init: - check/set video mode
;       - set default byte to edit
;       - print copyright info
;       - seed random timer
;       - wipe variables
;       - set some defaults
;       - replace int24h

init proc

;--- cs=ds=es=ss (tiny model)
;--- clear uninitialized vars
  cld
  mov di, offset startbss
  mov cx, sp
  sub cx, di
  shr cx,1
  xor ax,ax
  rep stosw

;--- check if video mode suits, else set 43x80 mode.
  mov di, 0B800h
  push ds
  push 0
  pop ds
  mov ax,ds:[44Ah] ;cols
  add ax,ax
  mov bx,ds:[44Eh] ;start offset video page
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
  mov ax, 80*2
  mov ch, 43
  xor bx, bx
  mov dl,0
clrscn:
  mov [vidcolsize],ax
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
  add di,[vidcolsize]
  dec ch
  jnz @B

  call cursoroff

  mov [scrn_xy], 1423h                  ; print out copyright info
  mov dx, offset introtext
  call printstring
  mov [scrn_xy], 161Ah                  ; print out copyright info
  mov dx, offset copyright
  call printstring

    mov ax, 3524h                       ; back up old int 24h
    int 21h
    mov word ptr [old24h+0], bx
    mov word ptr [old24h+2], es

    mov ah, 25h                         ; set up new int 24h
    mov dx, offset int24h               ; (al preserved from previous call)
    int 21h

  call setseeds1

  xor dx, dx                            ; y = (spot-1)/16
  call spotcalc
  mov [crsr_xy], dx
if ?VDD
  call initvdd                          ; init vdd on nt platforms
endif
  ret
init endp

;-------------------------------------------------------
setxy:                          ; set the current x/y coordinate
  pusha                         ; of the cursor this is mainly for
  mov bh, [vidpg]               ; the cursor when receiving input
  mov dx, [scrn_xy]             ; since we use direct text output
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
  movzx eax, [heads]
  movzx ebx, [sectors]
  mul ebx

  mov ebx, eax
  mov eax, [dwSector]
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
  movzx ebx, [sectors]
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
;       IN:     [dwSector]    = the sector number to read
;               [handling]    = what to do when sector read/write fails
;               [drive]       = drive number to use
;               [rwfunction]  = type of read/write function
;               [bRW]         = 1 for write, all other values read
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
rwsect proc

local dwRealSector:dword
local wOldfunction:word        ; when changing drives to edit, we need to keep
local bOlddrive:byte           ; track of these variables in case the drive can't
local wOldbps:word             ; be accessed (has to default to previous drive)
local drivepacket:DISKIO       ; used by int 25h/26h and int 21h/ax=7305h
local diskrwbuffer:DAP         ; used by int 13h ah=42h/43h (extended read/write)


    pushad
    mov eax,[dwSector]
    add eax, [dwDrivestart]
    mov [dwRealSector], eax
    push ds
    pop es
    mov ax, word ptr [rwfunction]
    mov [wOldfunction], ax
    mov ax, [wBps]
    mov [wOldbps], ax
    mov dl, [bDrive]
    mov [bOlddrive], dl
    mov [status], SUCCESS

    mov [subsector], 0

    test [rwfunction], CRW
    jz cdromread
    cmp [rwfunction], OLDINT13
    je useoldint13

    mov eax, [dwRealSector]

    cmp [rwfunction], FILEFUNC
    je fileread
    cmp [rwfunction], NEWINT13
    je hdread

; the following are used for both int21h and 25h/26h
    mov cx, 0FFFFh
    lea bx, drivepacket
    mov [bx.DISKIO.startsec], eax         ; set sector #
    mov [bx.DISKIO.sectors], 1            ; read in 1 sector at a time
    mov [bx.DISKIO.buffofs], offset readbuffer
    mov [bx.DISKIO.buffseg], ds
    xor si, si                            ; 0 (read)
    cmp [bRW], WRITE
    jne reading                           ; default to reading for safety
    mov [bx.DISKIO.buffofs], offset writebuffer
    inc si                                ; 1 (write)
reading:

    cmp [rwfunction], NEWINT21
    je newread

;--- access drive via int 25h/26h

    mov al, [bDrive]
    cmp [bRW], WRITE
    je @F
    call int25
    jc newreadadjust
    jmp nosectorerror
@@:
    call int26
    jc sectorerror
    jmp nosectorerror

;--------------

newreadadjust:
    mov [rwfunction], NEWINT21

newread:
    mov dl, [bDrive]
    inc dl
    mov ax, 7305h                       ; extended sector read/write
    call int21
    jc trycdrom
    jmp nosectorerror

;-------------

fileread:
    mov edx, [dwDataend]
    add edx, [dwDrivestart]
    cmp eax, edx
    ja sectorerror

    shl eax, 9                        ; \Fix/

    mov edx, [dwRwfilesize]
    sub edx, 512
    cmp eax, edx
    ja sectorerror

    mov bx, [rwhandle]
    mov dx, ax
    shr eax, 16
    mov cx, ax
    mov ax, 4200h                     ; seek from start of file
    int 21h

    mov ah, 3Fh                       ; read from file
    mov dx, offset readbuffer
    cmp [bRW], WRITE
    jne dofread
    mov dx, offset writebuffer
    inc ah
dofread:
    mov bx, [rwhandle]
    mov cx, 512
    int 21h
    jc sectorerror
    jmp nosectorerror
   ;-------------
trycdrom:                             ; check a drive for mscdex
    mov ax, 150Bh
    movzx cx, [bDrive]
    int 2Fh
    cmp bx, 0ADADh                    ; 0ADADh returned if mscdex called
    jne sectorerror
    test ax, ax                       ; ax=0 if not read successfully
    jz sectorerror

    mov [rwfunction], CDCOOKED
    mov [drivetype], CDROM

    mov [wBps], 2048
    mov byte ptr [cdheader], 13       ; size of header
    mov word ptr [cdheader+14], offset readbuffer
    mov word ptr [cdheader+16], ds
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
    mov [wBps], 2352                  ; 2352 bytes per sector
    mov [rwfunction], CDRAW

cdromread:
    mov bx, offset cdheader
    mov eax, [dwRealSector]
    add eax, CD_SECTOR_OFFSET         ; can't read first 10h sectors

    mov byte ptr [bx+2], 128          ; read long
    cmp [bRW], WRITE
    jne docdread
    mov byte ptr [bx+2], 134          ; write long
docdread:
    clc                               ; fixes bug in Win9x
    mov dword ptr [bx+20], eax
    push ds
    pop es
    movzx cx, [bDrive]
    mov ax, 1510h                     ; cd-rom send device driver request
    call int2F
    jc sectorerror                    ; device driver has not been called
    test byte ptr [bx+4], 10000000b   ; check status word for error
    jz nosectorerror

;-------------

sectorerror:
    mov dx, offset sectorrerror
    cmp [bRW], WRITE
    jne werror
    mov dx, offset sectorwerror
werror:

    cmp [handling], IGNORE_ERRORS
    je nosectorerror
    cmp [handling], ABORT_OPERATION
    je sectorerror2
    mov bx, word ptr [lastbottomtext]
    call printbottom

    mov dx, offset sectorrerror3
    cmp [handling], QUERY_SKIP
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
    cmp [handling], QUERY_SKIP
    je checkskip
    cmp ah, SCAN_Z
    jne gak
itsZ:
    push ds
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
    mov [handling], IGNORE_ERRORS
    jmp itsS
sectorerror2:
ifdef _DEBUG
    push eax
    mov eax, [dwRealSector]
    call printcount
    mov dx, offset valuebuffer
    pop eax
endif
    call nuprinterror
secterrhandle:
    mov [status], ERROR
    mov ax, [wOldfunction]
    mov word ptr [rwfunction], ax
    mov al, [bOlddrive]
    mov [bDrive], al
    mov ax, [wOldbps]
    mov [wBps], ax
    jmp nosectorerror

;-------------

hdread:
    lea si, diskrwbuffer
    mov word ptr [si].DAP.bSize, sizeof DAP ; size of struct (also clear reserved next byte)
    mov [si].DAP.wNumSec, 1             ; one sector to transfer
    mov [si].DAP.wBufferSeg, ds         ; segment part of transfer address
    mov [si].DAP.dwStartLow, eax        ; set sector #
    mov [si].DAP.dwStartHigh, 0

;    mov eax, [dwSectorHigh]             ; \/\/\/\ 64-bit lba support
;    mov [si].DAP.dwStartHigh, eax

    mov dl, [bDrive]

    cmp [bRW], WRITE
    je int13write

    mov [si].DAP.wBufferOfs, offset readbuffer
    mov ah, 42h
    jmp exint13

int13write:

    mov [si].DAP.wBufferOfs, offset writebuffer
    mov ax, 4300h + NEWINT13_WRITE_FLAG

exint13:

    stc                         ; bug circumvention
    call int13
    sti                         ; interrupt flag sometimes disabled
    jnc nosectorerror           ; try older int13h functions (ah=02h)

    mov [rwfunction], OLDINT13

useoldint13:
    call getchs
    mov dl, [bDrive]
    mov ax, 0201h
    cmp [bRW], WRITE
    jne old13hread
    inc ah
old13hread:
    mov bx, offset readbuffer
    call int13

    jc sectorerror

  ;---------------

nosectorerror:

    mov [bRW], READ
    popad
    ret
rwsect endp

;--- display error msg at menu line, then wait for a key press
printerror proc
  push dx
  call updatescreen
  pop dx
nuprinterror::
  call printbottom
  mov dx, offset errormsg
  call printstring
  call getkey
  mov [status], ERROR
  ret
printerror endp
;-------------------------------------------------------
validpathchar proc
  cmp al, BACK_SLASH
  je validchar
  cmp al, COLON
  je validchar
  cmp al, PERIOD
  je validchar
validfileinputchar::
  cmp al, 'a'                   ; lower case letters allowed in paths
  jb validfilechar
  cmp al, 'z'
  ja validfilechar
  jmp validchar
extvalidfilechar::
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
validpathchar endp
;-------------------------------------------------------
getfilename proc                ; IN:  nothing
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
getfilename endp

;-------------------------------------------------------
cbuffer_offset:                 ; take what's in [scrn_xy] and set es:di to address
  push ax                       ; of the respective byte in the screen buffer
  push dx
  mov es,[vidseg]
  movzx ax, [scrn_row]
  mul [vidcolsize]
  movzx dx, [scrn_col]
  add dx, dx
  add ax, dx
  mov di, ax
  pop dx
  pop ax
  ret
;-------------------------------------------------------
printdate:
  mov ax, word ptr [si+bx]
  mov [highlight_ofs], bx
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
  inc [scrn_col]
  ret
;-------------------------------------------------------
printtime:
  mov ax, word ptr [si+bx]
  mov [highlight_ofs], bx
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
  dec [highlight_ofs]
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
  mov ax, [spot]
  and ax, 11111b
  cmp ax, 15h
  pop ax
  je nodec
  dec [highlight_ofs]
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
  push ax                       ; OUT: dx = [scrn_xy]
  mov ax, dx

  cmp [displaymode], DM_BINARY
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
  ret
;-------------------------------------------------------
quit proc
  mov dx, offset quitmsg
  call printbottom
  call getyn
  jnc doret

if ?VDD
;--- exit vdd on nt platforms
  call exitvdd
endif

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
doneset:
else
  mov ah, 01h         ;set cursor shape
  mov cx, 0808h
  int 10h
  mov cx,[vidcolsize] ;clear bottom line on screen (just 80 rows)
  mov al,[vidrows]
  dec al
  mov bl,al
  mov ah,0
  mul cx
  mov di,ax
  mov es,[vidseg]
  mov ax,07*100h+SPACE;07=white on black
  mov cx,80
  rep stosw
  mov ah,2            ;set cursor pos to bottom line
  mov dh,bl
  mov bh,[vidpg]
  mov dl,0
  int 10h
endif

  mov ax, 2524h
  lds dx, [old24h]
  int 21h
  mov ax, 4c00h
  int 21h
doret:
  ret
quit endp

;-------------------------------------------------------
savedata proc
;
; IN:   dd:[dwValue]    number of sectors to save
;       eax             starting sector
;
; OUT:  disk is read and sectors are dumped to [wFilehandle]
;       dw:[wFilehandle] handle of file to write to
;

  mov edx, eax
  add edx, [dwValue]
  jc invalidperror
  dec edx
  cmp edx, [dwDataend]
  ja invalidperror

  mov edx, [dwValue]            ; the plan here is to convert
  mov cx, [wBps]                ; "value" into the number of 512-byte
  shr cx, 10                    ; pieces it contains by shifting it left
  shl edx, cl                   ; if BPS is > 512

  cmp edx, 400000h
  ja toobig

  push ax
  call createfile
  pop ax
  cmp [status], ERROR
  jne dosavedata
donesavedata:
    ret
dosavedata:
  call writefile
  call closefile

  call updatescreen

  cmp [status], ERROR
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
invalidperror::
  mov dx, offset invalidpmsg
  jmp printerror
savedata endp

;-------------------------------------------------------
printfilemenu:
  mov [chainflag], NO_CHAIN

  cmp [drivetype], PHYSICAL
  jne logicalrfo
  mov dx, offset pdfilemenu
  jmp printmenu
logicalrfo:

  mov dx, offset ldfilemenu
  mov eax, [dwReserved]
  cmp [dwSector], eax
  jb printmenu

  mov eax, [dwSpf]
  movzx ebx, [bFats]
  mul ebx
  mov dx, offset ldfilemenu
  add eax, [dwReserved]
  cmp [dwSector], eax
  jb dochain

checkdir:
  mov si, offset readbuffer
  xor bx, bx
  call finddirectory
  jc printmenu                  ; dir not found

  mov [chainflag], FILE_CHAIN
  jmp dochain2

dochain:
  mov [chainflag], FAT_CHAIN

dochain2:
  mov dx, offset chainmenu

;--- print menu at bottom line.
;--- dx=menu
printmenu:
  mov [scrn_xy], 2a01h
  mov si, dx
; mov ah, byte ptr [si]         ; number of items in the menu
; inc si
  movzx cx, byte ptr [si]       ; number of spaces between each item

  nextmenuitem:
    inc si
    mov bl, byte ptr [si]
    cmp bl,-1
    jz printmenu_done
    mov di, offset menustrings

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
  add [scrn_col], cl
  inc ch
  jmp nextmenuitem
printmenu_done:
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

  push ds
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
  dec [scrn_col]
  mov dl, SPACE
  call printchar
  dec [scrn_col]
  jmp setxy
;-------------------------------------------------------
movecursor:             ; IN:   ax = new [spot]
                        ;       dl = new [bHL]
  push [crsr_xy]
  pop [scrn_xy]
  call decolorchar
  mov [spot], ax
  mov [bHL], dl
  mov dx, ax
  call spotcalc
  add dl, [bHL]
  mov [crsr_xy], dx
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
  cmp [viewmode], dl              ; check if the "view" mode
  je abortviewmode0               ; is already set.

  mov [viewmode], dl              ; set new view
  mov es,[vidseg]
  mov cx,[vidcolsize]
  mov ax,34                       ; the "view" area starts at line 34
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
    mov eax, [dwDataend]                ; then abort.
    sub eax, [dwSector]
    inc eax
    mov dx, offset sectorsmsg
    call inputvalue
    test ecx, ecx
    jnz goodval
      mov [status], ERROR
    goodval:
    cmp [status], ERROR
  popad
  ret
;-----------------------------------------------------
displaybinary:                          ; AL = bits to display
  mov dh, 8
printbitsloop:
    cmp dh, 4                           ; 4th bit?  put a space.
    jne dontaddspace
    inc [scrn_col]
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
  mov [dwFilesize], eax
  ret
;-------------------------------------------------------
printbottom:
  mov [scrn_xy], 2a01h
  mov word ptr [lastbottomtext], dx
  call printstring
  call setxy
      ;-------------------------------------------------------
clearbottom:
  pusha
    mov cl, 80
    sub cl, [scrn_col]
    mov al, SPACE
    call printchar2
  popa
  ret
;-------------------------------------------------------
findfile:                       ; IN: filename = pointer to filename
  pusha                         ; OUT: carry flag set if no file found
  mov [status], SUCCESS
  mov dx, offset filename
  mov cx, 47h
  mov ax, 4e00h                 ; findfirst
  int 21h
  popa
  ret
;-------------------------------------------------------
copybuffer:
  pusha
    mov si, offset readbuffer
    mov di, offset writebuffer
    push ds
    pop es

    mov cx, 2352
    rep movsb
  popa
  ret
;-------------------------------------------------------
closefile:
  mov ah, 3eh
  mov bx, [wFilehandle]
  int 21h
  ret
;-------------------------------------------------------
writefile:                      ; in: dword [dwValue] = number of sectors
  push [dwSector]               ;                       to save
  mov [dwSector], eax           ;     eax             = start sector
   mov dx, offset writingmsg 
   call printbottom          
   writefileloop:

  call checkabort
  jne keepwritingfile

     mov dx, offset abortfmsg
     jmp printwferror

  keepwritingfile:

   call printcounts
   mov [handling], QUERY_FILL
   call rwsect
   mov [handling], ABORT_OPERATION
   cmp [status], ERROR
   je errorwritefile

   mov cx, [wBps]                       ; bytes to write
   mov [status], SUCCESS
   mov bx, [wFilehandle]
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

   inc [dwSector]
   dec [dwValue]
   jnz writefileloop
   errorwritefile:
   pop [dwSector]

   push word ptr [status]
   call rwsect
   pop word ptr [status]
   ret
;-------------------------------------------------------
openfile proc
  mov dx, 1
screatefile::
if ?LFN
  mov ax,716Ch
  call tryLFN
  pushf
  cmp ax,7100h
  jz @F
  popf
  ret
@@:
  popf
endif
  mov ax, 6c00h
tryLFN:
  mov bx, 3002h
  mov si, offset filename
  xor cx, cx
  int 21h
  mov [wFilehandle], ax
  ret
openfile endp
;-------------------------------------------------------
createfile:
  mov [status], SUCCESS
  call findfile
  jnc fileexists

  ccreatefile:
    mov dx, 10010b
    call screatefile

  mov dx, offset fileerror
  jc printerror
  mov [wFilehandle], ax
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

  mov word ptr [bx+0], dx   ;set seed1+seed3 or seed2+seed4  
  mov word ptr [bx+4], cx
  ret
;-----------------------------------------------------------------
backhex:
  mov dl, [scrn_col]                    ; can't backspace any further then the
  cmp [maxleft], dl                     ; x-coord after string printed
  je getkeyagain10

  call backcommon

  cmp [commandflag], GET_STRING
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
  mov [commandflag], GET_STRING
  jmp dogethex
gethex:
  mov [commandflag], GET_VALUE
  dogethex:
  mov [dwMaxvalue], eax                 ; back up max value
  call printbottom
  mov dl, [scrn_col]                    ; x-coordinate preserved so that
  mov [maxleft], dl                     ; backspace does not go too far
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

  cmp [scrn_col], 79
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
  cmp [commandflag], GET_STRING
  je stringhex

  cmp al, 0
  jne notestnec
  mov dh, [scrn_col]                    ; get x-coord on screen
  cmp [maxleft], dh                     ; characters already been typed?
  je getkeyagain10                      ; yes, skip this
  notestnec:                            ; abort if we type a 0 (first)

  test ebx, 0F0000000h                  ; cannot exceed FFFFFFFFh
  jnz getkeyagain10

  shl ebx, 4
  or bl, al

  cmp ebx, [dwMaxvalue]                 ; value smaller or equal to maximum?
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
  cmp [commandflag], GET_STRING
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
  mov bl, [subsector]                   ; byte [spot] should actually be
  shl bx, 9                             ; pointing to within the buffer.
  add bx, [spot]
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
  movzx ebx, [seed1]
  mul ebx
  mov bx, [seed2]
  add eax, ebx
  mov [seed12], eax

  mov ecx, eax

  mov eax, 30714
  mov bx, [seed3]
  mul ebx
  mov bx, [seed4]
  add eax, ebx
  mov [seed34], eax

  shl ecx, 16
  and eax, 0FFFFh
  add eax, ecx
  ret
;-----------------------------------------------------------------

;--- code to access WDEVDD on NT platforms.

if ?VDD
    include wdent.inc
endif

;-------------------------------------------------------
ifdef _DEBUG

debugviewmode:
  push edx

  mov [scrn_xy], 2201h
  mov dx, CStr("'EAX: ')
  call printstring
  call printregister

  mov [scrn_xy], 2301h
  mov dx, CStr('EBX: ')
  call printstring
  mov eax, ebx
  call printregister

  mov [scrn_xy], 2401h
  mov dx, CStr('ECX: ')
  call printstring
  mov eax, ecx
  call printregister

  mov [scrn_xy], 2501h
  mov dx, CStr('EDX: ')
  call printstring
  pop eax
  call printregister

  mov [scrn_xy], 2601h
  mov dx, CStr('SI:  ')
  call printstring
  movzx eax, si
  call printregister

  mov [scrn_xy], 2701h
  mov dx, CStr('DI:  ')
  call printstring
  movzx eax, di
  call printregister

  mov [scrn_xy], 2801h
  mov dx, CStr('SP:  ')
  call printstring
  movzx eax, sp
  call printregister

  mov [scrn_xy], 2222h
  mov dx, CStr('Stored EAX: ')
  call printstring
  mov eax, [storedeax]
  call printregister

  mov [scrn_xy], 2322h
  mov dx, CStr('Stored EBX: ')
  call printstring
  mov eax, [storedebx]
  call printregister

  mov [scrn_xy], 2422h
  mov dx, CStr('Stored ECX: ')
  call printstring
  mov eax, [storedecx]
  call printregister

  mov [scrn_xy], 2522h
  mov dx, CStr('Stored EDX: ')
  call printstring
  mov eax, [storededx]
  call printregister

  mov [scrn_xy], 2622h
  mov dx, CStr('Stored SI:  ')
  call printstring
  movzx eax, [storedsi]
  call printregister

  mov [scrn_xy], 2722h
  mov dx, CStr('Stored DI:  ')
  call printstring
  movzx eax, [storeddi]
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
  mov [storedeax], eax
  mov [storedebx], ebx
  mov [storedecx], ecx
  mov [storededx], edx
  mov [storedsi], si
  mov [storeddi], di
  ret

endif
;-------------------------------------------------------
;-------------------------------------------------------

;-------------------------------------------------------
int24h:         ; this is the new int 24h to catch any critical errors
  mov al, 3     ; abort operation code
  iret          ; int 24h would otherwise crash WDe with Abort/Retry/Fail
;-----------------------------------------------------------------

END Start
