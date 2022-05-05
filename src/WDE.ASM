;-------------------------------------------------------
;
; WDe Copyright(C)2005 Ben Cadieux, japheth
;
;-------------------------------------------------------

; the binary was originally created with tasm32 5.3 and tlink 7.1.32.2,
; now it's done using jwasm; alternately, Masm + MS link may be used.


    .model small        ; provides a full 64kB DGROUP just for data
    option casemap:none ; symbols are case sensitive
    .dosseg             ; segment order: _TEXT, _DATA, CONST, _BSS, STACK
    .stack 4096
    .386

;--- _TEXT2 is an extra "code" segment for menu vectors, so they're always aligned
;--- _DATA2 is an extra "data" segment for menus
;--- _BSS is for "uninitialized" data; we need it dword-aligned,
;--- hence simplified segment directive .data? cannot be used.

_TEXT2 segment word public 'CODE'
startmenucmds label word
_TEXT2 ends
_DATA2 segment word public 'DATA'
startmenudefs label byte
_DATA2 ends
_BSS segment dword public 'BSS'
startbss label byte
_BSS ends

CGROUP group _TEXT, _TEXT2
DGROUP group _DATA2, _BSS

ifndef ?DEBUG
?DEBUG           EQU 0  ; 1=debug features on
endif
ifndef ?EXT
?EXT             EQU 1  ; 1=enable "undelete" & "unformat" functions
endif
ifndef ?PM
?PM              EQU 0  ; 1=running as DPMI client
endif
ifndef ?VDD
?VDD             EQU 1  ; 1=winXP VDD supported
endif
ifndef ?LFN
?LFN             EQU 1  ; 1=prefer using LFN functions
endif
ifndef ?SN64
?SN64            EQU 0  ; 1=support 64-bit sector access (not implemented yet)
endif
?SAFEMODE        EQU 1  ; 1=support cmdline option -s
?MOUNT           EQU 1  ; 1=support cmdline option -m
?EXTVIEW         EQU 0  ; 1=extended exFAT direntry view
?ALTKEYS         EQU 1  ; 1=handle Alt-Left/Right

        BOTTOMROW        equ 42 ; last row (menu, messages)
        RIGHTCOL         equ 79 ; last col
        ROWXXX           equ 1  ; row where all displays start
        VIEWROW          equ 34 ; start of "view" area
        COLHEX           equ 10 ; column where hex display starts
        COLBIN           equ 11 ; column where binary display starts
        COLASC           equ 63 ; column where ascii display starts
        VIEWBYTES        equ 32*16 ; 32 rows a 16 bytes

        CD_SECTOR_OFFSET EQU 10h  ; can't read first 16 sectors of CDs
        DIRENTSIZE       EQU 32   ; size of directory entry (FATxx + exFAT)

; "bRW" variable
        RW_READ          EQU 0
        RW_WRITE         EQU 1

; "filesys" variable
        FS_UNDEFINED     EQU 0
        FS_FAT12         EQU 1  ; bits 0-2 (FAT12-FAT32) must not be changed;
        FS_FAT16         EQU 2  ; they are used to calculate a shift factor.
        FS_FAT32         EQU 4
        FS_EXFAT         EQU 8 or FS_FAT32
        FS_FATXX         EQU FS_FAT12 or FS_FAT16 or FS_FAT32 or FS_EXFAT
        FS_NTFS          EQU 16

; "bRegion" variable for figuring out what section we're on in the drive
        RG_UNDEFINED     EQU 0
        RG_RESERVED      EQU 00010000b
        RG_FAT           EQU 00100000b
        RG_ROOT          EQU 01000000b
        RG_DATA          EQU 10000000b

        ; if "region" does not have any of the lower 4 bits set, then
        ; it is set with a viewmode

; "viewmode" defines what the section at the bottom of the screen just above
; the menu is used to display (for additional information)
        VM_DATA          EQU 0          ; not manually set mode
        VM_MBR           EQU 1
        VM_BOOTSECTOR    EQU 2
        VM_FAT12         EQU 3
        VM_FAT16         EQU 4
        VM_FAT32         EQU 5
        VM_DIRECTORY     EQU 6
if ?DEBUG
        VM_DEBUG         EQU 7
        VM_LAST          EQU VM_DEBUG
else
        VM_LAST          EQU VM_DIRECTORY
endif
        VM_FSINFO        EQU 10000000b  ; not manually set mode     

; "viewmode2"
        VM2_AUTODETECT   EQU 0
        VM2_STATIC       EQU 1

; colors for the display
ifdef ?MONO
        COL_EDIT         EQU 70h         ; just use black/white/grey
        COL_DEFAULT      EQU 0fh
        COL_INACTIVE     EQU 07h
        COL_HIGHLIGHT    EQU 0F0h
else
;        COL_EDIT         EQU 0cah        ; light green on red
        COL_EDIT         EQU 0B0h        ; black on light cyan
        COL_DEFAULT      EQU 1fh         ; white on blue
        COL_INACTIVE     EQU 17h         ; light grey on blue
        COL_HIGHLIGHT    EQU 30h         ; black on dark cyan
endif

; "editmode" variable
        EM_DEFAULT       EQU 0
        EM_ASCII         EQU 1

; "displaymode" variable
        DM_HEX           EQU 0
        DM_BINARY        EQU 1

;--- drvtype and rwfunc are connected

; "drvtype" variable
        DT_PHYSICAL      EQU 0
        DT_LOGICAL       EQU 2
        DT_CDROM         EQU 4           ; CD-ROM is actually also a "logical" drive
        DT_FILE          EQU 6

; "rwfunc" variable
        RWF_OLDINT13     EQU 0
        RWF_NEWINT13     EQU 1
        RWF_OLDLOGICAL   EQU 2
        RWF_NEWLOGICAL   EQU 3
        RWF_CDCOOKED     EQU 4
        RWF_CDRAW        EQU 5
        RWF_FILE         EQU 6

; flags for int 13h, ah=43h (RWF_NEWINT13 write)
        NO_VERIFY               EQU 0
        VERIFY                  EQU 2
        NEWINT13_WRITE_FLAG     EQU NO_VERIFY

; directory entry attribute bits
        READONLY         EQU 00000001b
        HIDDEN           EQU 00000010b
        SYSTEM           EQU 00000100b
        VOLUME           EQU 00001000b
        DIRECTORY        EQU 00010000b
        ARCHIVE          EQU 00100000b

; fat directory data offsets
        DIR_ATTRIBUTES   EQU 0Bh
        DIR_CREATEMSEC   EQU 0Dh
        DIR_CREATETIME   EQU 0Eh
        DIR_CREATEDATE   EQU 10h
        DIR_LASTACCDATE  EQU 12h
        DIR_CLUST_HIGH   EQU 14h
        DIR_LASTUPDTIME  EQU 16h
        DIR_LASTUPDDATE  EQU 18h
        DIR_CLUST_LOW    EQU 1Ah
        DIR_FILESIZE     EQU 1Ch

; ascii
;        BACKSPACE_KEY    EQU 8
;        TAB_KEY          EQU 9
;        CTRLENTER_KEY    EQU 10
        ENTER_KEY        EQU 13
        ESCAPE_KEY       EQU 27

        SPACE            EQU ' ' ;20h
        DOUBLE_QUOTE     EQU '"' ;22h
        PERCENT          EQU '%' ;25h
        ASTERISK         EQU '*' ;2ah
        COMMA            EQU ',' ;2ch
        PERIOD           EQU '.' ;2eh
        FORWARD_SLASH    EQU '/' ;2fh
        COLON            EQU ':' ;3ah
        SEMICOLON        EQU 3bh; ';' ;3bh
        LESS_THAN        EQU '<' ;3ch
        GREATER_THAN     EQU '>' ;3eh
        QUESTION_MARK    EQU '?' ;3fh
        BACK_SLASH       EQU '\' ;5Ch
        PIPE             EQU '|' ;7ch


; scan codes
        BACKSPACE_SCAN   EQU 0eh
        TAB_SCAN         EQU 0fh
        ENTER_SCAN       EQU 1ch
        F1_KEY           EQU 3bh
        F2_KEY           EQU 3ch
        F3_KEY           EQU 3dh
        F4_KEY           EQU 3eh
        F5_KEY           EQU 3fh
        F6_KEY           EQU 40h
        F7_KEY           EQU 41h
        F8_KEY           EQU 42h
if ?DEBUG
        F12_KEY          EQU 86h
endif

        HOME_KEY         EQU 47h
        CSRUP_KEY        EQU 48h
        PAGEUP_KEY       EQU 49h
        CSRLEFT_KEY      EQU 4bh
        CSRRIGHT_KEY     EQU 4dh
        END_KEY          EQU 4fh
        CSRDOWN_KEY      EQU 50h
        PAGEDOWN_KEY     EQU 51h
        INS_KEY          EQU 52h
        DEL_KEY          EQU 53h

        CTRLENTER_KEY    EQU 1C0Ah  ;check both AH & AL (so 0A can be entered by ctrl-j)

        CTRLLEFT_KEY     EQU 73h
        CTRLRIGHT_KEY    EQU 74h
        CTRLEND_KEY      EQU 75h
        CTRLPAGEDOWN_KEY EQU 76h
        CTRLHOME_KEY     EQU 77h
        CTRLPAGEUP_KEY   EQU 84h
        CTRLUP_KEY       EQU 8dh
if ?ALTKEYS
        ALTLEFT_KEY      EQU 9Bh
        ALTRIGHT_KEY     EQU 9Dh
endif

; "handling" variable
        ABORT_OPERATION  EQU 0   ;  abort by default
        QUERY_FILL       EQU 1   ;  query user with "fill with zero"
        QUERY_SKIP       EQU 2   ;  query user with "skip"
        IGNORE_ERRORS    EQU 3   ;  ignore errors

; "fillflag" variable - low byte (type of fill)
        FL_RANDOM        EQU 0
        FL_INVERSE       EQU 1
        FL_BIT8          EQU 2
        FL_BIT12         EQU 3
        FL_BIT16         EQU 4
        FL_BIT32         EQU 5
;                     - high byte (for BIT fills)
        FL_INCREMENT     EQU +1
        FL_DECREMENT     EQU -1

; "srflag" variable
        SR_SAVE          EQU 0
        SR_RESTORE       EQU 1

; "chainflag" variable
        NO_CHAIN         EQU 0
        FILE_CHAIN       EQU 1
        FAT_CHAIN        EQU 2

;--- define a string in .const
CStr macro text:vararg
local sym
    .const
sym db text,0
    .code
    exitm <offset sym>
endm

;--- define a string in .const
DStr macro text:vararg
local sym
    .const
sym db text,0
    .data
    exitm <offset sym>
endm

;--- menu definition macros

@mstart macro index
_DATA2 segment
index equ $ - startmenudefs
endm

@mend macro name_
l&name_ equ ( $ - startmenudefs ) - name_
_DATA2 ends
endm

@mitem macro stridx, cmdofs, name_
name_  db stridx
_TEXT2 segment
    dw cmdofs
_TEXT2 ends
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
sec_per_fat1x    dw ?   ;+11 (sectors/fat for fat12/fat16)
sectors_track    dw ?
no_of_tracks     dw ?
hidden_sectors   dd ?   ;+17
sectors_fat1632  dd ?   ;+21 (sectors total FAT16/32)
BPB ends

;--- FAT12/FAT16 extended BIOS parameter block
EBPB struct
    BPB <>
phys_drive      db ?    ;+0x19 (???)
                db ?
ext_boot_sig    db ?    ;=0x29
volume_id       dd ?
volume_label    db 11 dup (?)
fs_type         db 8 dup (?)
EBPB ends

EBPB_FAT32 struct
    BPB <>
sec_per_fat32   dd ?    ;+0x19 (sectors/fat for fat32)
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

    include exfat.inc

;--- HD access for int 13h, ah=42h/43h

DAP struct
bSize       db ?    ;+0 size of structure
bRes        db ?    ;+1 reserved
sectors     dw ?    ;+2 sectors to transfer
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

;--- disk info returned by Int 13h, ah=48h

DINFO1 struct
_size    dw ?
flags    dw ?
cyls     dd ?
heads    dd ?
secs     dd ?
totalsecL dd ?
totalsecH dd ?
bps      dw ?
DINFO1 ends

CDREQ struct
_size    db ?
         db ?
cmd      db ?           ;+2
status   dw ?           ;+3
         db 9 dup (?)
bufofs   dw ?           ;+14
bufseg   dw ?           ;+16
numsec   dw ?           ;+18
startsec dd ?           ;+20
mode     db ?           ;+24
         db ?,?,?
CDREQ ends

;--- this struct is used for communication with readsect()/writesect()
;--- currently only a static member!

IOREQ struct
dwSector   dd ?
if ?SN64
dwSectorH  dd ?
endif
bDrive     db ? ; drive number (bDrive ... drvtype must be one dword)
bRW        db ? ; distinguish between read/write
rwfunc     db ? ; what read/write function to use
drvtype    db ? ; physical/fat/cdrom/file
pBuffer    dw ?
IOREQ ends

MENULVL struct  ; item for menu stack, size must be 4
bMenuStart db ?
bMenuSize  db ?
bSpaces    db ?
           db ?
MENULVL ends

SECITEM struct  ; item on "sector stack", size must be 8
dwSector dd ?
wSpot    dw ?
         dw ?
SECITEM ends

    .const

introtext       db 'WDe V0.50',0
copyright       db 'Copyright(C) 2005 Ben Cadieux, 2022 japheth',0

owmsg           db 'File Exists - A(ppend), O(verwrite) or C(ancel)? ',0
fhdmsg          db 'F(loppy) or H(ard) disk? ',0
cdrcmsg         db 'R(aw) or C(ooked) mode? ',0
plmsg           db 'L(ogical) or P(hysical) disk? ',0
abmsg           db 'A(bove) or B(elow)? ',0
truncatemsg     db 'Truncate To Filesize',0
diskfullmsg     db 'Disk Full',0
quitmsg         db 'Quit',0
ynmsg           db ' [Y/n]? ',0

unknownmsg      db 'Unknown',0
szActive        db '(Active)',0

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

menustrings     label byte
                db 'Save',0                             ; 0
                db 'File',0                             ; 1
                db 'Goto',0                             ; 2
                db 'View',0                             ; 3
                db 'Find',0                             ; 4
                db 'Functions',0                        ; 5
                db 'Change Disk',0                      ; 6
                db 'Sector',0                           ; 7
                db 'Boot Sector',0                      ; 8
                db 'Cluster',0                          ; 9
                db 'Fat1',0                             ; 10
                db 'Fat2',0                             ; 11
                db 'Root',0                             ; 12
                db 'Data Area',0                        ; 13
                db 'Save to File',0                     ; 14
                db 'Restore from File',0                ; 15
                db 'Input',0                            ; 16
                db 'MBR',0                              ; 17
                db 'Partition1',0                       ; 18
                db 'Partition2',0                       ; 19
                db 'Partition3',0                       ; 20
                db 'Partition4',0                       ; 21
szPartition     db 'Partition',0                        ; 22
                db 'Chain',0                            ; 23
                db 'Dump CD As ISO',0                   ; 24
                db 'Auto',0                             ; 25
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
                db 'Next',0                             ; 43
                db 'Help',0                             ; 44
                db '$MFT',0                             ; 45

;--- a few menu items are dynamically (de)activated. 
;--- in those cases the menu string# must be known;
;--- hence the MENUF_xxx definitions.

MENUF_RESTORE equ 15
MENUF_CHAIN   equ 23

if ?EXT
MENUF_UNFORMAT equ 46
MENUF_UNDELETE equ 47
                db 'UnFormat',0                         ; 46
                db 'UnDelete',0                         ; 47
endif


startchs        db 'S-CHS ',0
endchs          db 'E-CHS ',0
;startchs        db 'S-CHS %u/%u/%u',0
;endchs          db 'E-CHS %u/%u/%u',0
startlba        db 'S-LBA ',0
mboot           db 'Boot  ',0
mtype           db 'Type  ',0
psize           db 'Sects ',0

searchingmsg    db 'Searching...',0
writetodiskmsg  db 'Writing To Disk...',0
restoremsg      db 'Restoring...',0
writingmsg      db 'Writing File...',0

readingdrive    db 'Reading Drive...',0
recursemsg      db 'Recursing Chain... %s, curr. cluster %lX / %lX',0

searcherror     db 'No (more) Matches Found',0
abortfmsg       db 'Aborted Writing File',0
abortdmsg       db 'Aborted Writing to Disk',0

donewritefile   db 'Finished Writing File, %lu sector(s) written',0
donewritedisk   db 'Finished Writing to Disk',0

toosmall        db 'File Too Small',0
filenotfound    db 'File Not Found',0
filetoobigmsg   db 'File Size Cannot Exceed 4GB-1',0

errorread       db 'Error Reading File',0
filewriteerr    db 'Error Writing File',0
filecreateerr   db 'Error Creating File',0

invalidpmsg     db 'Invalid Sector Range',0

sectorrerror    db 'Error Reading Sector %lu',0
sectorrerror2   db ' - Abort/Zero-Fill [A/Z]? ',0
sectorrerror3   db ' - Abort/Skip/Ignore All [A/S/I]? ',0
sectorwerror    db 'Error Writing Sector %lu',0
invalstartclust db 'Invalid Start Cluster',0
nochainmsg      db 'Recursive Link Not Found',0
nosearchstring  db 'No search string defined yet',0
szDriveinvalid  db 'Drive invalid',0
invalclustmsg   db 'Cluster %lX invalid',0
endofchainmsg   db 'End of cluster chain reached',0
secsizetoobig   db 'Sector size exceeds 4K',0
errormsg        db ' - Press Any Key',0

inmbrmsg        db '[MBR]',0
infatmsg        db '[Fat-',0
inrootmsg       db '[Root]',0
indatamsg       db '[Data]',0
inreservedmsg   db '[Boot/Reserved]',0

;--- prompts
szHex           db 'Hex: ',0
szSector        db 'Sector: ',0
szCluster       db 'Cluster: ',0
szDrive         db 'Drive: ',0
szFile          db 'File: ',0
szString        db 'String: ',0
szNoOfSectors   db 'Number of Sectors (1-%lu): ',0

szSector2       db 'Sector (0-%lu): ',0
szCluster2      db 'Cluster (2-%lX): ',0

partmsg         db 'Part: ',0
sizemsg         db 'Size: ',0
entrymsg        db 'Entry: ',0
offsetmsg       db 'Offset: ',0
createdmsg      db 'Created: ',0
accessedmsg     db 'Accessed: ',0
modifiedmsg     db 'Modified: ',0
attributesmsg   db 'Attributes: ',0

    .data

_psp   dw 0
_mem   dw 0   ; current top of memory
_0000H dw 0   ; segment value/selector for access to BIOS data

fifields label word
    dw DStr('Total Free Clusters: '), offset printvalue_hl
    dw DStr('First Free Cluster:  '), offset printhex_hl
numfifields equ ($ - offset fifields) / (2 * sizeof word)

_BSS segment

vidaddr         dd ? ; start video buffer
stackbot        dw ? ; stack bottom
vidcolsize      dw ?
vidrows         db ?
vidpg           db ?
scrn_xy         label word ; xy position on screen
scrn_col        db ?
scrn_row        db ?
crsr_xy         dw ? ; cursor xy position
spot            dw ? ; keeps count of what byte we're editing 0-511
sectofs         dw ? ; because [spot] goes from 0-511, if we have sectors
                     ; that are >512 bytes, sectofs keeps track of what
                     ; 512-byte piece we're working with
maxleft         db ?
bHL             db ? ; keeps track of whether we're editing high or low nibble

    align dword
fromfat         db ? ; fat to use for getfatentry/putfatentry
filesys         db ? ; type of fat
bSpC            db ? ; sectors per cluster
bFats           db ? ; number of fats
dwSpF           dd ? ; sectors per fat
dwFat1end       dd ? ; end of first fat
dwReserved      dd ? ; reserved sectors (start of fat)
rootentries     dw ? ; number of root entries (unused)
wRootsectors    dw ? ; number of root sectors
dwCurSector     dd ? ; current sector in sectbuffer
if ?SN64
dwCurSectorH    dd ? ; high sector dword for int13h
endif
dwDataend       dd ? ; end of data (last sector)
if ?SN64
dwDataendH      dd ? ; high dword for int13h HUGE hds
endif
dwDataStart     dd ? ; start sector of data region
dwLastCluster   dd ? ; total # of clusters on the drive
dwRootSect      dd ? ; start sector of root directory
dwRootCluster   dd ? ; root start cluster (FAT32)
dwValue         dd ?
dwMaxvalue      dd ?
dwFilesize      dd ? ; size of current image file, or current file chain to save
dwCluster       dd ?
dwBpC           dd ? ; bytes per cluster
dwSecBackup     dd ? ; sector backup
dwNumCluster    dd ? ; clusters to be saved in exFAT savechain/restorechain variant
partitions      dd ?,?,?,? ; partition start sectors

backupbs        dw ? ; backup boot sector location (FAT32)
fsinfo          dw ? ; fsinfo sector (FAT32)
wBps            dw ? ; current bytes per sector ( both physical/logical )
lastbottomtext  dw ? ; printbottom backs up string pointer for readsect/writesect
                     ; to reprint it when there's a sector error
hdnumber        db ? ; hard drive number partition belongs to
bSpCshift       db ? ; sectors per cluster for doing bitshifts
spcc            db ? ; sectors per cluster counter
bRegion         db ? ; what part of the disk we're in
viewmode        db ? ; see VM_xxx
viewmode2       db ? ; 0 = autodetect view, 1=force view
displaymode     db ? ; hex or binary
editmode        db ? ; what mode being edited in (ascii/default)

HIGHLIGHT struct
ofs   dw ?
siz_  db ?
scsiz db ?
HIGHLIGHT ends

highlight       HIGHLIGHT <>; area to highlight with viewmode

seed12          label dword
seed1           dw ?
seed2           dw ?
seed34          label dword
seed3           dw ?
seed4           dw ?

dwRwfilesize    dd ?            ; filesize of image file for DT_FILE
dwDrivestart    dd ?            ; used for sector restriction ( physical access only )
if ?SN64
dwDrivestartH   dd ?
endif
dwFat12start    dd ?            ; stores the sector number when fat12
                                ; view mode was selected
rwhandle        dw ?            ; file handle if device is DT_FILE
wFilehandle     dw ?            ; file handle for file ops
cylinders       dw ?            ; disk geometry for int 13h, ah=02/03
fillflag        db ?,?
area            db ?            ; specifies where on a drive we are
srflag          db ?            ; "file ops" menu flag
undelflag       db ?            ; 
driveflag       db ?            ; setdrive gets File or Drive? 0/1 respective
commandflag     db ?            ; used by unformat
chainflag       db ?            ; dictates what type of chain to save
                                ; fat links/file
heads           db ?
sectors         db ?
handling        db ?            ; inside readsect/writesect: how to handle errors
menustackidx    db ?            ; index for menustack
secstk_top      db ?            ; index for secstk
bHexString      db ?            ; stringbuffer filled with hex value
if ?SAFEMODE
bSafe           db ?            ; "safe" mode cmdline option set?
endif
if ?MOUNT
bMount          db ?            ; mount partition + 1
endif
bTabSw          db ?
bSkipFat        db ?
;unlockdrv       db ?            ; unlock this drive if != 0
bSecSh          db ?            ; shift factor for wBps

;--- unformat fields
    align dword
maxsize         dd ?            ; maximum filesize to recover
minsize         dd ?            ; minimum filesize to recover
dwNextsize      dd ?            ; next smallest filesize to recover
fat12fixsec     dd ?            ; sector # for fat12 fix
lostdirs        dw ?            ; total lost directories found
rootdirs        dw ?            ; total root directories found
wDirs           dw ?            ; total dirs found
lasttick        dw ?            ; timer ticks since last call

if ?DEBUG
starttime       dd ?
storedeax       dd ?
storedebx       dd ?
storedecx       dd ?
storededx       dd ?
storedsi        dw ?
storeddi        dw ?
endif

oldint24        dd ?
                dw ?            ; add a word to oldint24 in case it runs in dpmi32
rembytes        dw ?            ; remaining bytes when dealing with
                                ; non-standard sized sectors

    align 4
menustack       MENULVL 4 dup (<?>)  ; menu stack
secstk          SECITEM 8 dup (<?>)  ; sector stack ( room for 8 items )
if ?LFN
filenamebuffer  db 256 dup (?)
else
filenamebuffer  db 72 dup (?)   ; size must be at least 69, 72 used for alignment
endif
stringbuffer    db 74 dup (?)   ; buffered string for find/fill
stringlen       dw ?
sprintfbuffer   db 80 dup (?)   ; buffer for sprintf
ioreq           IOREQ <?>
diskinfobuffer  DINFO1 <?>      ; buffer for int13h "get drive info"
cdheader        CDREQ <?>       ; cd device request header
drivepacket     DISKIO <?>      ; used by int 25h/26h and int 21h/ax=7305h
dapacket        DAP <?>         ; used by int 13h ah=42h/43h (extended read/write)
valuebuffer     db 11 dup (?)


;--- the alignment must observe the fat12fix.
;--- the handling of this format requires one byte just before
;--- and one byte just after the sector buffer.
    align 4
                db 3 dup (?)    ; ensure sectbuffer is dword aligned
fat12fix1       db ?            ; stores first borrowed byte for fat12

BUFFSHIFT equ 12                ; sectbuffer must be a factor of 2

sectbuffer      db (1 shl BUFFSHIFT) dup (?) ; read buffer for sector reading


_BSS ends

    .code

getstring proto stdcall :ptr, :word, :word, :word, :ptr

if ?PM
    include initpm.inc
    include wdepm.inc
endif

;--- code to access WDEVDD on NT platforms.

if ?VDD
    include wdent.inc
else
@int13 equ <int 13h>
@int21 equ <int 21h>
@int2F equ <int 2Fh>
@int25 macro
    int 25h
    pop dx
endm
@int26 macro
    int 26h
    pop dx
endm
endif

    include sprintf.inc
if ?DEBUG
    include ..\Test\timer.inc
endif
@getstarttime macro
if ?DEBUG
    pushad
    call gettimer
    mov starttime, eax
    popad
endif
endm
@printtime macro formstr 
if ?DEBUG
    pushf
    pushad
    call gettimer
    sub eax, starttime
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr(formstr), eax
    call printerror
    popad
    popf
endif
endm
@dprintf macro formstr, args:vararg 
if ?DEBUG
    pushf
    pushad
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr(formstr), args
    call printerror
    popad
    popf
endif
endm

;--- main menu definition

    @mstart initialmenu
    @mitem 44, helpscreen
    @mitem  1, submenu_file
    @mitem  2, submenu_jumpto
    @mitem  3, submenu_view
    @mitem  4, submenu_find
    @mitem  5, submenu_functions
    @mitem  0, savetodisk
    @mend initialmenu

Start proc

;--- setup small memory model

    cld
    mov dx, @data
    mov ds, dx
    mov [_psp], es
    mov ax, ss
    sub ax, dx
    shl ax, 4
    mov ss, dx
    add sp, ax
if 1 ;free memory beyond 64kB dgroup
    mov cx, es
    mov bx, ds
    sub bx, cx
    add bx, 1000h
    mov ah, 4ah
    int 21h
    jc quit
endif
    push ds
    pop es

;--- now ds=es=ss=dgroup

;--- clear uninitialized vars

    mov di, offset startbss
    mov cx, sp
    sub cx, di
    shr cx, 1
    xor ax, ax
    rep stosw

if ?VDD
    call initvdd         ; init vdd on nt platforms ( works in V86 only, not in PM )
endif

;--- copy cmdline to dgroup

    push ds
    push ds
    pop es
    mov ds, [_psp]
    mov di, offset sprintfbuffer
    mov si, 80h+1
@@:
    lodsb
    stosb
    cmp al,13
    jz @F
    cmp al,0
    jnz @B
@@:
    pop ds
    mov byte ptr [di-1],0

;--- scan command line

    mov si, offset sprintfbuffer
@@:
    lodsb
    cmp al,0
    jz no_drive
    cmp al,' '
    jbe @B
    mov ah,[si]
    cmp al,'/'
    jz handleoptions
    cmp al,'-'
    jz handleoptions
    cmp al, '0'
    jb inval_cmd
    cmp al, '9'
    jbe maybedrive
    mov bh, DT_LOGICAL
    or al, 20h
    cmp al, 'a'
    jb inval_cmd
    cmp al, 'z'
    ja inval_cmd
    sub al, 'a'
    cmp ah, ':'
    jz has_drive
    jmp inval_cmd
handleoptions:
    call options
    jnc @B
inval_cmd:
    jmp printhelp
maybedrive:
    mov bh, DT_PHYSICAL
    sub al, '0'
    or al, 80h
    cmp ah, 0
    jz has_drive
    or ah, 20h
    cmp ah, 'h'
    jz has_drive
    and al, 7fh
    cmp ah, 'f'
    jz has_drive
    jmp inval_cmd
no_drive:
    mov al, -1
has_drive:
    pusha

    call setseeds1
    call vinit                  ; init video mode, init screen
if ?PM
    call initpm
    call wdepm
    mov bl,24h                  ; use DPMI to modify int vector, since
    mov ax, 204h                ; DS MUST hold DGROUP selector when int 21h is called
    int 31h
    @storevec [oldint24]
    mov cx, cs
    @movofs dx, offset myint24
    mov al, 5
    int 31h
else
    mov ax, 3524h               ; back up old int 24h ( must be done AFTER switch to pm )
    int 21h
    mov word ptr [oldint24+0], bx
    mov word ptr [oldint24+2], es
    push ds
    mov dx, offset myint24      ; new address in DS:DX
    push cs
    pop ds
    mov ah, 25h                 ; set up new int 24h
    int 21h
    pop ds
endif
    popa

    mov [stackbot], sp
    mov [_mem], sp              ; set start of heap ( currently used by unformat only )
    cmp al, -1
    jnz disk_entered

enter_disk:
if ?MOUNT
    mov [bMount], 0             ; reset any mount option
endif
    call setdrive
    jnc disk_entered
    call quit
    jmp enter_disk
disk_entered:
    call trydevice
    jc enter_disk
    call clearsecarea           ; clear sector rectangle (contains copyright msg)
;drive_ok::
    call setvariables           ; set all obtainable parameter variables

if ?MOUNT
    cmp [ioreq.drvtype], DT_PHYSICAL
    jnz @F
    movzx eax, [bMount]
    cmp al, 0
    jz @F
;--- setvariables moved partition startsectors in [partitions]
    dec ax
    mov eax, [partitions+eax*4]
    mov [ioreq.dwSector], eax
    call readsect
    call mountdrive
@@:
endif

    xor dx, dx
    call nspotcalc
    mov [crsr_xy], dx           ; set cursor to spot 0
    call printoffset            ; print current offset

    mov dx, initialmenu + linitialmenu shl 8
    mov cl, 3
    call initmenustack

Start endp

;--- falls thru!

main proc

    mov sp, [stackbot]
    mov [handling], ABORT_OPERATION  ; inside main
    call updatescreen           ; print line 0, sector area and view area
    call printmenu

    push offset main

getkeyagain:
    mov ax, [crsr_xy]           ; set [scrn_xy] to cursor coordinates so that
    mov [scrn_xy], ax           ; functions like changemode color the right
                                ; spot on the screen
    call getkey

    cmp al, ESCAPE_KEY          ; exit menu or program
    je handle_esc
    cmp al, ENTER_KEY           ; jump to cluster ( in FAT or directory )
    je handle_enter
    cmp ax, CTRLENTER_KEY       ; jump to FAT entry for current cluster
    je handle_ctlenter
if ?DEBUG
    cmp ah, F12_KEY
    jnz @F
    mov [viewmode], VM_DEBUG
@@:
endif

    call checkmenukey           ; check for menu (=function) keys

    mov dx, sp                  ; set dx to "clean" stack
    push offset getkeyagain     ; default to 'no full screen update'
    push offset updateview      ; edit keys may change view, so update it after processing

    call ctrlkeys               ; check for control keys

;    cmp ah, DEL_KEY             ; allow writing of null when the "del" key in ascii
;    je @F                       ; edit mode is pressed (however, al is 0E0h then!).
    cmp al, 0                   ; don't write null values in ascii for certain
    je skipkey                  ; extended keys (Fxx keys)
    cmp al, 0E0h                ; don't write 0E0h values in ascii for certain
    je skipkey                  ; extended keys (Home, End, PgUp, ...)
@@:
    call bufferinsi
    mov bx, [spot]
    cmp [editmode], EM_ASCII
    je modascii
    cmp [displaymode], DM_BINARY
    je modbinary
modhex:
    sub al, '0'                 ; check for valid hex digit
    cmp al, 9
    jbe digitok                 ; '0' - '9'?
    sub al, 'A' - '0'           ; 'A' - 'F' -> 0 - 5
    cmp al, 5
    jbe @F
    sub al, 32                  ; check again for lower-case
    cmp al, 5                   ; 'a' - 'f'?
    ja skipkey
@@:
    add al, 10                  ; convert A-F (=0-5) to 0A-0F
digitok:
    mov cl, [si+bx]             ; get the byte to be edited from the buffer
    cmp [bHL], 0                ; low or high nibble to be changed?
    jne @F
    and cl, 0Fh
    shl al, 4
    jmp donehex
@@:
    and cl, 0F0h                ; remove the bottom nibble
donehex:
    or al, cl                   ; set new high/low nibble

modascii:
    mov [si+bx], al             ; store the modified value
    jmp displaybyte

modbinary:                      ; "binary" mode, just '0', '1' or SPACE accepted
    mov cl, [bHL]
    cmp cl, 5                   ; if we're over the space between nibbles
    jb @F                       ; decrement so that the position matches
    dec cl                      ; incrementally to bits 0-7
@@:
    mov dl, 10000000b           ; this byte gets shifted as a mask
    shr dl, cl                  ; to work with the bit we're editing

    cmp al, '1'
    je onebin
    cmp al, SPACE
    je reversebin
    cmp al, '0'
    jne skipkey
    not dl
    and [si+bx], dl             ; clearing a bit
    jmp donefixbin
reversebin:
    xor [si+bx], dl             ; changing a bit
    jmp donefixbin
onebin:
    or [si+bx], dl              ; setting a bit
donefixbin:
    mov al, [si+bx]

displaybyte:                    ; display AL both in hex/binary and ascii
    mov dx, bx
    call nspotcalc
    mov [scrn_xy], dx
    cmp [displaymode], DM_HEX   ; hex or binary?
    je @F
    call rendernumbin
    jmp done_render
@@:
    mov dl, 2
    call rendernumhex
done_render:
    call printstring            ; display rendered number
    mov dx, bx
    call aspotcalc
    mov [scrn_xy], dx
    mov cl, 1
    call fillchar               ; display ascii value
    jmp moveright

skipkey:
    pop ax                      ; skip view update
    ret
handle_esc:
    cmp [menustackidx], 0       ; in main menu?
    jz quit                     ; then ask to quit;
    dec [menustackidx]          ; else pop one menu level
    ret

main endp

options proc
    lodsb
    and al,al
    jz error
    or al,20h
if ?SAFEMODE
    cmp al,'s'
    jnz @F
    mov [bSafe], 1              ; deactivate all write access
    ret
@@:
endif
if ?MOUNT
    cmp al,'m'
    jnz @F
    lodsb 
    and al,al
    jz error
    sub al,'0'
    jc error
    cmp al,4
    cmc
    jc error
    inc ax
    mov [bMount], al
    ret
@@:
endif
error:
    stc
    ret
options endp

;--- handle control keys
;--- these are supposed to work in all menus

CKey macro x,y
    .const
    db x
    .code
    dw y
endm

    .const
ckc label byte
    .code
    align 2
ck  label word
    CKey PAGEDOWN_KEY,     nextsect
    CKey PAGEUP_KEY,       prevsect
    CKey CTRLPAGEDOWN_KEY, nextsect1000
    CKey CTRLPAGEUP_KEY,   prevsect1000
    CKey CTRLLEFT_KEY,     recursechain
    CKey CTRLRIGHT_KEY,    jumpcluster
    CKey CTRLUP_KEY,       jumpstkpop
    CKey CTRLHOME_KEY,     jumptobootsector
    CKey CTRLEND_KEY,      jumptolastsect
    CKey TAB_SCAN,         changemode
if ?ALTKEYS
    CKey ALTLEFT_KEY,      prevcluster
    CKey ALTRIGHT_KEY,     nextcluster
endif
lck1 equ ($ - ck) shr 1
    CKey CSRLEFT_KEY,      moveleft
    CKey CSRRIGHT_KEY,     moveright
    CKey CSRUP_KEY,        moveup
    CKey CSRDOWN_KEY,      movedown
    CKey HOME_KEY,         movefirst
    CKey END_KEY,          movelast
lck equ ($ - ck) shr 1

;--- in: dx=clean SP

ctrlkeys proc
    push ax
    push ds
    pop es
    mov al, ah
    mov di, offset ckc
    mov cx, lck
    repnz scasb
    pop ax
    jz @F
    ret
@@:
    pop cx         ; skip return address
    dec di
    sub di, offset ckc
    cmp di, lck1
    jnb @F
    mov sp, dx     ; clean stack ( skip calls meant for "simple" control keys )
@@:
    shl di, 1
    jmp word ptr cs:[di][ck]  ; function tables are in the code segment

ctrlkeys endp

;--- check if function key is for current menu
;--- modifies cx, bx

checkmenukey proc

    mov cl, ah
    sub cl, F1_KEY              ; convert F1-F8 to 0-7
    jb @F
    movzx bx, [menustackidx]
    shl bx, 2
    add bx, offset menustack
    cmp cl, [bx].MENULVL.bMenuSize
    jb found
@@:
    ret
found:
    add cl, [bx].MENULVL.bMenuStart
    movzx bx, cl
    cmp [bx][startmenudefs], -2 ; item deactivated?
    jz @B
    shl bx, 1
    pop cx                      ; skip return address
    jmp cs:[bx][startmenucmds]  ; function tables are in the code segment

checkmenukey endp

;--- push a new level onto the menu stack
;--- there's room for 4 levels ( all are used )
;--- example: 0=initialcmds, 1=funccmds, 2=fillcmds, 3=incdeccmds
;--- in: DL=start, DH=size menu

pushmenustack proc
    inc [menustackidx]
initmenustack::
    movzx bx, [menustackidx]
    shl bx, 2
    add bx, offset menustack
    mov [bx].MENULVL.bMenuStart, dl
    mov [bx].MENULVL.bMenuSize, dh
    mov [bx].MENULVL.bSpaces, cl
    ret

pushmenustack endp


;--- alloc AX bytes on the dgroup heap

allocmem proc
    add ax, [_mem]
    jc @F             ; out of space?
    xchg ax, [_mem]
@@:
    ret
allocmem endp

freemem proc
    mov [_mem], ax
    ret
freemem endp

;--- try a new device
;--- "usually" called after setdrive()
;--- AL = drive number
;--- BH = PHYS/FAT/CDROM

trydevice proc
    mov dx, offset readingdrive
    call printbottom

;    push [dwCurSector]           ; if drive switching is unsuccessful,
    push dword ptr [ioreq.bDrive] ; some fields will have to be restored.
    push [wBps]                   ; might be used inside readsect (zero-fill)!
    push [dwDrivestart]

    mov [ioreq.dwSector], 0       ; attempt to read sector 0
if ?SN64
    mov [ioreq.dwSectorH], 0
endif
    mov [ioreq.pBuffer], offset sectbuffer
    mov [ioreq.drvtype], bh
    mov [dwDrivestart], 0
    push ax
    mov ax, 512
    call setBps
    pop ax
    cmp bh, DT_FILE
    jnz @F
    mov [ioreq.rwfunc], RWF_FILE
    mov [dapacket.sectors], 1     ; used by file access!
    jmp tryread
@@:
    mov [ioreq.bDrive], al
    cmp bh, DT_LOGICAL
    jz trylogical
    call setphysvars              ; if ok, [ioreq.rwfuncs] and [wBps] are adjusted
    jnc tryread
    jmp driveinvalid
trylogical:
    inc al
    mov bl, al
    mov ax,4409h
    int 21h
    jc driveinvalid
    test dh,10h                       ; drive remote?
    jz tryfat
    movzx cx, [ioreq.bDrive]          ; check if drive is a CD-ROM
    mov ax, 150Bh
    int 2Fh
    cmp bx, 0ADADh                    ; 0ADADh returned if mscdex called
    jne tryfat
    test ax, ax                       ; ax=0 if not read successfully
    jnz iscdrom
tryfat:
    call setlogvars                   ; will set [ioreq.rwfunc], may change [wBps]
tryread:
    call readsect
    jc driveerror                     ; failed?
    mov [sectofs],0
    add sp, 4+2+4                     ; skip saved data on stack
    ret
driveinvalid:
    mov dx, offset szDriveinvalid
    call nuprinterror
driveerror:
    pop [dwDrivestart]                ; if reading the new drive failed
    pop ax
    call setBps
    pop dword ptr [ioreq.bDrive]      ; restores bDrive, rwfunc, drvtype, bRW
    stc
    ret

iscdrom:
    mov [ioreq.rwfunc], RWF_CDCOOKED
    mov [ioreq.drvtype], DT_CDROM     ; overwrite DT_LOGICAL

;    mov [cdheader._size], 13          ; size of header
    mov [cdheader._size], sizeof CDREQ
    mov [cdheader.bufseg], ds
    mov [cdheader.numsec], 1
    mov [cdheader.mode], 0            ; cooked mode
    mov bx, 2048
    mov dx, offset cdrcmsg            ; choose between raw/cooked
    call printbottom
@@:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je driveerror
    or al,20h
    cmp al, 'c'
    je @F
    cmp al, 'r'
    jne @B
    mov [cdheader.mode], 1            ; raw mode
    mov [ioreq.rwfunc], RWF_CDRAW
    mov bx, 2352
@@:
    mov ax, bx
    call setBps                 ; set sector size to 2048/2352
    jmp tryread

trydevice endp

;--- enter a disk/drive/image filename
;--- exit: C if ESC pressed or a blank filename was entered
;---       NC, then drive in AL, drvtype in BH

setdrive proc
    cmp [driveflag], 0          ; drive or filename to enter?
    jne fnreq
    mov dx, offset szDrive      ; prompt
    call printbottom            ; print on the bottom of the screen
getkeyagain:
    call cursorgetkey           ; cursorgetkey turns the cursor on, gets
                                ; a key and then shuts the cursor back off
                                ; again (for normal editing)
    cmp al, ESCAPE_KEY
    je abort
    cmp ah, TAB_SCAN
    je handle_tabkey

    sub al, '0'                 ; subtract 48, so '0' becomes 0, '1' = 1, etc
    cmp al, 9                   ; if the value is <= 9, the key pressed was
    jbe hdphysical              ; a drive number, 0-9

    mov bh, DT_LOGICAL
    sub al, 17                  ; 17 is the 65-48, so 'A' = 0, 'B' = 1, etc
    cmp al, 26                  ; if the value is > 26, a non-letter
    jbe done                    ; was pressed (non-valid drive letter)
    sub al, 32                  ; 32 is 'a'-'A', so 'a' = 0, 'b' = 2, etc
    cmp al, 26                  ; same concept as above
    jbe done
    jmp getkeyagain

hdphysical:
;--- this is for setting up the editing for a physical
;--- rather than logical drive. check if floppies are available.
    mov cl, al                  ; back up drive number
    mov es,[_0000H]
    test byte ptr es:[410h], 1  ; floppies available?
    jz nofds                    ; if no, skip asking

    mov dx, offset fhdmsg       ; choose between floppy and HD
    call printbottom
@@:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je setdrive
    or al,20h
    cmp al, 'f'
    je readasfd
    cmp al, 'h'
    jne @B
nofds:
    add cl, 80h                 ; physical hard drive.
readasfd:
    mov al, cl
;--- al: 80h+ = hard drive
;--- al: 00h+ = floppy
    mov bh, DT_PHYSICAL
    jmp done
abort:
    stc
    ret
handle_tabkey:
    xor [driveflag], 1
    jmp setdrive

tabsw:
    mov [bTabSw], 1
    stc                         ; exit getstring when TAB is pressed
    ret

fnreq:
    mov [bTabSw], 0
    mov ax, tabsw
    call getfilename
    cmp [bTabSw], 1             ; exit with TAB?
    je handle_tabkey
    jcxz abort                  ; no chars entered, or ESC pressed
    call findfileX
    jnc @F
    mov dx, offset filenotfound
    call nuprinterror           ; print error without screen update
    jmp fnreq
@@:
    mov eax, [dwFilesize]       ; file must be 1+ sectors in size
    cmp eax, 512
    jnc @F
    mov dx, offset toosmall     ; "File too small"
    call nuprinterror
    jmp fnreq
@@:
    mov [dwRwfilesize], eax
    mov bl, 2                   ; access mode (0=ro,1=wo,2=rw)
    call openfile
    mov [rwhandle], ax
    mov bh, DT_FILE
done:
    clc
    ret
setdrive endp

;--- menuitem "disk"

select_disk proc
@@:
    call setdrive
    jc done
    call trydevice
    jc @B
    call setvariables
done:
    ret
select_disk endp


    .const

quickhelptext label byte
    db "Quick Key Reference",0
    db 0
    db "Escape        - Back out of a menu (Quit also)",0
    db "Arrow Keys    - Change offset within data",0
    db "Home/End      - Move cursor to start/end of data",0
    db "PageUp        - Back 1 sector",0
    db "PageDown      - Forward 1 sector",0
    db "Ctrl+PageUp   - Back 100 sectors",0
    db "Ctrl+PageDown - Forward 100 sectors",0
    db "Tab           - Switch to/from ascii editing",0
    db "Shift+Tab     - Switch between hex and binary",0
    db "Ctrl+End      - Jump to last sector on drive",0
    db "Ctrl+Home     - Jump to first sector on drive",0
    db "Ctrl+Up       - Pop sector from stack and jump to it",0
    db 0
    db "Keys in FAT region of (ex)FAT partitions:",0
    db 0
    db "Ctrl+Right    - Jump to linked FAT entry (successor)",0
    db "Ctrl+Left     - Try to find linking FAT entry (predecessor)",0
    db "Enter         - Jump to current entry's data (=cluster)",0
    db 0
    db "Keys in Data region of (ex)FAT partitions:",0
    db 0    
    db "Ctrl+Right    - Jump to linked cluster in FAT (successor)",0
    db "Ctrl+Enter    - Jump to FAT entry for this cluster",0
if ?ALTKEYS
    db "Alt+Right     - Forward 1 cluster",0
    db "Alt+Left      - Back 1 cluster",0
endif
    db "Enter         - If in directory, jump to start cluster of entry",0
    db 0    
    db "On exFAT disks, a file may have no associated FAT chain; in such",0
    db "cases the file is stored contiguous and Ctrl+Right can't work.",0
if ?ALTKEYS
    db "Alt+Right is no real substitute, it won't detect the chain's end.",0
endif
    db -1

    .code

helpscreen proc

    call clearscreen
    mov [scrn_xy],0205h
    mov dx, offset quickhelptext
nextline:
    call printstring
    mov si, dx
nextchar:
    lodsb
    cmp al,0
    jnz nextchar
    cmp byte ptr [si],-1
    jz done
    inc [scrn_row]
    mov [scrn_col],5
    mov dx, si
    jmp nextline
done:
    mov dx, CStr("ESC to return")
    call printbottom
nextkey:
    call getkey
    cmp al, ESCAPE_KEY
    jnz nextkey
    call clearscreen
    call printoffset
    ret
helpscreen endp

;--- main menu, item "save": rewrite current sector 

savetodisk proc
    mov dx, offset writetodiskmsg
    call printbottom
    call writecursect
    jc @F
    mov dx, offset donewritedisk
    call nuprinterror
@@:
    ret
savetodisk endp

;--- submenu functions, menu item "restrict"

restrictsectors proc
    mov dx, offset abmsg                  ; "above/below"?
    call printbottom
rsgetkeys:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je done
    or al, 20h
    cmp al, 'a'
    je restrictabove
    cmp al, 'b'
    jne rsgetkeys
restrictbelow:
    mov eax, [dwCurSector]              ; set the current sector as the
    mov [dwDataend], eax                ; last sector of the drive
    ret
restrictabove:
    mov dx, offset plmsg                ; "physical/logical?"
    call printbottom
rsgetkeys2:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je done
    or al,20h
    mov dl, DT_PHYSICAL
    cmp al, 'p'
    je donesetpl
    cmp al, 'l'
    jne rsgetkeys2
mountdrive::                            ; <--- mount [dwCurSector] as boot sector of new logical drive
    mov dl, DT_LOGICAL
donesetpl:
    mov [ioreq.drvtype], dl
    mov eax, [dwCurSector]              ; set the current sector as the
    add [dwDrivestart], eax             ; first sector; this is added to
    sub [dwDataend], eax                ; [dwCurSector] for r/w, so adjust the
    xor eax, eax                        ; final sector accordingly
    mov [dwCurSector], eax
    call setvariables
done:
    ret
restrictsectors endp

;--- submenu "functions"

submenu_functions proc

    @mstart funcmenu
    @mitem 30, restrictsectors
    @mitem 29, submenu_fill
if ?EXT
    @mitem -2, unformat, funcmf3    ; "unformat"
    @mitem -2, undelete, funcmf4    ; "undelete"
endif
    @mend funcmenu

    mov al, -2
    cmp [filesys], FS_EXFAT       ; no "undelete" for exFAT!
    jz @F
    test [filesys], FS_FATXX
    jz @F
    mov al, MENUF_UNFORMAT
@@:
    mov [funcmf3], al             ; set/remove "unformat"
    mov dx, funcmenu + lfuncmenu shl 8
    mov cl, 3
    jmp pushmenustack

submenu_functions endp

if ?EXT
;------------------------------------------------------
    include UNDELETE.INC
;------------------------------------------------------
    include UNFORMAT.INC
;------------------------------------------------------
endif

;--- submenu "fill" in submenu "functions"

submenu_fill proc

    @mstart fillmenu
    @mitem 28, fillhex
    @mitem 27, fillstring
    @mitem 32, fillincr
    @mitem 33, filldecr
    @mitem 42, fillinverse
    @mitem 34, fillrandom
    @mend fillmenu

    mov dx, fillmenu + lfillmenu shl 8
    mov cl, 3
    jmp pushmenustack

fillincr:
    mov [fillflag+1], FL_INCREMENT
    jmp submenu_incdec
filldecr:
    mov [fillflag+1], FL_DECREMENT
    jmp submenu_incdec
fillinverse:
    mov [fillflag], FL_INVERSE
    jmp fillinvrand
fillrandom:
    mov [fillflag], FL_RANDOM
    jmp fillinvrand

submenu_fill endp

;--- items "decremental", "incremental" of submenu "fill"

submenu_incdec proc

    @mstart incdecmenu
    @mitem 35, fillbit8
    @mitem 36, fillbit12
    @mitem 37, fillbit16
    @mitem 38, fillbit32
    @mend incdecmenu

    mov dx, incdecmenu + lincdecmenu shl 8
    mov cl, 3
    jmp pushmenustack

fillbit8:
    mov [fillflag], FL_BIT8
    mov cl, 0FFh
    movzx ecx, cl
    jmp fillamount
fillbit12:
    mov [fillflag], FL_BIT12
    mov cx, 0FFFh                         ; ECX=0FFFh
    movzx ecx, cx
    jmp fillamount
fillbit16:
    mov [fillflag], FL_BIT16
    mov cx, 0FFFFh                          ; ECX=0FFFFh
    movzx ecx, cx
    jmp fillamount
fillbit32:
    mov [fillflag], FL_BIT32
    mov ecx, 0FFFFFFFFh
    jmp fillamount

submenu_incdec endp

;--- fill region with 8,12,16 or 32 bit value.
;--- in: ecx=0FF, 0FFF, 0FFFF or 0FFFFFFFF0
;--- [fillflag]: 8/12/16/32/RANDOM/INVERSE
;--- [fillflag+1]: INC/DEC

fillamount proc

    mov dx, offset szHex
    mov eax, ecx
    call gethexvalue                    ; get hex value in ebx
    jc exit

;---

fillinvrand::                           ;<--- entry for RANDOM/INVERSE
    call getnos                         ; get number of sectors in [dwValue]
    jc exit
    mov dx, offset writetodiskmsg
    call printbottom
    mov eax, ebx
    push ds
    pop es

    push [dwCurSector]
    pop [ioreq.dwSector]

    mov di, offset sectbuffer
    call setfilllen

keeprandomfill:                         ; <--- next "block"
    mov cx, bp
    mov bl,[fillflag]

    cmp bl, FL_BIT12
    je do12fill
    cmp bl, FL_BIT8                     ; writing byte at a time?
    je dontshift                        ; then dont divide by 2
    shr cx, 1                           ; divide by 2 to write words
    cmp bl, FL_BIT16                    ; if we're writing 32-bits at a time
    je dontshift
    shr cx, 1                           ; divide by 2 again
dontshift:
    cmp bl, FL_INVERSE
    jne randomloop                      ; inverse function requires reading
    mov si, di                          ; every sector to reverse that data

;--- todo: optimize the "sector restriction" thing

    movzx eax, [dapacket.sectors]
    cmp eax, [dwValue]
    jbe @F
    mov ax, word ptr [dwValue]
    mov [dapacket.sectors], ax
    mov [drivepacket.sectors], ax
@@:
    call diskaccess_read
    jc fillerror
    push ds
    pop es
randomloop:                             ; <--- next byte/word/dword
    cmp bl, FL_INVERSE
    jne @F
    lodsd                               ; reverse a dword at a time
    not eax
    jmp continuerandinv
@@:
    cmp bl, FL_RANDOM
    jne continuerandinv
    push cx
    push bx
    call rand                           ; generate random value (eax)
    pop bx
    pop cx
continuerandinv:
    cmp bl, FL_BIT16
    je fill16bit
    cmp bl, FL_BIT8
    je fill8bit
    stosd
    jmp doriloop
fill8bit:
    stosb
    jmp doriloop
fill16bit:
    stosw
doriloop:
    movsx edx,[fillflag+1]
    add eax, edx
    loop randomloop

    call fillcommon             ; preserves EAX!
    jc fillerror
    jnz keeprandomfill
    jmp done

;--- 12-bit fill. 

do12fill:
    stosb
    loop @F                     ; ran out of bytes to this sector?
    call fillcommon
    jc fillerror
    jz done
    mov cx, bp
@@:
    mov bh, ah                  ; save cur bits 8-11 in BH
    and bh, 0Fh
    movsx dx,[fillflag+1]
    add ax, dx
    mov dx, ax                  ; save next bits 0-11 in DX
    shl al, 4                   ; store next bits 0-3 in hinib AL
    or al, bh                   ; store cur bits 8-11 in lonib AL
    stosb                       ; store cur[8-11] and next[0-3]
    loop @F
    call fillcommon
    jc fillerror
    jz done
    mov cx, bp
@@:
    mov ax, dx
    shr ax, 4                   ;get next 4-11 in AL
    stosb                       ;stored. DX contain nothing anymore
    loop @F
    call fillcommon
    jc fillerror
    jz done
    mov cx, bp
@@:
    mov ax, dx
    movsx dx,[fillflag+1]
    add ax, dx
    jmp do12fill

;--- done/fillerror

fillerror:
done:
    pushf
    mov [dapacket.sectors],1
    mov [drivepacket.sectors],1
    call readcursect
    popf
    jc exit
    call updatescreen           ; let the user see how it looks like
    mov dx, offset donewritedisk
    call nuprinterror
exit:
    ret

setfilllen:
    mov bp, [wBps]
    mov ax, sizeof sectbuffer
    xor dx, dx
    div bp
    and dx, dx
    jnz @F
    mov [drivepacket.sectors], ax
    mov [dapacket.sectors], ax
    mov bp, sizeof sectbuffer
@@:
    ret

;--- menu item "hex" of submenu "fill"

fillhex::
    call gethexstring     ;fills stringbuffer
    jnc dofill
    ret

;--- menu item "string" of submenu "fill"

fillstring::
    call getstringprompt
dofill:                               ; <--- entry "fill hex"
    jcxz exit
    mov [stringlen], cx
    call getnos                       ; get number of sectors in [dwValue]
    jc exit

;--- here string in stringbuffer, size in CX

    mov si, offset stringbuffer
    mov di, si
    add di, cx

;--- 1. get in cx a multiple of the string len that still fits in string buffer
    mov ax, sizeof stringbuffer
    cwd
    div cx
    mov dx, cx
    imul cx, ax

;--- 2. repeat string in buffer

    push cx
    sub cx, dx
    push ds
    pop es
    rep movsb
    pop cx

    push [dwCurSector]
    pop [ioreq.dwSector]

    push ds
    pop es
    mov di, offset sectbuffer

    call setfilllen   ; adjust sector buffer length for the fill op (returned in BP)
    mov ax, bp
    mov dx, cx        ; save stringbuffer length in DX
kfi:                  ; <--- new string copy op
    mov si, offset stringbuffer
    mov cx, dx
    cmp ax, cx        ; 3. check if enough space in sector buffer for a full copy
    jc @F
    rep movsb         ; yes, just copy
    sub ax, dx
    jmp kfi           ; and restart
@@:
    xchg cx, ax       ; no, copy until sector buffer end
    sub ax, cx
    rep movsb
    mov cx, ax        ; hold in cx what remains in string buffer
    call fillcommon   ; buffer copied, so write to disk, check ESC, print progress
    jbe @F            ; C:error, Z:dwValue==zero
    mov ax, bp
    sub ax, cx
    rep movsb         ; 4. copy the rest of string buffer to cleaned sector buffer
    jmp kfi           ; and restart
@@:
    mov si, [stringlen] ; don't change flags in next lines
    lea si, [si + offset stringbuffer]
    mov byte ptr [si], 0;clean multiples from string buffer, so it can be edited
    jmp done

fillamount endp

;--- this routine must not modify EAX, CX or DX!
;--- decrements [dwValue] (=number of sectors)
;--- out: C if ESC pressed or error
;---      Z set if no more sectors to fill

fillcommon proc
    push eax
    movzx eax, [dapacket.sectors]
    sub [dwValue], eax
    jnc @F
    add eax, [dwValue]
    mov [dapacket.sectors], ax
    mov [drivepacket.sectors], ax
    mov [dwValue], 0
@@:
    pop eax
    call writesect
    jc error
    cmp [dwValue], 0
    jz done

    call checktime
    jc @F
    call checkabort
    je abort
    push eax
    push cx
    mov eax, [dwValue]
    mov cx, offset writetodiskmsg
    call printprogress
    pop cx
    pop eax
@@:
    movzx edi, [dapacket.sectors]
    add [ioreq.dwSector], edi
    push ds
    pop es
    mov di, offset sectbuffer
    or di,di                      ; clear zero flag!
done:
    clc
    ret
abort:
    mov dx, offset abortdmsg      ; "abort writing to disk"
    call printerror
error:
    stc
    ret
fillcommon endp

;--- write bottom line in a lengthy operation
;--- in:  EAX = remaining sectors
;---       CX = operation string ("restoring", "searching", "writing",...)
;--- all registers preserved ( sprintf leaves them all intact)

printprogress:
    push dx
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("%s (sector %lu, remaining %lu)"), cx, [ioreq.dwSector], eax
    call printbottom
    pop dx
    ret

;--- main menu tab & shift-tab keys

changemode proc
  cmp al, 0                     ; shift+tab?
  je @F
  xor [editmode], EM_ASCII      ; switch between ascii/regular editing
  call colorchar
  ret
@@:
  xor [displaymode], DM_BINARY  ; switch between hex/binary editing
  call clearsecarea
  xor dl, dl                    ; reset bHL
  mov ax, [spot]
  call movecursor
  ret
changemode endp

;--- main menu ctrl-up

jumpstkpop proc
    call popsecstack            ; pop saved sector# from sector stack
    ret
jumpstkpop endp

;--- handle ctrl-enter key
;--- jump to cluster entry in FAT

handle_ctlenter proc

    test [filesys], FS_FATXX    ; must be a FAT drive
    je done
    mov eax, [dwCurSector]
    test eax, eax
    jz log2phys

    test [bRegion], RG_DATA
    jz done

;retcluster:
    call pushsecstack           ; push sector# in eax onto sector stack
    call sector2cluster         ; convert sector# to cluster#
    call go2entry               ; convert cluster# to [ioreq.dwSector] + [spot] (location inside FAT)
    call readsect               ; read FAT sector set by go2entry
done:
    ret

;--- if we're on a logical drive, attempt
;--- to jump to respective phys. drive.
;--- won't work for ramdisks - also, the HD number in 
;--- the boot sector is generally a rather unreliable info.
log2phys:
    mov al, [hdnumber]
    and al, al
    jz @F
    mov bh, DT_PHYSICAL
    call trydevice
;    jnc drive_ok
    jc @F
    call setvariables           ; set all obtainable parameter variables
@@:
    ret

handle_ctlenter endp

;--- push/pop items on/from sector stack

popsecstack proc
    push bx
    movzx bx, [secstk_top]
    dec bl
    and bl, 7
    shl bx, 3
    xor eax, eax
    xchg eax, [bx][secstk].dwSector
    cmp eax, 0
    jz done
    dec [secstk_top]
    mov [ioreq.dwSector], eax
    call readsect
    mov ax, [bx][secstk].wSpot
    mov dl, 0
    call movecursor
done:
    pop bx
    ret
popsecstack endp

pushsecstack proc
    push bx
    push ax
    movzx bx, [secstk_top]
    and bl, 7
    shl bx, 3
    mov [bx][secstk].dwSector, eax
    mov ax, [spot]
    mov [bx][secstk].wSpot, ax
    inc [secstk_top]
    pop ax
    pop bx
    ret
pushsecstack endp

;--- main menu ctrl-left

recursechain proc
    cmp [bRegion], RG_FAT               ; must be in FAT region
    jne done

    call getcurrententry                ; get ebx = current entry number
    cmp ebx, 2                          ; starting (2nd) cluster?
    jbe done                            ; no where to recurse from
    mov eax, ebx

;--- the old code assumed that the cluster that we search and that links to the
;--- current one is "below" ( hence it starts decrementing from the current
;--- cluster# ). This assumption was incorrect.

    mov edi,-1                          ; begin with decending from current entry#
    mov cx, CStr("descending")
nextentry:
    call checktime
    jc @F
    call checkabort
    je done
    push eax
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset recursemsg, cx, eax, [dwLastCluster]
    call printbottom
    pop eax
@@:
    add eax, edi                        ; go back/forward one fat entry
    cmp eax, 2                          ; past first entry in fat?
    jb loop_done
    cmp eax, [dwLastCluster]            ; past last entry in fat?
    ja chainnotfound

    push eax
    call getfatentry                    ; read the fat entry in EAX
    cmp ebx, eax                        ; match the one we want?
    pop eax
    je dochainjump                      ; found

    jmp nextentry                       ; no...keep recursing

loop_done:
    mov edi, 1                          ; no predecessor found "below"
    mov eax, ebx                        ; so the region "above" is to be scanned
    mov cx, CStr("ascending")
    jmp nextentry

chainnotfound:
    mov dx, offset nochainmsg           ; "recursive link not found"
    call printerror
done:
    ret
recursechain endp

;--- main menu ctrl-right key
;--- if in FAT, jump to linked (=next) cluster in chain
;--- if in data region, jump to linked cluster in FAT

;--- for exFAT, it might be that the FAT entry is NULL -
;--- this usually means that the file is stored contiguous;
;--- and the successor ( if one exists ) is then the next cluster#.
;--- problem is that WDe doesn't know the file size and hence
;--- can't tell when the end is reached.

jumpcluster proc

    cmp [bRegion], RG_FAT
    je jumpfatcluster
    test [bRegion], RG_DATA
    jz done
;jumpdatacluster:
    mov eax, [dwCurSector]
    mov [fromfat], 1
    call sector2cluster                 ; get respective cluster number
    call getfatentry                    ; read fat entry
    jc done
    mov dx, offset endofchainmsg
    cmp eax, 0fffffffh
    jz nuprinterror
    jmp setcluster                      ; set the cluster# read from FAT
;-------------------------------------------------------
jumpfatcluster:

    call getcurrententry

dochainjump::             ; <--- for recurse ( Ctrl-left in FAT )

    cmp eax, 2            ; disregard ebx, which is the current entry #
    jb done               ; we only care about eax, the value stored there.
;    cmp eax, 0FFFFFF7h
;    jae done

    cmp eax, [dwLastCluster]
    ja done
    call go2entry                 ; will set [dwCurSector] + [spot]=0
    mov eax, [dwCurSector]
    cmp eax, [ioreq.dwSector]
    jz done
    call readsect                 ; read the sector set by go2entry
done:
    ret
jumpcluster endp

;--- display error msg "invalid cluster # xxx"
;--- in: ebx=cluster# to display

invalclusterror proc
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset invalclustmsg, ebx
    jmp nuprinterror
invalclusterror endp

;--- handle ctrl-key ENTER
;--- in FAT area: jump to data area of cluster at current offset
;--- in DIR area: jump to starting cluster of dir entry

handle_enter proc

    test [filesys], FS_FATXX            ; FAT disk?
    je done

    cmp [viewmode], VM_DIRECTORY
    je do_direntry

    cmp [bRegion], RG_FAT
    jne done

    call getentrynumber                 ; get the cluster number for [dwCurSector][spot]

;--- set cluster# in eax and store current sector in sector stack,
;--- reset spot to 0.

setcluster::                            ; <--- used by various code
    mov ebx, eax
    call cluster2sector                 ; multiply it out to get the
    cmp eax, [dwDataend]                ; corresponding sector number
    ja invalclusterror                  ; verify that it's a valid sector
    mov [ioreq.dwSector], eax

    cmp eax,[dwCurSector]               ; don't store if sectors are identical.
    jz @F                               ; (will happen for "." entries, for example.
    mov eax,[dwCurSector]               ; store current sector onto stack.
    call pushsecstack                   ; push sector# in eax onto sector stack
@@:
    call readsect
    mov ax,0
    mov dl,0
    call movecursor
done:
    ret

do_direntry:

;--- get the cluster# of the dir entry

    call bufferinsi
    mov bx, [spot]
    and bl, 11100000b

    cmp [filesys], FS_EXFAT                    ; exFAT direntry structure?
    jz exfat_enter

    cmp byte ptr [si+bx+DIR_ATTRIBUTES], 0Fh   ; lfn entry?
    jz done
    mov ax, word ptr [si+bx+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [si+bx+DIR_CLUST_LOW]

    cmp eax, 2
;--- jump to root directory if cluster# invalid?
;--- not generally, only if name of entry is ".."
;    jb jumptoroot
    jae setcluster
    cmp dword ptr [si+bx],"  .."
    jz jumptoroot
    ret

exfat_enter:
    mov al, [si+bx].EXFDIRP.etype
    test al, 80h
    jz done
    test al, 40h
    jz isprim
    test [si+bx].EXFDIRS.secflgs, EXFPF_CLSDEFINED
    jz done
@@:
    mov eax, [si+bx].EXFDIRS.dwFirstCl
    jmp setcluster
isprim:
    and al, 1Fh
    cmp al, EXFPTC_ALLOCBM
    jz @B
    cmp al, EXFPTC_UPCASET
    jz @B
    ret

handle_enter endp

;--- submenu view

submenu_view proc

    @mstart viewmenu
    @mitem 25, autoview
    @mitem 17, specview
    @mitem  8, specview
    @mitem 39, specview
    @mitem 40, specview
    @mitem 41, specview
    @mitem 26, specview
    @mend viewmenu

    mov dx, viewmenu + lviewmenu shl 8
    mov cl, 2
    jmp pushmenustack

specview:
    sub ah, F1_KEY
    mov dl, ah
    cmp dl, VM_FAT12
    jne @F
    mov eax, [dwCurSector]
    mov [dwFat12start], eax
@@:
    mov [viewmode2], VM2_STATIC
    call checksetview  ;set viewmode to DL
    ret
;-------------------------------------------------------
autoview:
    mov [viewmode2], VM2_AUTODETECT
    ret
submenu_view endp

;--- submenu "find": "string hex next MBR boot sector, FAT, directory,..."

submenu_find proc

    @mstart searchmenu
    @mitem 27, findstring
    @mitem 28, findhex
    @mitem 43, findnext
    @mitem 17, findmbr
    @mitem  8, findbs
    @mitem 31, findfat
    @mitem 26, finddir
    @mend searchmenu

    mov [handling], QUERY_SKIP    ; inside submenu_find (useless to do here)
    mov dx, searchmenu + lsearchmenu shl 8
    mov cl, 2
    jmp pushmenustack

;--- find directory entries

finddir:
    call bufferinsi
@@:
    call IsDirectory    ; scan if a dir entry is found in buffer
    jnc doneX
    call findcommon     ; get next (sub)sector, will set SI
    jmp @B
doneX:
    ret

;--- find boot sector

findbs:
    call bufferinsi
findbsnext:
    cmp dword ptr [si+1fch], 0AA550000h           ; check for boot sig ++
    jne findbs2
    cmp byte ptr [si], 0EBh                       ; check for jmp
    je doneX
findbs2:
    call findcommon           ; get next (sub)sector, will set SI
    jmp findbsnext

;--- find FAT
;
; This function is slightly bugged; the first byte is a media descriptor
; byte and only makes the partition more likely to be a certain type of
; fat.  Fat finding should only verify that the first byte is a valid
; media descriptor and then attempt to identify the fat type.
;
findfat:
    call bufferinsi
findfatnext:                      ; <---- next sector?
if 1
    xor bx, bx                    ; 14.4.2022: TEST, just to ensure that BX has a defined value
endif
    cmp byte ptr [si], 0F0h       ; fat12
    je n12sfl                     ; 14.4.2022: TEST, n12sfl expects BX to be set up!
    cmp byte ptr [si], 0F8h       ; fat16/fat32
    jne findfat2
fatok:
    mov bx, 3
    cmp byte ptr [si+bx], 0Fh     ; fat32
    jne if16

  ; likely fat32

lfatloop:
    add bx, 4
    test byte ptr [si+bx], 0F0h   ; highest nibble on fat32 shouldn't
    jnz findfat2                  ; be anything but 0000b
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
    je doneX
findfat2:
    call findcommon                     ; get next (sub)sector, will set SI
    jmp findfatnext

;--- find MBR

findmbr:
    call bufferinsi
findmbrnext:
    cmp byte ptr [si], 0EBh
    je findmbr2
    cmp dword ptr [si+1fch], 0AA550000h ; mbr signature
    jne findmbr2
    cmp dword ptr [si+1e4h], 061417272h ; fsinfo sector signature
    je findmbr2                         ; annoying of microsoft to
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

    cmp al, 1                           ; more than one active partition?
    je doneX                            ; no, MBR found.

findmbr2:
    call findcommon                     ; get next (sub)sector, will set SI
    jmp findmbrnext

;--- find next occurence of (hex) string

findnext:
    mov al, 1
    mov cx, [stringlen]
    and cx, cx
    jnz stringsearch
    mov dx, offset nosearchstring
    jmp nuprinterror

findstring:
    call getstringprompt
    jmp findstring_hs
findhex:
    call gethexstring   ;fills stringbuffer
    jc @F
findstring_hs:
    xor al, al
    test cx, cx
    jnz stringsearch
@@:
    ret

submenu_find endp

;--- print line 0, sector area, view area

updatescreen proc

    call printtopline
    cmp [wBps], VIEWBYTES             ; in case the sector doesn't exactly fit on the screen, update offset
    jz @F
    call printoffset
@@:
    call printsector

    cmp [viewmode2], VM2_STATIC       ; forced view?
    je updateview

;--- detect the view type

    mov dl, [bRegion]
    test dl, RG_RESERVED or RG_FAT or RG_ROOT or RG_DATA  ; known region?
    jz setDLview                      ; if no, assume lower bits define view (MBR or default)
    cmp dl, RG_FAT
    je choosefatview
    test dl, RG_ROOT                  ; root can also be a data area
    jnz setdirview

    cmp dl, RG_DATA
    jne @F
    call bufferinsi                   ; check if it's a directory
    call IsDirectory
    jnc setdirview
    jmp setdataview
@@:
    cmp dl, RG_RESERVED
    jne setdataview
    cmp [dwCurSector], 0
    je setbsview
    movzx eax, [backupbs]
    cmp [dwCurSector], eax
    je setbsview
    movzx edx, [fsinfo]
    cmp [dwCurSector], edx            ; in the fsinfo sector?
    je setfsview                      ; then set fsinfo view
    add edx, eax                      ; checks if we're in the backup
    cmp [dwCurSector], edx               ; fsinfo sector...but it assumes
    je setfsview                      ; it's the same distance from the backupbs
setdataview:
    mov dl, VM_DATA                   ; as the main fsinfo is the main
    jmp setDLview                     ; bootsector, which is wrong.
setdirview:
    mov dl, VM_DIRECTORY
    jmp setDLview
setbsview:
    mov dl, VM_BOOTSECTOR
    jmp setDLview
setfsview:
    mov dl, VM_FSINFO
    jmp setDLview
;-------------------------------------------------------
choosefatview:
    mov dl, VM_FAT32
    test [filesys], FS_FAT32
    jnz setDLview
    mov dl, VM_FAT16
    cmp [filesys], FS_FAT16
    je setDLview
    mov dl, VM_FAT12

    mov eax, [dwReserved]
    add eax, [dwSpF]
    cmp eax, [dwCurSector]
    jbe @F
    sub eax, [dwSpF]
@@:
    mov [dwFat12start], eax
setDLview:
    call checksetview                 ; set viewmode to DL
    jmp updateview

updatescreen endp

;--- IN: [stringbuffer]: search string
;---      CX: size of string
;---      AL: 0=normal start, 1=find next ( skips byte at spot pos )
;--- search starts at cursor pos of current sector

stringsearch proc

    push [dwCurSector]
    pop [ioreq.dwSector]

    call spot2bufofs                    ; bx = sectofs + spot

    mov si, offset stringbuffer
    mov di, offset sectbuffer
    mov dx, [wBps]
    add dx, di
    mov [stringlen], cx                 ; save length
    add di, bx

    call findreadreset

;--- about timings: this compare version uses "repnz scasb"
;--- and "repz cmpsb". This avoids hand-coded loops and thus may make
;--- code easier to understand, but one shouldn't expect speed advantages on
;--- "modern" cpus. On the contrary, execution time may be slightly slower.
;--- Another problem with those repeated scans and compares is that they tend
;--- to behave "unexpected" if they run with cx=0.

    @getstarttime

    push ds
    pop es
    cmp al,1
    jnz nextbyte
    lodsb
    inc di
    cmp di, dx
    jz nexts
    jmp @F
nextbyte:
    lodsb
@@:
    mov cx, dx
    sub cx, di
    repnz scasb
    je comparestring
nexts:
    call getnextsector              ; read next sector, NOT in string compare op
    mov al, [si-1]
    jmp @B
comparestring:                      ; ok, first chars do match
    mov ax, [stringlen]
    dec ax
    jz stringfound                  ; done if string is just 1 char
    cmp di, dx
    jnz maybesplit
    mov cx, ax
    call getnextsector
    mov bx, di
    repz cmpsb
    jz stringfound
    mov di, bx                      ; not matching. this case is without sector bounds crossing
    mov si, offset stringbuffer     ; just restore DI and reset SI
    jmp nextbyte

maybesplit:
    mov bx, di
    cmp cx, ax                      ; check if there's enough space in sector
    jb splitcompare
    mov cx, ax                      ; yes, use stringlen-1 to compare
    repz cmpsb
    jz stringfound
noboundcross:
    mov di, bx                      ; not matching. this case is without sector bounds crossing
    mov si, offset stringbuffer     ; just restore DI and reset SI
    jmp nextbyte

splitcompare:
    mov bp, cx
    sub ax, cx                      ; remember in AX what's left to compare
    repz cmpsb                      ; compare the first part
    jnz noboundcross
    mov cx, ax                      ; fill cx with the rest len to compare
    call getnextsector
    repz cmpsb                      ; and compare the second part ( no search string may cross 2 sector boundaries! )
    jz stringfound2
;--- a sector boundary has been crossed during compare.
;--- we don't want to "reread" the old sector.
    mov si, offset stringbuffer     ; reset SI
    lea di, [si+1]
    lea dx, [di+bp]
    jmp nextbyte                    ; and restart the compare...

stringfound2:                       ; string found, sector border crossed
stringfound:
    call findreadreset              ; reset io to default ( 1 sector )
    sub di, [stringlen]
    sub di, offset sectbuffer
    jnc @F                          ; C if the found string began in the previous sector
    add di, [wBps]
    dec [ioreq.dwSector]            ; just read it, don't care about the cache anymore!
    call diskaccess_read
    jmp sx1
@@:
    mov ax, di
    mov cl, [bSecSh]
    shr ax, cl
    call findreadadjust             ; expects sec# in AL
    movzx eax, ax
    add eax, [ioreq.dwSector]
    mov [dwCurSector], eax
sx1:
;--- set sector offset
    mov ax, 1
    mov cl, [bSecSh]
    shl ax, cl
    dec ax
    xor ax, VIEWBYTES - 1
    and ax, di
    mov [sectofs], ax

;--- set spot
    mov ax, di
    and ax, VIEWBYTES - 1
    mov dl,0
    call movecursor
    ret

getnextsector:
    cmp di, offset sectbuffer      ; is current "buffer" not inside sectbuffer?
    jb @F                          ; then we did just compare inside the search string
    call findreadnext
    jc abort

    call checktime
    jc @F
    call checkabort
    je abort
    push es
    push cx
    mov eax, [dwDataend]
    sub eax, [ioreq.dwSector]
    mov cx, offset searchingmsg
    call printprogress
    pop cx
    pop es
@@:
    mov di, offset sectbuffer      ; return DI pointing to the first sector read
    mov dx, [dapacket.sectors]     ; and DX points to end of sectors
    push cx
    mov cl, [bSecSh]
    shl dx, cl
    add dx, di
    pop cx
    ret

;	@dprintf "programming error in searchstring, di=%X dx=%X sector=%lu", di, dx, [ioreq.dwSector]
;	ret

stringnotfound:
    pop ax
    @printtime "stringsearch; duration %lu ms"
    mov dx, offset searcherror    ; "no (nore) matches found"
    call nuprinterror
abort:
    pop ax                        ; skip "getnextsector" caller address
    call findreadreset
    call readcursect
    ret

;--- since stringsearch reads just forward now, 
;--- a small cache is implemented ( consists of just the 4 kB sector buffer ).
;--- this improves speed significantly.

findreadnext:
    mov eax, [dwDataend]           ; how many sectors exist until end?
    inc eax
    movzx edx, [dapacket.sectors]
    add [ioreq.dwSector], edx
    add edx, [ioreq.dwSector]
    cmp edx, eax
    jae stringnotfound
    sub eax, edx

    push cx
    mov cl, BUFFSHIFT
    sub cl, [bSecSh]
    mov dl, 1
    shl dl, cl
    pop cx
    movzx edx, dl

    cmp eax, edx
    jb @F
    mov ax, dx
@@:
    cmp [bSecSh], 0
    je diskaccess_read
    mov [dapacket.sectors], ax
    mov [drivepacket.sectors], ax
    call diskaccess_read
    ret

findreadreset:
    mov [dapacket.sectors], 1
    mov [drivepacket.sectors], 1
    ret

findreadadjust:
;--- string has been found. Since we don't bother to copy sector
;--- contents around ( just DI is adjusted ), we have to copy the
;--- content now to the start of sectbuffer.
    pusha
    mov di, offset sectbuffer
    mov si, di
    mov cl, [bSecSh]
    shl ax, cl
    add si, ax
    mov cx, [wBps]
    push ds
    pop es
    rep movsb
@@:
    popa
    ret

stringsearch endp

;--- common routine for find directory/boot sector/fat/mbr cmds
;--- out: SI=current 512-chunk of sector

findcommon proc

;    mov dx, offset searchingmsg
;    call printbottom

    call checktime
    jc @F
    call checkabort
    je abort                  ; pop address, update screen, then RET
    mov eax, [dwDataend]
    sub eax, [ioreq.dwSector]
    mov cx, offset searchingmsg
    call printprogress
@@:

    mov ax, [wBps]            ; reached end of physical sector?
    sub ax, VIEWBYTES
    cmp [sectofs], ax
    jb dontrw
    mov eax, [ioreq.dwSector] ; check if end of disk has been reached
    inc eax
    cmp eax, [dwDataend]
    ja notfound
    mov [ioreq.dwSector], eax ; not yet, try to read next sector
    call diskaccess_read
    jc abort
    mov [sectofs], 0
    jmp dontinc
dontrw:
    add [sectofs], VIEWBYTES
dontinc:
    call bufferinsi
    ret

notfound:
    mov dx, offset searcherror ; "no (more) matches found"
    call nuprinterror
abort:
    call readcursect
    add sp, 2                  ; skip caller's return address, will jump to main
    ret
findcommon endp

;--- file submenu

submenu_file proc

    @mstart filemenu               ; file menu cmd table
    @mitem 14, submenu_fileoptions
    @mitem 15, submenu_fileoptions, filemenu_restore
    @mitem  6, select_disk
    @mend filemenu

    mov al, MENUF_RESTORE
    cmp [ioreq.drvtype], DT_CDROM
    jne @F
    mov al,-2                      ; for CDROMs, remove "restore"
@@:
    mov [filemenu_restore], al
    mov dx, filemenu + lfilemenu shl 8
    mov cl, 3
    jmp pushmenustack

submenu_file endp

;--- this routine is called by getstring()
;--- ax=start of string buffer

getexfatname proc
    pusha
    push ds
    pop es
    mov di, ax
    mov bp, ax
    call bufferinsi
    mov bx,[spot]
    and bl, 11100000b
    add bx, DIRENTSIZE
    mov cx, sizeof filenamebuffer
nextchar:
    test bl, 1Fh
    jnz @F
    cmp bx, [wBps]
    jae done
    cmp byte ptr [si+bx], EXFSTCF_NAME
    jnz done
    add bx, 2
@@:
    mov ax, [si+bx]
    add bx, 2
    stosb
    and ax, ax
    loopnz nextchar
done:
    mov byte ptr [di], 0   ; the last char must be 0
    popa
    ret
getexfatname endp

;--- this routine is called by getstring()
;--- ax=start of string buffer

getfatxname proc
    pusha
    push ds
    pop es
    mov di, ax
    mov bp, ax
    call bufferinsi
    mov bx,[spot]
    and bl, 11100000b
    mov cx, 8
@@:
    mov al, [si+bx]
    cmp al, SPACE
    jz @F
    stosb
    inc bx
    loop @B
@@:
    add bx, cx
    mov al,[si+bx]
    cmp al,' '
    jz done
    mov al,'.'
    stosb
    mov cl,3
@@:
    mov al,[si+bx]
    cmp al, SPACE
    jz done
    stosb
    inc bx
    loop @B
done:
    mov byte ptr [di], 0   ; the last char must be 0
    popa
    ret
getfatxname endp

;--- submenu file options, key F7
;--- IN: [chainflag] = FAT_CHAIN or FILE_CHAIN

savechain proc
    mov [fromfat], 1
    mov [bSkipFat], 0
    xor ebp, ebp
    cmp [chainflag], FAT_CHAIN
    je beginfatchainsave

;--- we're in a directory and are to save a file chain

    call bufferinsi
    mov bx,[spot]
    and bl, 11100000b                       ; chop off 0-31 bytes to set bx to

    cmp [filesys], FS_EXFAT
    jz exfat_savechain

    mov eax, dword ptr [si+bx+DIR_FILESIZE] ; filesize
    mov [dwFilesize], eax
    mov ax, word ptr [si+bx+DIR_CLUST_HIGH] ; high cluster word
    shl eax, 16
    mov ax, word ptr [si+bx+DIR_CLUST_LOW]  ; low cluster word

savefilechain:                              ; <- common for both FATxx and exFAT file chain
    mov [dwSecBackup], eax                  ; back the cluster number up
    push eax
    mov ax, deliverfn
    call getfilename
    pop eax
    jcxz done                               ; cx=0 if user has ESCaped
    call cluster2sector                     ; returns -1 if outside of valid cluster range
    cmp eax, [dwDataend]
    ja invalclust
    call getnextcluster
    jmp startchainsaving

deliverfn:
    cmp [filesys], FS_EXFAT
    jnz @F
    call getexfatname
    xor ax, ax
    ret
@@:
    call getfatxname
    clc
    ret

invalclust:
    mov dx, offset invalstartclust          ; "invalid start cluster"
    call printerror
done:
    ret

exfat_savechain:
    mov eax, [si+bx].EXFDIRS.dwFirstCl
    mov ecx, dword ptr [si+bx].EXFDIRS.dqSize+0
    mov [dwFilesize], ecx
    test [si+bx].EXFDIRS.secflgs, EXFPF_NOCHAIN
    jz savefilechain

;--- the file has NO fat chain.
;--- hence the number of clusters to save must be calculated

    mov [bSkipFat], 1   ; don't use fat to get next cluster#
    push eax
    push ecx
    movzx eax, [wBps]
    mov cl, [bSpCshift]
    shl eax, cl         ; eax = bytes per cluster
    pop ecx
    xchg eax, ecx       ; eax = filesize, ecx = bytes/cluster
    mov edx, dword ptr [si+bx].EXFDIRS.dqSize+4
    div ecx             ; filesize / bytes per cluster
    and dx,dx
    setnz dl
    movzx edx, dl
    add eax, edx
    mov dwNumCluster, eax
    pop eax
    jmp savefilechain

;--- in a FAT, start saving cluster chain

beginfatchainsave:
    call srcommon
    call getcurrententry                  ; get cluster # from sector+spot info
    mov [dwSecBackup], eax                ; current entry's data
    mov eax, ebx
    call cluster2sector
    cmp eax, [dwDataend]
    ja invalclust                         ; current entry is beyond data end

startchainsaving:
    push ax
    call createfile
    pop ax
    jc done

chainsaveloop:
    movzx ebx, [bSpC]                     ; writefile will write one cluster at a time
    mov [dwValue], ebx
    add ebp, ebx
    mov di, offset mydisp                 ; function address to call inside writefile
    call writefile
    jc done

    mov eax, [dwSecBackup]
    call cluster2sector
    cmp eax, [dwDataend]
    ja donechainsave
    call getnextcluster
    jmp chainsaveloop

getnextcluster:
    push eax
    mov eax, [dwSecBackup]
    cmp [bSkipFat], 0       ; does a fat chain exist
    jz ncfromfat
    inc eax                 ; no, increment cluster#
    dec [dwNumCluster]
    jns dgnc                ; and check if EOF has been reached
    mov eax, -1
    jmp dgnc
ncfromfat:
    call getfatentry        ; get next cluster# from fat chain
dgnc:
    mov [dwSecBackup], eax
    pop eax
    ret

mydisp:
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("Writing file, %lu sectors written, saving cluster %lX..."), ebp, [dwSecBackup]
    jmp printbottom

donechainsave:
    cmp [chainflag], FAT_CHAIN          ; file chain?
    je notruncate

    mov ax, 4201h                       ; then seek from current file position
    mov bx, [wFilehandle]
    xor cx, cx
    xor dx, dx
    int 21h

    shl edx, 16
    mov dx, ax

    cmp edx, [dwFilesize]
    jbe notruncate

    mov dx, offset truncatemsg          ; ask user if file is to be truncated
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

    call readcursect                    ; [dwCurSector] is untouched
    mov eax, ebp
sectorswritten2file::
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset donewritefile, eax
    call nuprinterror
    ret

savechain endp

;--- called from submenu "file options"
;--- restore a cluster chain from a file
;--- IN: [chainflag] = FAT_CHAIN or FILE_CHAIN
;        entry of file in DTA

restorechain proc
    call srcommon               ; calls findfile ( DTA set )

;    mov eax, [dwCurSector]
;    mov [dwSecBackup], eax

    cmp [chainflag], FILE_CHAIN
    jz @F
    call getcurrententry
    mov eax, ebx
    jmp restclusts
@@:
    mov [fromfat], 1
    call bufferinsi
    mov bx, [spot]
    and bl, 11100000b

    cmp [filesys], FS_EXFAT
    jnz @F
    mov eax, [si+bx].EXFDIRSS.dwFirstCl
    test [si+bx].EXFDIRSS.secflgs, EXFPF_NOCHAIN
    jnz exfat_restorechain
    jmp restclusts
@@:
    mov [bSkipFat], 0
if 0                            ; chain is restored even if file isn't big enough
    mov eax, [dwFilesize]
    cmp eax, dword ptr [si+bx+DIR_FILESIZE]
    jb toosmallerr
endif
    mov ax, word ptr [si+bx+DIR_CLUST_HIGH]
    shl eax, 16
    mov ax, word ptr [si+bx+DIR_CLUST_LOW]

restclusts:

    push eax
    call cluster2sector
    cmp eax, [dwDataend]
    ja invalstart

    call openfilero
    pop ecx
    mov dx, offset filenotfound
    jc error
    mov [wFilehandle], ax
    mov eax, ecx

nextcluster:                              ; <--- next cluster
    mov [dwCluster], eax
    call cluster2sector                   ; fix?  checking needed for sector.
    cmp eax, [dwDataend]
    ja clusterr
    mov [ioreq.dwSector], eax
    mov al, [bSpC]
    mov [spcc], al

    call checktime
    jc nextsector

    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("Reading file, writing cluster %lX..."), [dwCluster]
    call printbottom

nextsector:                               ; <--- next sector
    mov ah, 3Fh
    mov bx, [wFilehandle]
    mov cx, [wBps]
    mov dx, [_mem]
    int 21h
    jc disperread
    cmp ax, cx
    je iswholesector

;--- the last bytes of the file don't cover a full sector
;--- so read the current sector into sectbuffer and copy
;--- the missing bytes from sectbuffer to our write buffer.

    call readsect
    jc done
    push ds                               ; preserve bytes at end of sector
    pop es
    sub cx, ax
    mov si, offset sectbuffer
    add si, ax
    mov di, [_mem]
    add di, ax
    rep movsb
iswholesector:
    mov dx, [_mem]
    mov [ioreq.pBuffer], dx
    call writesect
    jc done
    cmp ax, cx                ; EOF reached?
    jne donerestchain

    dec [spcc]
    jz @F
    inc [ioreq.dwSector]
    jmp nextsector
@@:
    mov eax, [dwCluster]
    cmp [bSkipFat], 1         ; get next cluster thru FAT chain?
    jnz @F
    inc eax                   ; no ( it's a contiguous exFAT file )
    dec [dwNumCluster]
    jnz nextcluster
    jmp donerestchain
@@:
    call getfatentry
    cmp eax, 0FFFFFF7h        ; top bits are set even for FAT12/FAT16!
    jb nextcluster            ; end of cluster chain?

donerestchain:

;    mov eax, [dwSecBackup]
;    mov [ioreq.dwSector], eax
    call readcursect
    mov dx, offset donewritedisk
    call printerror
;    mov [menustackidx], 0     ; auto return to main menu
    ret
clusterr:
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr('Invalid Cluster %lX'), [dwCluster]
    call nuprinterror
    ret
invalstart:
    pop eax
invalstart2:
    mov dx, offset invalstartclust          ; "invalid start cluster"
    jmp error
disperread:
    mov dx, offset errorread
error:
    call printerror
done:
    ret

exfat_restorechain:

;--- the exFAT file has NO fat chain.
;--- hence the number of clusters to restore must be calculated

    mov ecx, dword ptr [si+bx].EXFDIRS.dqSize+0
    mov [bSkipFat], 1   ; don't use fat to get next cluster#
    push eax
    push ecx
    movzx eax, [wBps]
    mov cl, [bSpCshift]
    shl eax, cl         ; eax = bytes per cluster
    pop ecx
    xchg eax, ecx       ; eax = filesize, ecx = bytes/cluster
    mov edx, dword ptr [si+bx].EXFDIRS.dqSize+4
    div ecx             ; filesize / bytes per cluster
    and dx,dx
    setnz dl
    movzx edx, dl
    add eax, edx
    mov [dwNumCluster], eax
    pop eax
    jmp restclusts

restorechain endp

;--- common routine for save/restore
;--- 1. prompt user to enter a filename
;--- 2. if "restore"-branch, check if file exists
;--- in case an error occurs, skip caller's return address and return.

srcommon proc
    push ax
    mov ax, sr_ok
    call getfilename
    pop ax
    jcxz srskip               ; cx=0 if user has ESCaped
    cmp [srflag], SR_RESTORE
    jne sr_ok
    call findfileX
    jnc sr_ok
    mov dx, offset filenotfound
    call printerror
srskip:
    add sp,2                  ; skip srcommon return address
sr_ok:
    ret
srcommon endp

;--- submenu "file options"
;--- logical drives: F1=Input F2=Boot F3=Fat1 F4=Fat2 F5=Root F6=Partition [F7=chain]

submenu_fileoptions proc

    @mstart cdfileoptmenu
    @mitem 14, srsecrange
    @mitem 24, dumpiso
    @mend cdfileoptmenu

    @mstart pdfileoptmenu
    @mitem 16, srsecrange
    @mitem 17, srsector0
    @mitem 18, srhdcheck
    @mitem 19, srhdcheck
    @mitem 20, srhdcheck
    @mitem 21, srhdcheck
    @mend pdfileoptmenu


    @mstart ldfileoptmenu
    @mitem 16, srsecrange
    @mitem  8, srsector0
    @mitem 10, srfat1
    @mitem 11, srfat2
    @mitem 12, srroot
    @mitem 22, srdisk
    @mitem -2, srchain, ldfileoptf7 
    @mend ldfileoptmenu

    cmp ah, F2_KEY
    setz [srflag]                  ; set SR_RESTORE for F2, else SR_SAVE

    mov cl, 3
;--- set simple CD menu: F1=save file F2=dump cd as ISO
    mov dx, cdfileoptmenu + lcdfileoptmenu shl 8
    cmp [ioreq.drvtype], DT_CDROM
    je  setxxfileopt

;--- print file option menu for non-CD devices.
;--- for physical devices, just print the corresponding menu

    dec cx                         ; 2 spaces only
;--- set menu "input, MBR, partition1, ..."
    mov dx, pdfileoptmenu + lpdfileoptmenu shl 8
    cmp [ioreq.drvtype], DT_PHYSICAL
    je setxxfileopt

;--- for FAT drives, check if the menu item "chain" is to be added

    mov [chainflag], NO_CHAIN      ; reset chain flag

;--- set menu "input, boot sector, fat1, ..."

    mov dx, ldfileoptmenu + lldfileoptmenu shl 8
    test [filesys], FS_FATXX       ; non-FAT drives?
    jne setxxfileopt
    mov dh, 2                      ; then just allow "sectors" & "boot sector"
setxxfileopt:
    jmp pushmenustack

srsecrange:                        ; save/restore sector range to/from file
    cmp [srflag], SR_RESTORE
    je restsecrange
    jmp savesecrange

srdisk:                            ; save/restore partition to/from file
    cmp [srflag], SR_RESTORE
    je restdrive
    jmp dumpiso

srchain:                           ; save/restore chain to/from file
    cmp [chainflag], NO_CHAIN
    je @F
    cmp [srflag], SR_RESTORE
    je restorechain
    jmp savechain
@@:
    ret

;--- save/restore partition

srhdcheck:                         ; save/restore partition 1-4

    mov bx, 1CAh
    mov cx, 4
    mov al, F3_KEY                 ; F3,F4,F5,F6?
    mov si, offset partitions
@@:
    cmp ah, al
    je srpartition
    inc al
    add bx, 10h
    add si, 4
    loop @B
    ret
srpartition:                       ; SI -> partitions array, BX = offset in MBR for partition
    mov eax, dword ptr [si]
    test eax, eax                  ; "empty" partition?
    jz donesr
    call srcommon

;--- read sector 0

    mov [ioreq.dwSector], 0
    call readsect
    jc donesr
    mov ebx, dword ptr [sectbuffer+bx]   ; get size of partition
    mov [dwValue], ebx
    cmp [srflag], SR_RESTORE
    je endrestsectors
endsavedrive:                      ; <--- by srsecrange, srbs, srfatx, srroot
    call savedata
donesr:
    ret

srroot:                            ; save/restore root dir
    call srcommon
    mov eax, [dwRootSect]
    xor edx, edx
    test [filesys], FS_FAT32
    je @F
    mov dl, [bSpC]                 ; known bug: FAT32 root dir may be more than just 1 cluster!
    jmp dorootsr
@@:
    mov dx, [wRootsectors]
dorootsr:
    mov [dwValue], edx
    cmp [srflag], SR_SAVE
    je endsavedrive
    jmp endrestsectors

restdrive:                         ; restore partition from file
    mov eax, [dwDataend]
    inc eax
    mov [dwValue], eax
    call srcommon
    xor eax, eax
endrestsectors:
    call readfile
    ret

srfat2:                            ; save/restore FAT-2 to/from file
    cmp [bFats], 2
    jb srfat1
    mov eax, [dwFat1end]
    jmp srfatx
srfat1:                            ; save/restore FAT-1 to/from file
    mov eax, [dwReserved]
srfatx:
    call srcommon
    mov edx, [dwSpF]
    mov [dwValue], edx
    cmp [srflag], SR_SAVE
    je endsavedrive
    jmp endrestsectors

srsector0:                         ; save/restore MBR/BS to/from file
    call srcommon
    xor eax, eax
    mov [dwValue], 1
    cmp [srflag], SR_SAVE
    je endsavedrive
    jmp endrestsectors

savesecrange:                 ; save sector range
    call getnos               ; get number of sectors in [dwValue]
    jc @F
    call srcommon             ; get filename ( may skip return address if no filename supplied )
    mov eax, [dwCurSector]
    jmp endsavedrive
@@:
    ret

restsecrange:                 ; restore sector range
    call srcommon             ; calls findfile
    mov eax, [dwFilesize]
    movzx ebx, [wBps]
    cmp eax, ebx
    jae filesizeok
toosmallerr:
    mov dx, offset toosmall   ; "File too small"
    call printerror
    ret
filesizeok:  
;    mov eax, [dwFilesize]
    xor edx, edx
    div ebx
    mov ebx, [dwDataend]
    sub ebx, [dwCurSector]
    inc ebx
    cmp eax, ebx                          ; if there are more sectors in the
    jbe mvok                              ; file than there are remaining
    xchg eax, ebx                         ; on the partition; then set number
mvok:                                     ; of partition sectors remaining
                                          ; as maxvalue
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset szNoOfSectors, eax
    call getdecvalue
    jc @F
    mov eax, [dwCurSector]
    jmp endrestsectors
@@:
    ret

submenu_fileoptions endp

;--- menu File, save sectors, bs, fat, ...
;--- "save chain" isn't handled here, it's in savechain()
;--- "save partition" is handled by dumpiso() ( why? )

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

    push eax
    mov edx, [dwValue]            ; the plan here is to convert
    movzx eax, [wBps]             ; "value" into the number of 512-byte
    mul edx
    pop eax
    and edx, edx                  ; more than 4 GB to write?
    jne toobig

    push ax
    call createfile
    pop ax
    jnc dosavedata
donesavedata:
    ret
dosavedata:
    push [dwValue]
    mov di, offset writeprogress
    call writefile
    pushf
    call closefile
    popf
    pop eax
    jc donesavedata
    mov [menustackidx], 0        ; if file op was successful, go back to main menu
    jmp sectorswritten2file

toobig::
    mov dx, offset filetoobigmsg
    jmp printerror

invalidperror::
    mov dx, offset invalidpmsg   ;"invalid sector range"
    jmp printerror

writeprogress::
    mov eax, [dwValue]
    mov cx, offset writingmsg 
    jmp printprogress

savedata endp

;--- dump cd to .iso-file, partition to image-file

dumpiso proc

    mov edx, [dwDataend]
    inc edx
    mov [dwValue], edx

    movzx eax, [wBps]             ; "value" into the number of 512-byte
    mul edx
    and edx, edx                  ; more than 4 GB to write?
    jne toobig

    call srcommon                 ; prompt user for file name

    call createfile
    jc done
    cmp [ioreq.drvtype], DT_CDROM
    jne drivedump

    push ds
    pop es
    mov di, offset sectbuffer
    mov cx, [wBps]
    mov al, 0
    rep stosb

    mov cx, [wBps]
    mov dx, offset sectbuffer
    mov bx, [wFilehandle]
    mov si, 10h
;--- write to file (16 blank sectors)
;--- to the beginning of the iso
;--- since we can't read the first 10 sectors on a CD
isoloop:
    mov ah, 40h
    int 21h
    jnc @F
    mov dx, offset filewriteerr
    call printerror
    stc 
    jmp donedump
@@:
    dec si
    jnz isoloop
drivedump:

    @getstarttime
    xor eax, eax
    mov di, offset writeprogress
    call writefile
    @printtime "writefile duration: %lu ms"

donedump:
    pushf
    call closefile
    popf
    jc done
    mov eax, [dwDataend]
    inc eax
    call sectorswritten2file
    mov [menustackidx], 0               ; leave file option menu, back to main menu
done:
    ret

dumpiso endp

;--- submenu goto

submenu_jumpto proc

    @mstart pdjumpmenu
    @mitem 16, jumptosector
    @mitem 17, jumptobootsector
    @mitem 18, jumptop1
    @mitem 19, jumptop2
    @mitem 20, jumptop3
    @mitem 21, jumptop4
    @mend pdjumpmenu

    @mstart ldjumpmenu
    @mitem  7, jumptosector
    @mitem  8, jumptobootsector
    @mitem  9, jumptocluster
    @mitem 10, jumptofat1
    @mitem 11, jumptofat2
    @mitem 12, jumptoroot
    @mitem 13, jumptodata
    @mend ldjumpmenu

    @mstart ntfsjumpmenu
    @mitem  7, jumptosector
    @mitem  8, jumptobootsector
    @mitem 45, jumptomft
    @mend ntfsjumpmenu

    mov cl, 2
;--- set menu "input, MBR, partition1, ..."
    mov dx, pdjumpmenu + lpdjumpmenu shl 8
    cmp [ioreq.drvtype], DT_PHYSICAL
    je @F
    mov dx, ntfsjumpmenu + lntfsjumpmenu shl 8
    cmp [filesys], FS_NTFS
    jz @F
    mov dx, ldjumpmenu + 1 shl 8  ; for CDFS, just jump to sector
    cmp [ioreq.drvtype], DT_CDROM
    je @F
    mov dh, lldjumpmenu
@@:
    jmp pushmenustack

jumptop1:
    mov ebx, [partitions+0*sizeof dword]
    jmp donejump
jumptop2:
    mov ebx, [partitions+1*sizeof dword]
    jmp donejump
jumptop3:
    mov ebx, [partitions+2*sizeof dword]
    jmp donejump
jumptop4:
    mov ebx, [partitions+3*sizeof dword]
    jmp donejump

jumptodata:
    mov ebx, [dwDataStart]
    jmp donejump

jumptomft:
    mov ebx, [dwRootSect]
    jmp donejump

jumptocluster:
    mov eax, [dwLastCluster]
    mov dx,offset sprintfbuffer
    invoke sprintf, dx, offset szCluster2, eax
    call gethexvalue
    jc done
    mov eax, ebx
    jmp setcluster

jumptobootsector::
    xor ebx, ebx
    jmp donejump

jumptofat1:
    mov ebx, [dwReserved]
    jmp donejump
jumptofat2:
    cmp [bFats], 2
    jb jumptofat1
    mov ebx, [dwFat1end]
    jmp donejump
jumptoroot::
    mov ebx, [dwRootSect]

donejump:
    cmp [dwDataend], ebx
    jb @F
    mov [ioreq.dwSector], ebx
    call readsect
    mov [menustackidx], 0  ; auto return to main menu
@@:
done:
    ret
;-------------------------------------------------------
jumptosector:
    mov eax, [dwDataend]
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset szSector2, eax    ; "sector (0-x): "
    call getdecvalue
    jc done
    mov ebx, ecx
    jmp donejump

;--- ctrl-end

jumptolastsect::
    mov ebx, [dwDataend]
    jmp donejump

submenu_jumpto endp

;--- main menu, cursor move keys
;--- home
;--- end
;--- csr-up
;--- csr-down
;--- csr-left
;--- csr-right

movefirst:
    mov ax, [spot]
    neg ax
    mov dl, 0
    jmp domove

movelast:
    mov ax, VIEWBYTES
    dec ax
    sub ax,[spot]
    mov dl, 0
    jmp domove

moveup:
    mov ax, -16
    mov cx, -4
    jmp moveupdn
movedown:
    mov ax, 16
    mov cx, 4
moveupdn:
    mov dl, [bHL]
    cmp [editmode], EM_ASCII
    je domove
    cmp [displaymode], DM_BINARY
    jne domove
    mov ax, cx
    jmp domove

moveleft:
    mov ax, -1
    mov cl, 8
    jmp moveleftright
moveright:
    mov ax, 1
    mov cl, 0
moveleftright:
    mov dl, [bHL]
    cmp [editmode], EM_ASCII
    je domove
    cmp [displaymode], DM_HEX
    je dohexadd
;--- binary move left/right
    add dl,al
    cmp dl,8+1
    pushf
    jb @F
    mov dl,cl
@@:
    cmp dl,4
    jnz @F
    add dl,al
@@:
    popf
    jnb domove
    xor ax, ax
    jmp domove
dohexadd:     ; hex move left/right
    add dl, al
    cmp dl, 2
    pushf
    and dl, 1
    popf
    jnb domove
    xor ax, ax
;    jmp domove

;--- common code for up,down,left,right

domove proc
    add ax, [spot]
    cmp ax, VIEWBYTES
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
;           this function is called for every key press in main menu,
;           so don't do lengthy things here!

updateview proc

    mov al,[viewmode]
    cmp al, VM_BOOTSECTOR
    je bsview
    cmp al, VM_FAT12
    je fat12viewmode
    cmp al, VM_FAT16
    je fat16viewmode
    cmp al, VM_FAT32
    je fat32viewmode
    cmp al, VM_DIRECTORY
    je dirview
    cmp al, VM_MBR
    je mbrview
    cmp al, VM_FSINFO
    je fsinfoviewmode

if ?DEBUG
    cmp al, VM_DEBUG
    je debugviewmode
endif
;    call clearview
    ret

updateview endp

;--- filesystem info view

fsinfoviewmode proc
    mov [scrn_xy], VIEWROW * 100h + 1

    call bufferinsi
    mov bx, 01E8h
    mov [highlight.siz_], 4
    mov di, offset fifields
    mov cx, numfifields
nextitem: 
    push cx
    mov dx, [di+0]
    call printstring
;   dec bx

    xor dx, dx
    mov eax, dword ptr [si+bx]
    cmp eax, -1
    jne vbik
    mov [highlight.scsiz], 7
    call bshighlight
    mov dx, offset unknownmsg
    call printstring
    mov ax, COL_DEFAULT shl 8 or SPACE
    mov cl, 3
    call fillcell
    jmp dtsc
vbik:
    call word ptr [di+2]
dtsc:
    add bx, sizeof dword
    call printcrlf
    add di, 2*2
    pop cx
    loop nextitem
    ret

fsinfoviewmode endp

;--- print an 8 digit hex number
;--- si=buffer
;--- bx=entry
;--- dx=offset

printhex_hl:
    push bx
    add bx, dx
    mov eax, [si+bx]
    mov [highlight.ofs], bx
    pop bx
    mov dl, 8
    mov [highlight.scsiz], dl
    call rendernumhex
    call bshighlight
    jmp printstring

;--- display directory LFN entry
;--- actually this may span multiple entries
;--- in: si=buffer
;---     bx=start entry

lfnview proc

    mov dx, CStr('LFN entry "')
    call printstring

    .const

lfntab label byte
    db 1,5
    db 14,6
    db 28,2

    include oemchars.inc

    .code

    push bx
@@:
    mov cl, [si+bx]
    and cl, 3Fh
    cmp cl, 1
    jz foundfirst
    cmp bx,  512 - DIRENTSIZE
    jz foundfirst
    cmp byte ptr [si+bx+DIR_ATTRIBUTES+DIRENTSIZE], 0Fh
    jnz foundfirst
    add bx, DIRENTSIZE
    jmp @B
foundfirst:

nextentry:
    push bp
    mov bp, offset lfntab
    mov ch, 3
nextti:
    movzx di, byte ptr [bp+0]
    mov cl, [bp+1] 
    mov ax, bx
    add ax, di
    mov [highlight.ofs], ax
    add di, si
    add di, bx
    push bx
    mov bx, offset sprintfbuffer
nextchar:
    mov ax, [di]
    and ax, ax      ; end of string reached?
    jnz @F
    mov ch, 1
    jmp namedone
@@:
    call translatechar
    mov [bx], al
    inc bx
    add di, 2
    dec cl
    jnz nextchar
namedone:
    mov byte ptr [bx], 0
    mov ax, bx
    pop bx
    mov dx, offset sprintfbuffer
    sub ax, dx
    mov ah, RIGHTCOL-1
    sub ah, al
    mov [highlight.scsiz], al
    shl al, 1
    mov [highlight.siz_], al
    jz noprint
    sub ah, [scrn_col]
    jnc @F
    call printeol
@@:
    call bshighlight
    call printstring
noprint:
    add bp, 2
    dec ch
    jnz nextti
    pop bp

    mov al, [si+bx]
    and al, 0C0h
    cmp al, 40h      ; last entry?
    jz done
    cmp bx, 0
    jz done
    sub bx, DIRENTSIZE
    cmp byte ptr [si+bx+DIR_ATTRIBUTES], 0Fh
    jz nextentry
done:
    mov dl, '"'
    call printchar

@@:
    cmp [scrn_row], VIEWROW+5
    jz @F
    call printcrlf
    mov ax, COL_DEFAULT shl 8 or SPACE
    mov cl, 78
    call fillcell
    jmp @B
@@:
    pop bx
    test byte ptr [si+bx], 80h
    jz @F
    mov [scrn_xy], (VIEWROW+1) * 100h + 1
    mov dx, CStr('(deleted)')
    call printstring
@@:
    ret
translatechar:
    and ah, ah
    jnz qmark
    and al,al
    jns @F
    push si
    mov si, offset oemchars
    mov dl, al
    and dx, 7fh
    add si, dx
    mov dl, [si]
    pop si
    and dl, dl
    jz @F
    mov al, dl
@@:
    ret
qmark:
    mov al,'?'
    ret

printeol:
    pusha
    mov dl, '"'
    call printchar
    call printcrlf
if 0
    mov ax, COL_DEFAULT shl 8 or SPACE
    mov cl, 78
    call fillcell
endif
    mov [scrn_col], 11
    mov dl, '"'
    call printchar
    popa
    ret

lfnview endp

;--- in: si=sector buffer
;---     bx=current dir entry

exfat_dirview proc

;--- (de)activate "Chain"

    xor dx, dx
    cmp [menustackidx], 2        ; simple check if "file options" may be active.
    jnz nochainadjust
    mov al, -2
    mov ah, NO_CHAIN
    cmp [si+bx].EXFDIRP.etype, 0C0h          ; file stream entry?
    jnz @F
    mov al, MENUF_CHAIN
    mov ah, FILE_CHAIN
@@:
    cmp al, [ldfileoptf7]
    setnz dl
    mov [ldfileoptf7], al
    mov [chainflag], ah
nochainadjust:
    and dx, dx         ; only reprint the current menu if menu has been changed
    jz @F
    pusha
    call printmenu
    popa
@@:

    mov [scrn_xy], VIEWROW * 100h + 1
    mov cl, 78
    mov ax, COL_DEFAULT shl 8 or SPACE
    call fillcell
    inc [scrn_row]
    mov cl, 78
    mov ax, COL_DEFAULT shl 8 or SPACE
    call fillcell
    mov [scrn_xy], VIEWROW * 100h + 1

    mov al, [si+bx].EXFDIRP.etype
    test al, 80h
    jz freeentry
    test al, 40h
    jnz issecondary

    and al,1Fh
    mov dx, allocbm
    cmp al, EXFPTC_ALLOCBM
    jz @F
    mov dx, upcase
    cmp al, EXFPTC_UPCASET
    jz @F
    mov dx, vollabel
    cmp al, EXFPTC_VOLLABEL
    jz @F
    mov dx, file
    cmp al, EXFPTC_FILE
    jnz unknownprim
@@:
    call dx
unknownprim:
if ?EXTVIEW
    mov dx, CStr(", primary")
    call printstring
endif
    movzx cx, [si+bx].EXFDIRP.seccnt
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr(", secondary count: %u"), cx
    call printstring
done:
    ret
freeentry:
    and al, al   ; end of directory?
    jz done
    mov dx, CStr("free")
    call printstring
    ret
issecondary:
if ?EXTVIEW
    mov dx, CStr("secondary, ")
    call printstring
endif
    and al, 1Fh
    cmp al, 0      ; a secondary file stream entry?
    jz isfilestream
    cmp al, 1      ; a secondary file name entry?
    jz isfilename
    ret
isfilestream:
    mov dx, offset sprintfbuffer
    movzx ax, [si+bx].EXFDIRSS.secflgs
    invoke sprintf, dx, CStr("file stream, flags: %X"), ax
    call printstring
    test al, EXFPF_NOCHAIN
    jz @F
    push dx
    mov dx, CStr(" [no FAT chain]")
    call printstring
    pop dx
@@:
    movzx cx, [si+bx].EXFDIRSS.namelength
    invoke sprintf, dx, CStr(", name length: %u"), cx
    call dispcluster
    ret
isfilename:
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr('file name')
    call printstring
fncont_nextrow:
    inc [scrn_row]
    mov [scrn_col], 1
    mov dl,'"'
    call printchar
fncont:
    push si
    lea si, [si+bx].EXFDIRSN.name_
    mov cx, 15
nextwchar:
    lodsw
    and ax, ax
    jz namedone
    cmp ah, 0
    jz @F
    mov al, '?'
@@:
    mov dl, al
    call printchar
    loop nextwchar
namedone:
    pop si
    jz @F
    cmp bx,[wBps]
    jz @F
    cmp [si+bx+DIRENTSIZE].EXFDIRS.etype, EXFSTCF_NAME
    jnz @F
    add bx, DIRENTSIZE
    cmp [scrn_col], RIGHTCOL-15
    jb fncont
    mov dl,'"'
    call printchar
    jmp fncont_nextrow
@@:
    mov dl,'"'
    call printchar
    ret

allocbm:
    mov dx, CStr("allocation bitmap")
    call printstring
    call dispcluster
    ret
upcase:
    mov dx, CStr("uppercase table")
    call printstring
    call dispcluster
    ret
vollabel:
    mov dx, CStr("volume label")
    call printstring
    ret
file:
    mov dx, CStr("file, attributes: ")
    call printstring
    mov dx, EXFDIRPF.attributes
    call printattr

    push [scrn_xy]
    inc [scrn_row]
    mov [scrn_col], 1

    mov dx, CStr("created: ")
    call printstring
    mov dx, EXFDIRPF.dwCreated + 2
    call printdate
    mov dx, EXFDIRPF.bCreInc
    mov cx, EXFDIRPF.dwCreated
    call printtime

    mov dx, CStr(", modified: ")
    call printstring
    mov dx, EXFDIRPF.dwModified + 2
    call printdate
    mov dx, EXFDIRPF.bModInc
    mov cx, EXFDIRPF.dwModified
    call printtime
    pop [scrn_xy]

    ret

dispcluster:
    mov al, [si+bx].EXFDIRP.etype
    test al,80h
    jz nocluster
    push [scrn_xy]
    mov [scrn_col],1
    inc [scrn_row]
    mov dx, CStr("start cluster: ")
    call printstring
    mov [highlight.siz_], 4
    mov dx, EXFDIRP.dwFirstCl
    call printhex_hl
    mov dx, CStr(", size: ")
    call printstring
    mov [highlight.siz_], 8
    mov dx, EXFDIRP.dqSize
    call printvalue_hl
    pop [scrn_xy]
nocluster:
    ret

exfat_dirview endp

;--- directory view
;--- displaying just the spot entry

dirview proc

    call bufferinsi
    mov bx,[spot]
    and bl, 0E0h

    cmp [filesys], FS_EXFAT
    jz exfat_dirview

;--- adjust menus.
;--- (the menu adjustment is currently a bit silly implemented, too complicated )

    xor dx, dx                   ; dl and dh used as flags if the menu has to be printed

;--- de(activate) "chain" in "file options" menu.

    cmp [menustackidx], 2        ; simple check if "file options" may be active.
    jnz nochainadjust
    mov al, -2
    mov ah, NO_CHAIN
    cmp byte ptr [si+bx], 0      ; dir entry empty?
    jz @F
    cmp byte ptr [si+bx+DIR_ATTRIBUTES], 0Fh  ; LFN entry?
    jz @F
    mov al, MENUF_CHAIN
    mov ah, FILE_CHAIN
@@:
    cmp al, [ldfileoptf7]
    setnz dl
    mov [ldfileoptf7], al
    mov [chainflag], ah
nochainadjust:

;--- (de)activate "undelete" in "functions" menu depending on current entry status

    cmp [menustackidx], 1        ; simple check if "functions" may be active
    jnz noundeleteadjust
    mov al, -2
    cmp byte ptr [si+bx], 0E5h
    jnz @F
    cmp byte ptr [si+bx+DIR_ATTRIBUTES], 0Fh  ; LFN entry?
    jz @F
    mov al, MENUF_UNDELETE
@@:
    cmp al, [funcmf4]
    setnz dh
    mov [funcmf4], al
noundeleteadjust:

    and dx, dx         ; only reprint the current menu if a menu has been changed above
    jz @F
    pusha
    call printmenu
    popa
@@:

    mov [scrn_xy], VIEWROW * 100h + 1

;--- attribute value of 0Fh (R/O+hidden+system+volume) indicates a LFN entry

    call clearentryview

    cmp byte ptr [si+bx+DIR_ATTRIBUTES], 0Fh
    jz lfnview
    cmp byte ptr [si+bx],0
    jz done

    mov [scrn_col], 5
    mov dx, CStr("Name: ")
    call printstring
    mov di, offset sprintfbuffer
    mov dx, di
    push ds
    pop es
    push si
    add si, bx
    mov cx, 8
    rep movsb
    mov cl, 8
@@:
    dec di
    cmp byte ptr [di], SPACE
    loopz @B
    inc di
    mov cl,3
@@:
    lodsb
    cmp al, SPACE
    loopz @B
    jz @F
    dec si
    inc cx
    mov al,'.'
    stosb
    rep movsb
@@:
    pop si
    mov [di], cl

    mov [highlight], 0B0000h
    add [highlight.ofs], bx
    mov ax, di
    sub ax, dx
    mov [highlight.scsiz], al
    call bshighlight
    call printstring

    cmp byte ptr [si+bx],0E5h
    jnz @F
    mov [scrn_col], 40+12
    mov dx, CStr("(deleted)")
    call printstring
@@:
    call printcrlf

    inc [scrn_col]

;--- print created date+time

    mov dx, offset createdmsg
    call printstring

    mov dx, DIR_CREATEDATE
    call printdate

;--- minute+second

    mov cx, DIR_CREATETIME
    mov dx, DIR_CREATEMSEC
    call printtime

    mov dl, '.'
    call printchar

    mov [highlight], (101h shl 16) or DIR_CREATEMSEC
    add [highlight.ofs], bx
    call bshighlight

    movzx ax, byte ptr [si+bx+DIR_CREATEMSEC]
    cmp al, 199
    jbe @F
    mov al, 199
@@:
    xor dx, dx
    push bx
    mov bx, 10
    div bx
    pop bx
    add dl, 48
    call printchar

    mov [scrn_col], 40

;--- print attributes

    mov dx, offset attributesmsg
    call printstring

    mov dx, DIR_ATTRIBUTES
    call printattr
    call printcrlf

;--- print last access date

    mov dx, offset accessedmsg    ; last accessed
    call printstring

    mov dx, DIR_LASTACCDATE
    call printdate

;--- print cluster

    mov [scrn_col], 40+3

    mov dx, offset szCluster
    call printstring

;--- hiword cluster only displayed if it's != 0000 or filesys is FAT32/exFAT
    mov [highlight], (0302h shl 16) or DIR_CLUST_HIGH
    add [highlight.ofs], bx
    mov ax, word ptr [si+bx+DIR_CLUST_HIGH]
    and ax, ax
    jnz @F
    test [filesys], FS_FAT32
    jz nohighcl
@@:
    call bshighlight
    mov dl, 3
    call rendernumhex
    call printstring
nohighcl:
    mov [highlight.scsiz], 4
    add [highlight.ofs], (DIR_CLUST_LOW - DIR_CLUST_HIGH)
    call bshighlight

    mov dl, 4
    mov ax, word ptr [si+bx+DIR_CLUST_LOW]
    call rendernumhex
    call printstring

    call printcrlf

;--- print last modified date

    mov dx, offset modifiedmsg    ; last modified
    call printstring

    mov dx, DIR_LASTUPDDATE
    call printdate
    xor dx, dx
    mov cx, DIR_LASTUPDTIME
    call printtime

;--- print size

    mov [scrn_col], 40+3+3

    mov dx, offset sizemsg
    call printstring

    mov [highlight.siz_], 4
    mov dx, DIR_FILESIZE
    call printvalue_hl
done:
    ret

clearentryview:
    mov cx, 4 shl 8 or 78
    mov ax, COL_DEFAULT shl 8 or SPACE
@@:
    call fillcell
    inc [scrn_row]
    dec ch
    jnz @B
    sub [scrn_row], 4
    ret

dirview endp

    .const
attrchars db "ADVSHR"
    .code

;--- print attributes
;--- in: si+bx -> entry
;---     dx = offset for attributes

printattr proc
    push di
    push si
    mov word ptr [highlight.siz_], 601h
    push bx
    add bx, dx
    mov ah, [si+bx]
    mov [highlight.ofs], bx
    pop bx
    call bshighlight

    mov di, offset valuebuffer
    push ds
    pop es
    mov si, offset attrchars
    mov cx, sizeof attrchars
    shl ah, 2   ; use bits 0-5 only
nextchar:
    lodsb
    shl ah, 1
    jc @F
    mov al, '-'
@@:
    stosb
    loop nextchar
    mov [di], cl
    pop si
    pop di
    mov dx, offset valuebuffer
    jmp printstring

printattr endp


chainmenuitem proc

    mov [ldfileoptf7], MENUF_CHAIN
    mov [chainflag], FAT_CHAIN   ; we're in a FAT
    ret

chainmenuitem endp


;--- FAT32/EXFAT view - 7 rows and 9 clusters/row are shown.
;--- in total that fits in 15 lines: 0,36,72,108,144,180,216,252,288,324,360,396,432,468,504
;--- ( the last line has 2 items only )

CLUSTER_PER_ROW = 9
CLBYTES_PER_ROW = CLUSTER_PER_ROW * sizeof dword

fat32viewmode proc

    call chainmenuitem

    xor ebx, ebx
    call getentrynumberX
    mov edi, eax


    mov [scrn_xy], VIEWROW * 100h + 4
    mov [highlight], 07040000h

    call bufferinsi

    mov bx, 4 * CLBYTES_PER_ROW

loopline2:
    cmp [spot], bx
    jb donesetline2
    add si, CLBYTES_PER_ROW
    add bx, CLBYTES_PER_ROW
    add edi, CLUSTER_PER_ROW
    add [highlight.ofs], CLBYTES_PER_ROW
    cmp bx, 12 * CLBYTES_PER_ROW
    jne loopline2
donesetline2:

    mov ch, 7
nextrow:
    mov cl, CLUSTER_PER_ROW
nextcol:
    call bshighlight
    add [highlight.ofs], 4

    lodsd

    mov dx, CStr("-------")
    cmp edi, [dwLastCluster]
    ja @F
    mov dl,7
    call rendernumhex
@@:
    call printstring

    mov dl, SPACE
    call printchar

    inc edi
    add bx, sizeof dword
    cmp bx, 512 + 4 * CLBYTES_PER_ROW
    jz done

    dec cl
    jnz nextcol
    mov [scrn_col], 4
    inc [scrn_row]
    dec ch
    jnz nextrow
    ret
done:
    mov cl, 7 * 7 + 6  ; 7 clusters, 7 digits/cluster, 6 spaces
    jmp fillspace

fat32viewmode endp
  
;--- FAT16 view - 7 rows and 15 clusters/row are shown
;--- that fits in 18 rows: 0,30,60,90,120,150,180,210,240,270,300,330,360,390,420,450,480,510

CLUSTER_PER_ROW = 15
CLBYTES_PER_ROW = CLUSTER_PER_ROW * sizeof word

fat16viewmode proc

    call chainmenuitem

    xor ebx, ebx
    call getentrynumberX
    mov edi, eax

    mov [scrn_xy], VIEWROW * 100h + 3
    mov [highlight], 04020000h

    call bufferinsi

    mov bx, 4 * CLBYTES_PER_ROW

loopline:
    cmp [spot], bx
    jb donesetline
    add si, CLBYTES_PER_ROW
    add bx, CLBYTES_PER_ROW
    add edi, CLUSTER_PER_ROW
    add [highlight.ofs], CLBYTES_PER_ROW
    cmp bx, 15 * CLBYTES_PER_ROW
    jne loopline
donesetline:

    mov ch, 7
nextrow:
    mov cl, CLUSTER_PER_ROW
nextcol:

    call bshighlight
    add [highlight.ofs], 2

    lodsw

    mov dx, CStr("----")
    cmp edi, [dwLastCluster]
    ja @F
    mov dl,4
    call rendernumhex
@@:
    call printstring

    mov dl, SPACE
    call printchar

    inc edi
    add bx, sizeof word
    cmp bx, 512 + 4 * CLBYTES_PER_ROW
    je done

    dec cl
    jnz nextcol
    mov [scrn_col], 3
    inc [scrn_row]
    dec ch
    jnz nextrow
    ret
done:
    mov cl, 14 * 4 + 13   ; 14 clusters, 4 digits/cluster, 13 spaces (=69)
    jmp fillspace

fat16viewmode endp

CLUSTER_PER_ROW = 18
CLBYTES_PER_ROW = 27 ; that's 18 * 1.5 (12 bits/entry)

;--- FAT12 view
;--- to be fixed: currently the view is filled with 7 full lines,
;--- although there might be less valid clusters.   

fat12viewmode proc

    call chainmenuitem

    xor ebx, ebx
    call getentrynumberX
    mov di, ax

    mov [highlight], 03020000h

    xor ax, ax                          ; this little loop figures out
    mov bx, [spot]                      ; where to start displaying
buf12fix:                               ; fat12 entries, since an entire
    cmp bx, 4 * CLBYTES_PER_ROW         ; sectofs (512 bytes) of 3-nibbles
    jb donebuffix                       ; won't fit in the view area.
    sub bx, CLBYTES_PER_ROW
    add ax, CLBYTES_PER_ROW
    add di, CLUSTER_PER_ROW
    add [highlight.ofs], CLBYTES_PER_ROW
    cmp ax, 300
    jbe buf12fix
donebuffix:

    mov si, offset sectbuffer
    add si, [sectofs]

    call fat12pad

    add si, ax

    mov eax, [dwCurSector]

    mov ebx, [dwFat12start]
    cmp ebx, eax
    ja dodec12
    sub eax, ebx
    jmp donesub12
dodec12:
    dec eax
donesub12:

;--- eax = relative sectorno in fat
if 0
;--- this instructions have no effect at all if sector size is 512!!!
;--- if sector size is 2048, is there a fat12 possible?
    movzx ebx, [sectofs]         ;???
    add eax, ebx                 ;???
    mov cx, [wBps]               ;512 = 200h
    shr cx, 10                   ;/1024 -> 0???
    shl eax, cl
endif
    xor edx, edx
    mov ebx, 3
    div ebx

    mov [scrn_xy], VIEWROW * 100h + 3

    cmp dl, 0
    je fat12loop
    dec [highlight.ofs]
    dec si
    cmp dl, 1
    je ssection
  
fat12loop:
    lodsw
    call print12bits
    jnc done
    dec si
ssection:
    lodsw
    xchg al, ah
    rol ax, 4
    call print12bits
    jnc done
    inc [highlight.ofs]
    jmp fat12loop
done:
    mov cl, 4
    jmp fillspace

print12bits:
    mov dl, SPACE
    call printchar
    call bshighlight
    inc [highlight.ofs]
    mov dx, CStr("---")
    cmp di, word ptr [dwLastCluster]
    ja @F
    mov dl,3
    call rendernumhex
@@:
    call printstring
    inc di
    cmp [scrn_col], 75
    jne @F
    mov [scrn_col], 3
    inc [scrn_row]
@@:
    cmp [scrn_xy], (VIEWROW+7) * 100h + 3  ;check if we reached bottom of view area
    ret

fat12viewmode endp

;-------------------------------------------------------

;--- physical disk MBR view

mbrview proc

    mov [scrn_col], 01h
    xor cx, cx

    call bufferinsi

nextpart:
    mov [scrn_row], VIEWROW

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

    call mbrcommon

    mov dx, offset mboot
    call printstring

    mov word ptr [highlight+2], 0201h
    mov [highlight.ofs], bx
    call bshighlight

    mov al, byte ptr [si+bx]
    mov dl,2
    call rendernumhex
    call printstring

    mov dl, SPACE
    call printchar
    cmp al, 80h
    je partactive
    jmp donepart

partactive:
    mov dx, offset szActive
    call printstring
donepart:

    call mbrcommon

;--- print partition start/end CHS

    mov dx, offset startchs
    call printchs

    call mbrcommon

    mov dx, offset mtype
    call printstring

    mov word ptr [highlight+2], 0201h
    mov [highlight.ofs], bx
    add [highlight.ofs], 4

    call bshighlight

    mov al, byte ptr [si+bx+4]
    mov dl, 2
    call rendernumhex
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
    jmp dontshowpart

showpart:
    push dx
    mov dl, '('
    call printchar
    pop dx
    call printstring
    mov dl, ')'
    call printchar

dontshowpart:

    call mbrcommon
    mov dx, offset endchs

    add bx, 4

    call printchs
    call mbrcommon

    mov dx, offset startlba
    call printstring

    mov dx, 4
    mov [highlight.siz_], 4
    call printvalue_hl

    call mbrcommon

    mov dx, offset psize
    call printstring

    mov dx, 8
    mov [highlight.siz_], 4
    call printvalue_hl

    inc cx

    call mbrcommon
    cmp cx, 4
    jb nextpart
    ret

;--- position to next line
;--- CX=partition no
mbrcommon:
    mov al, 20
    mul cl
    inc al

;--- clear the rest of this "quarter" line
    push cx
    push ax
    mov cl, al
    add cl, 20
    sub cl, [scrn_col]
    call fillspace
    pop ax
    pop cx

    mov [scrn_col], al
    inc [scrn_row]
    ret

mbrview endp


    .data

;--- FAT BPB struct

bsviewtab label word
    dw BPB.bytes_sector
    dw DStr('Bytes Per Sector')
    dw 0502h
    dw BPB.sectors_cluster
    dw DStr('Sectors Per Cluster')
    dw 0301h
    dw BPB.reserved_sectors
    dw DStr('Reserved Sectors')
    dw 0502h
    dw BPB.num_fats
    dw DStr('Number Of Fats')
    dw 0301h
    dw BPB.root_entries
    dw DStr('Maximum Root Entries')      ; FAT1x only
    dw 0502h
    dw BPB.media_byte
    dw DStr('Media Descriptor')
    dw 0301h
    dw BPB.hidden_sectors
    dw DStr('Partition Start')
    dw 0A04h
bs_psec label word
    dw 0                                 ; sectors (FAT12 or FAT16/FAT32)
    dw DStr('Sectors In Partition')
    dw 0
bs_spf label word
    dw 0
    dw DStr('Sectors Per Fat')
    dw 0
bs_hd label word
    dw 0
    dw DStr('Hard Disk Number')
    dw 0301h
    dw EBPB_FAT32.root_startcl
    dw DStr('Root Start Cluster')        ; FAT32 only
    dw 0A04h
    dw EBPB_FAT32.fs_info_start
    dw DStr('FSInfo Sector Number')      ; FAT32 only
    dw 0502h
    dw EBPB_FAT32.bs_copy_start
    dw DStr('Backup B.S. Location')      ; FAT32 only
    dw 0502h
lbsviewtab equ ($ - offset bsviewtab) / ( 3 * sizeof word )

    .code

;--- boot sector view

bsview proc
    mov [scrn_xy], VIEWROW * 100h + 1

    call bufferinsi

    cmp [filesys], FS_NTFS
    jz bsntfsview
    cmp [filesys], FS_EXFAT     ; don't test flags here, no jump wanted for FAT12/16/32!
    jz bsexfatview

    mov di, offset bsviewtab

    mov bx, BPB.sectors_fat12
    mov dx, 0502h
    mov ax, word ptr [si+bx]
    test ax, ax
    jnz @F
    mov bx, BPB.sectors_fat1632
    mov dx, 0A04h
@@:
    mov word ptr [bs_psec+0], bx
    mov word ptr [bs_psec+4], dx

;--- check if it's FAT32. This will cause to print 3 additional fields

    mov cl,lbsviewtab-3
    mov bx, BPB.sec_per_fat1x
    mov dx, 0502h
    mov ax, EBPB.phys_drive
    cmp [si].BPB.sec_per_fat1x, 0
    jnz @F
    add cl, 3
    mov bx, EBPB_FAT32.sec_per_fat32
    mov dx, 0A04h
    mov ax, EBPB_FAT32.phys_drive
@@:
    mov word ptr [bs_spf+0], bx
    mov word ptr [bs_spf+4], dx
    mov word ptr [bs_hd+0], ax

    mov ch,0
nextitem:
    push cx
    call basicbs
    add di,3*2

    mov cl, 9
    call fillspace

    pop cx
    mov [scrn_col], 40
    test ch, 1
    jz @F
    call printcrlf
@@:
    inc ch
    dec cl
    jnz nextitem

    mov dx, CStr("Signature")
    call printstring
    call spaceandcolon
    mov word ptr [highlight.ofs],1FEh
    mov word ptr [highlight.siz_],0402h
    call bshighlight
    mov dl,4
    mov ax, [si+1FEh]
    call rendernumhex
    call printstring
    cmp ax, 0AA55h
    jz @F
    mov dx, CStr(" (invalid)")
    call printstring
    ret
@@:
    mov cl,10
    call fillspace
    ret

basicbs:
    mov bx, [di+0]
    mov dx, [di+2]
    mov cx, [di+4]

    mov word ptr [highlight.siz_], cx
    call printstring
    call spaceandcolon
    mov dx, bx
    xor bx, bx
    call printvalue_hl
    cmp dx, BPB.media_byte
    jne npldn2
    cmp al, 0F0h
    jb npldn2
    mov dx, CStr(' (HD)')
    cmp al, 0F8h
    je @F
    mov dx, CStr(' (FD)')
@@:
    call printstring
npldn2:

    cmp di, offset bs_hd
    jnz @F
    cmp al, 80h
    jb @F
    cmp al, 89h
    ja @F
    mov dl, SPACE
    call printchar
    mov dl, '('
    call printchar
    mov dl, al
    sub dl, 80h-48
    call printchar
    mov dl, ')'
    call printchar
@@:
    ret

bsview endp

    .data

;--- NTFS BPB struct

bsntfsviewtab label word
    dw BPB.bytes_sector
    dw DStr('Bytes Per Sector')
    dw 0502h
    dw BPB.sectors_cluster
    dw DStr('Sectors Per Cluster')
    dw 0301h
    dw BPB.reserved_sectors
    dw DStr('Reserved Sectors')
    dw 0502h
    dw BPB.media_byte
    dw DStr('Media Descriptor')
    dw 0301h
    dw BPB.hidden_sectors
    dw DStr('Partition Start')
    dw 0A04h
    dw 28h
    dw DStr('Sectors In Partition')
    dw 0A04h
    dw 30h
    dw DStr('$MFT Cluster')
    dw 1408h
    dw 38h
    dw DStr('Backup $MFT Cluster')
    dw 1408h
lbsntfsviewtab equ ($ - offset bsntfsviewtab) / ( 3 * sizeof word )

    .code

bsntfsview proc
    mov di, offset bsntfsviewtab
    mov cl,lbsntfsviewtab
    mov ch,0
nextitem:
    push cx
    call basicbs
    add di,3*2

    mov cl, 9
    call fillspace

    pop cx
    mov [scrn_col], 40
    test ch, 1
    jz @F
    call printcrlf
@@:
    inc ch
    dec cl
    jnz nextitem
    ret
basicbs:
    mov bx, [di+0]
    mov dx, [di+2]
    mov cx, [di+4]

    mov word ptr [highlight.siz_], cx
    call printstring
    call spaceandcolon
    mov dx, bx
    xor bx, bx
    call printvalue_hl
    ret
bsntfsview endp

    .data

bsexfatviewtab label word
    dw EXFAT.dqHidden
    dw DStr('Start of Partition')
    dw 1408h
    dw EXFAT.dqSize
    dw DStr('Sectors In Partition')
    dw 1408h
    dw EXFAT.dwFatOfs
    dw DStr('Reserved Sectors')
    dw 0A04h
    dw EXFAT.dwFatSiz
    dw DStr('Size of FAT')
    dw 0A04h
    dw EXFAT.dwClHpOfs
    dw DStr('Start Data Region')
    dw 0A04h
    dw EXFAT.dwClCnt
    dw DStr('Clusters')
    dw 0A04h
    dw EXFAT.dwRootCl
    dw DStr('Start Root Dir')
    dw 0A04h
    dw EXFAT.wFSRev
    dw DStr('FS Revision')
    dw 0502h
    dw EXFAT.wVolFlgs
    dw DStr('Volume Flags')
    dw 0502h
    dw EXFAT.bBpSShift
    dw DStr('BytesPerSector Shift')
    dw 0301h
    dw EXFAT.bSpCShift
    dw DStr('SecPerCluster Shift')
    dw 0301h
    dw EXFAT.bNumFats
    dw DStr('No of FATs')
    dw 0301h
lbsexfatviewtab equ ($ - offset bsexfatviewtab) / ( 3 * sizeof word )

    .code

bsexfatview proc
    mov di, offset bsexfatviewtab
    mov cl,lbsexfatviewtab
    mov ch,0
nextitem:
    push cx
    call basicbs
    add di,3*2

    mov cl, 9
    call fillspace

    pop cx
    mov [scrn_col], 40
    test ch, 1
    jz @F
    call printcrlf
@@:
    inc ch
    dec cl
    jnz nextitem
    ret
basicbs:
    mov bx, [di+0]
    mov dx, [di+2]
    mov cx, [di+4]

    mov word ptr [highlight.siz_], cx
    call printstring
    call spaceandcolon
    mov dx, bx
    xor bx, bx
    call printvalue_hl
    ret
bsexfatview endp

;--- "emulate" a cr,lf sequence

printcrlf:
    mov [scrn_col], 1
    inc [scrn_row]
    ret

;--- print a value and check if it should be highlighted
;--- in: si = buffer
;---     bx = offset entry
;---     dx = offset
;---     [highlight.siz_]

printvalue_hl:

    push bx
    add bx, dx
    mov [highlight.ofs], bx
    mov eax, [si+bx]
    cmp [highlight.siz_], 8
    jnz @F
    mov edx, [si+bx+4]
    invoke i64toa, edx::eax, offset sprintfbuffer, 10
    pop bx
    mov dx, ax
    mov ax, offset sprintfbuffer+22
    sub ax, dx
    mov [highlight.scsiz], al
    call bshighlight
    jmp printstring
@@:
    pop bx
    cmp [highlight.siz_], 4
    jae @F
    movzx eax, ax
@@:
    cmp [highlight.siz_], 2
    jae @F
    mov ah, 0
@@:
printeaxvalue_hl:
    call rendernumdec
    push ax
    mov ax, offset valuebuffer+10  ;calculate string size
    sub ax, dx
    mov [highlight.scsiz], al
    pop ax
    call bshighlight
    jmp printstring

;-------------------------------------------------------
;--- modify color of chars on screen
;--- at current screen pos [scrn_xy].
;--- in: [highlight]
;---     [spot]

bshighlight proc
    pusha
    call cbuffer_offset

;--- check if current spot matches highlight.ofs

    mov al, COL_DEFAULT
    mov cl, [highlight.scsiz]    ;no of chars on screen to highlight
    movzx bx, [highlight.siz_]
    mov dx, [highlight.ofs]
    cmp [spot], dx
    jb nextcell
    add dx, bx
    cmp [spot], dx
    jae nextcell
    mov al, COL_HIGHLIGHT
    mov ch, cl
nextcell:
    inc di
    stosb
    dec cl
    jnz nextcell
    popa
    ret
bshighlight endp

if ?ALTKEYS
prevcluster:
nextcluster proc

    test [filesys], FS_FATXX
    jz done
    test [bRegion], RG_DATA
    jz done
    mov bx, ax
    mov eax, [dwCurSector]
    call sector2cluster
    jc done
    cmp bh, ALTLEFT_KEY
    setnz cl
    sub cl, 1
    cmc
    movsx ecx, cl
    adc ecx, 0
    add eax, ecx
if 0
    jmp setcluster                  ; don't use setcluster, that would push sector# onto stack
else
    mov ebx, eax                    ; save cluster# for possible error msg
    call cluster2sector             ; get corresponding sector number
    cmp eax, [dwDataend]            ; 
    ja invalclusterror              ; verify that it's a valid sector
    mov [ioreq.dwSector], eax
    call readsect
endif
done:
    ret

nextcluster endp
endif

;--- main menu pgup, pgdown, ctrl-pgup, ctrl-pgdown keys

nextsect1000:
    mov eax, [dwCurSector]
    add eax, 100
    jmp donextsect

;--- main menu, pgdn key

nextsect:
    add [sectofs], VIEWBYTES
checkcursorbounds:
    mov dx, [sectofs]
    mov ax, [wBps]                        ; if (sectofs <= bps), then
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
    mov eax, [dwCurSector]
    inc eax
donextsect:
    cmp eax, [dwDataend]
    jbe @F
    sub eax, [dwDataend]
    dec eax
@@:
    mov [ioreq.dwSector], eax
    call readsect
    jc @F
    mov [sectofs],0
@@:
    ret

;--- main menu, pgup key

prevsect:
    cmp [sectofs], 0
    jnz @F
    mov eax, [dwCurSector]
    dec eax
    jmp dolastsect
@@:
    sub [sectofs], VIEWBYTES
    jnc @F
    mov [sectofs], 0
@@:
    ret

;--- main menu, ctrl-pgup key

prevsect1000:
    mov eax, [dwCurSector]
    sub eax, 100
dolastsect:
    cmp eax, [dwCurSector]
    jb golastsect
    not eax

    mov ebx, [dwDataend]
    sub ebx, eax
    mov eax, ebx
golastsect:
    mov [ioreq.dwSector], eax
    call readsect
    jc @F
    mov dx, [wBps]
    sub dx, VIEWBYTES
    mov [sectofs], dx
    jmp checkcursorbounds
@@:
    ret

;--- logical drive
;--- it's already ensured that drive is valid
;--- and it's NOT remote ( CD-ROM / network ).
;--- What remains is to check if it's to be accessed
;--- via int 25h/26h or int 21h, ax=7305h
;--- this is also true if FS is NTFS or EXFAT.

;--- Also: here the drive can be locked - previously
;--- this was done in setvariables, but this is the wrong
;--- place, since this proc is called by "restrict"

setlogvars proc
    mov [drivepacket.sectors], 1 ; default: read in 1 sector at a time
    mov di, offset sprintfbuffer
    mov word ptr [di], 003Dh     ; size of buffer
    push ds
    pop es                       ; ES:DI = buffer for eDPB
    mov dl, [ioreq.bDrive]
    inc dl
    mov cx, 003Fh
    mov ax, 7302h                ; fix: check if this call needs translation in WinXP
    int 21h
    mov dl, RWF_OLDLOGICAL
    jc olddpb
    cmp ax,7300h
    jz olddpb
    mov ax, [di+4]
    call setBps
    jc donesetlog

;--- if dword [di+35h] != 0, it's FAT32

if ?VDD
;--- windows complains if drive is an USB memory stick.
;--- hence don't lock if running on NT!
;--- todo: check if wdevdd can take over the locking.
    cmp [hVdd],-1
    jnz dontlock
endif

;--- lock logical valume. Required by Win9x only?
;--- should there be a corresponding unlock (86A/486A) when done with the drive???

;    call unlock

;--- just doing what MS-DOS command com does:
;--- 1. always use ch=08h, never 48h
;--- 2. first try a level 4 lock, if this fails, a level 0 lock

    mov cx, 084Ah       ; this is for FAT12/FAT16
if 0
    cmp dword ptr [di+35h], 0
    jz @F
    mov ch, 48h
@@:
endif
    mov bl, [ioreq.bDrive]
    inc bl
;--- DX seems to have no meaning???
    mov dx, 0ffffh      ; permission flags (bit 0: 1=allow writes)

    mov bh, 4           ; lock level (0-4)
    mov ax, 440Dh
    int 21h
    jnc @F
    mov bh, 0
    mov ax, 440Dh
    int 21h
    jc dontlock
@@:
;    mov [unlockdrv], bl
dontlock:
    mov dl, RWF_NEWLOGICAL
donesetlog:
    mov [ioreq.rwfunc], dl
    ret
olddpb:
    mov dl, [ioreq.bDrive]
    inc dl
    mov ah, 32h         ; preFAT32 getdpb function
    int 21h
    mov dl, RWF_OLDLOGICAL
    cmp al, 00
    jnz donesetlog
    mov ax, [bx+2]
    push ss
    pop ds
    call setBps
    jmp donesetlog

setlogvars endp

;--- unlock a logical volume that was previously locked

if 0
unlock proc
    mov bl, 0
    xchg bl, [unlockdrv]
    cmp bl, 0
    jz done
    mov cx,  86Ah
    mov ax, 440dh
    int 21h
done:

    ret
unlock endp
endif

;--- set wBps and bSecSh variables

setBps proc
    cmp ax, 1
    jc done
    cmp ax, sizeof sectbuffer + 1 ; refuse sector sizes beyond 4 kB
    cmc
    jc done
    mov [wBps], ax     ;0x200 -> 9, 0x100 -> 8
    mov [bSecSh], 0
    mov cl, 0
@@:
    shr ax, 1
    jz @F
    jc done
    inc cl
    jmp @B
@@:
    mov [bSecSh], cl
    clc
done:
    ret
setBps endp

;--- set parameters for physical drive access
;--- in:  [ioreq.bDrive]
;--- out if successful:
;---      [ioreq.rwfunc]
;---      [wBps]
;---      [dwDataend]
;---      [cylinders], [heads], [sectors]

setphysvars proc

    mov [dapacket.bSize], sizeof DAP
    mov [dapacket.sectors], 1           ; default: one sector to transfer
    mov dl, [ioreq.bDrive]              ; check if int 13h extensions are implemented
    test dl, 80h
    jz use1308
    mov bx, 55AAh
    mov ah, 41h
    @int13
    jc use1308
    cmp bx, 0AA55h
    jnz use1308
    test cl, 1                          ; AH=42h/43h supported?
    jz use1308

    mov si, offset diskinfobuffer
    mov [si].DINFO1._size, sizeof DINFO1
    mov dl, [ioreq.bDrive]
    mov ah, 48h                         ; get drive parameters
    @int13
    jc use1308

    mov eax, [si].DINFO1.totalsecL
ife ?SN64                               ; HUGE hd support?
    dec eax
else
    mov edx, [si].DINFO1.totalsecH
    sub eax, 1
    sbb edx, 0
    mov [dwDataendH], edx
endif
    mov [dwDataend], eax
    mov ax, [si].DINFO1.bps
    call setBps
    jc secsizeerror 
    mov ax,word ptr [si].DINFO1.cyls
    mov bl,byte ptr [si].DINFO1.heads
    mov cl,byte ptr [si].DINFO1.secs
    mov [cylinders], ax
    mov [heads], bl
    mov [sectors], cl
    mov [ioreq.rwfunc], RWF_NEWINT13
    clc
    jmp done
secsizeerror:
    mov dx, offset secsizetoobig
    call printerror
    stc
    ret
use1308:
    mov dl, [ioreq.bDrive]
    xor di, di                          ; ES:DI=0000:0000 (bios bug)
    mov es, di
    mov ah, 08h
    @int13
    jc done
    cmp dl,1
    jc done
    inc dh
    mov [heads], dh
    mov [sectors], cl
    and [sectors], 00111111b
    and cl,3
    xchg cl,ch
    mov [cylinders], cx
    mov ax, 512
    call setBps
    movzx eax, [cylinders]              ; CHS -> LBA
    movzx ebx, dh                       ; heads*cylinders
    mul ebx
    add eax, ebx                        ; + heads
    mov bl, [sectors]
    mul ebx                             ; * sectors
    dec eax                             ; - 1
    mov [dwDataend], eax
    mov [ioreq.rwfunc], RWF_OLDINT13
done:
    ret

setphysvars endp

;--- disk change. obtain all info
;--- IN:   [ioreq.drvtype], [ioreq.bDrive] & [ioreq.rwfunc]
;--- sector 0 read in sectbuffer
;--- for logical devices: disk type may be FAT, NTFS, EXFAT

setvariables proc
    call setseeds2

    mov [filesys], FS_UNDEFINED         ; reset FAT type

    cmp [ioreq.drvtype], DT_CDROM
    je cdsetvars
    cmp [ioreq.drvtype], DT_FILE        ; file access?
    je filesetvars
    cmp [ioreq.drvtype], DT_PHYSICAL
    jne logicalsetvars

    push ds                             ; sets variables p1-p4
    pop es                              ; for jumping to partitions
    mov di, offset partitions           ; on physical drives
    mov si, offset sectbuffer + 1c6h
    mov cx, 4
@@:
    movsd
    add si, 0Ch
    loop @B
    ret

cdsetvars:
    mov bx, 50h
    cmp [ioreq.rwfunc], RWF_CDCOOKED
    je @F
    add bx, 18h
@@:
    mov eax, dword ptr [sectbuffer+bx]
    sub eax, CD_SECTOR_OFFSET+1
    mov [dwDataend], eax
    ret

logicalsetvars:
    xor eax, eax
    mov [dwRootCluster], eax                  ; default root cluster = 0

;--- get file system
;--- no DOS functions can be used here, 
;--- since under pure DOS we won't have a valid drive letter.
;--- all information must be read from the boot sector

    mov si, offset sectbuffer

    mov eax, [si+3]
    cmp eax, "SFTN"
    jz isntfs
    cmp eax, "AFXE"
    jnz assumefat
    mov eax, [si+7]
    cmp eax, "   T"
    jz isexfat
assumefat:

    cmp [ioreq.rwfunc], RWF_FILE              ; image file?
    jnz @F
    mov ax, [si].BPB.bytes_sector             ; then use sector size from boot sector ( if it's a real
    call setBps                               ; physical/logical drive, we already got it )
    jc secsizeerror
@@:
    mov al, [si].BPB.sectors_cluster          ; sectors per cluster
    mov [bSpC], al

    mov dl, 0FFh
@@:
    inc dl
    shr al, 1
    jnz @B
    mov [bSpCshift], dl

    movzx eax, [si].BPB.reserved_sectors      ; number of reserved sectors
    mov [dwReserved], eax
    mov al, [si].BPB.num_fats                 ; number of fat tables
    mov [bFats], al
    mov ax, [si].BPB.root_entries             ; maximum number of root entries
    mov [rootentries], ax
    shr ax, 4                                 ; 16 entries in one sector
    mov [wRootsectors], ax                    ; # of entries/16 = # of sectors

    mov ax, [si].BPB.sec_per_fat1x            ; sectors/fat (fat12/fat16)
    test ax, ax
    jnz @F
    mov eax, [si].EBPB_FAT32.sec_per_fat32    ; if fat32
@@:
    mov [dwSpF], eax

    movzx eax, [si].BPB.sectors_fat12         ; sectors in partition
    test ax, ax                               ; < 32 MB?
    jnz @F
    mov eax, [si].BPB.sectors_fat1632
@@:
    dec eax
    cmp [ioreq.rwfunc], RWF_FILE              ; don't set dwDataend if image file
    jz @F
    mov [dwDataend], eax
@@:
    sub eax, [dwSpF]
    cmp [bFats], 2
    jb skipsub2
    sub eax, [dwSpF]
skipsub2:
    sub eax, [dwReserved]

    movzx ebx, [wRootsectors]
    sub eax, ebx
    mov cl, [bSpCshift]
    shr eax, cl

    mov [filesys], FS_FAT32
    cmp eax, 65525
    jae goodnumcluster                  ; jump if not fat16 or less
    mov [filesys], FS_FAT16
    cmp eax, 4085
    jae goodnumcluster                  ; jump if not fat12
    mov [filesys], FS_FAT12
goodnumcluster:
    add eax, 2
    mov [dwLastCluster], eax

    mov eax, [dwSpF]
    movzx ebx, [bFats]
    mul ebx
    add eax, [dwReserved]               ; spf * fats + reserved = root
    mov [dwRootSect], eax

    cmp [filesys], FS_FAT32
    jne not_fat32

    push eax
    mov al, [si].EBPB_FAT32.phys_drive    ; hard drive number
    mov [hdnumber], al
    mov ax, [si].EBPB_FAT32.bs_copy_start ; backup boot sector
    mov [backupbs], ax
    mov ax, [si].EBPB_FAT32.fs_info_start ; filesystem info sector
    mov [fsinfo], ax
    movzx ax, [bSpC]
    mov [wRootsectors], ax
    mov eax, [si].EBPB_FAT32.root_startcl
    mov [dwRootCluster], eax

    sub eax, 2
    jc wrongrootc
    mov cl, [bSpCshift]
    shl eax, cl
    add [dwRootSect], eax
wrongrootc:
    pop eax
    jmp isfat32

not_fat32:

    mov al, [si].EBPB.phys_drive        ; hard drive number
    mov [hdnumber], al
    movzx eax, [wRootsectors]
    add eax, [dwRootSect]               ; calculate start of data area

isfat32:

    cmp eax, [dwRootSect]
    jne datastartiscorrect
    mov bl, [bSpC]
    add eax, ebx
datastartiscorrect:
    mov [dwDataStart], eax

    mov eax, [dwReserved]
    add eax, [dwSpF]
    mov [dwFat1end], eax                ; calculate end of fat 1 area

    movzx eax, [wBps]                   ; calculate bytes per cluster
    mov bl, [bSpC]
    mul ebx
    mov [dwBpC], eax
donegetvars:
    ret

isntfs:
    mov [filesys], FS_NTFS
    mov eax, [si+28h]
    dec eax
    mov [dwDataend], eax
    mov al, [si].BPB.sectors_cluster
    mov [bSpC], al
    mov ecx, [si][30h]   ; it's actually a qword
    movzx eax,al
    mul ecx
    mov [dwRootSect], eax
    mov [dwReserved], eax
    ret

isexfat:
    mov [filesys], FS_EXFAT
    mov eax, dword ptr [si].EXFAT.dqSize+0
ife ?SN64
    dec eax
else
    mov edx, dword ptr [si].EXFAT.dqSize+4
    sub eax, 1
    sbb edx, 0
    mov [dwDataendH], edx
endif
    mov [dwDataend], eax
    mov eax, [si].EXFAT.dwFatOfs
    mov [dwReserved], eax
    mov eax, [si].EXFAT.dwFatSiz
    mov [dwSpF], eax
    add eax, [dwReserved]
    mov [dwFat1end], eax
    mov eax, [si].EXFAT.dwClHpOfs
    mov [dwDataStart], eax
    mov eax, [si].EXFAT.dwClCnt     ; cluster count
    inc eax                         ; +1, since clusters start with #2
    mov [dwLastCluster], eax        ; and we need the last valid cluster#
    mov al, [si].EXFAT.bNumFats
    mov [bFats], al
    mov eax, [si].EXFAT.dwRootCl
    mov [dwRootCluster], eax

;--- here we use bytes/sector from boot sector - but this should actually
;--- be done only if the device is an image file ( rwfunc == RWF_FILE )
    mov ax, 1
    mov cl, [si].EXFAT.bBpSShift 
    shl ax, cl
    call setBps
    jc secsizeerror

    mov al, 1
    mov cl, [si].EXFAT.bSpCShift 
    mov [bSpCshift], cl
    shl al, cl
    mov [bSpC], al
    movzx edx, [wBps]
    movzx eax, al
    push eax
    mul edx
    mov [dwBpC], eax
    pop eax
    mov edx, [dwRootCluster]
    sub edx, 2
    mul edx
    add eax, [dwDataStart]
    mov [dwRootSect], eax
    movzx ax, [bSpC]
    mov [wRootsectors], ax        ; [wRootsectors] just one cluster!
    ret
secsizeerror:
    mov dx, offset secsizetoobig
    call printerror
    ret

filesetvars:
    mov eax, [dwRwfilesize]
    shr eax, 9                    ; bytes/sector is 512 as long as image file is "physical"
    jz @F
    dec eax
@@:
    sub eax, [dwDrivestart]
    mov [dwDataend], eax
    ret

setvariables endp

;-------------------------------------------------------

;*******************************************************
; CALLS
;*******************************************************
include FATFS.INC
;-------------------------------------------------------

printchs proc

    call printstring
    mov [highlight.ofs], bx

    movzx eax, byte ptr [si+bx+3]
    mov ah, byte ptr [si+bx+2]
    shr ah, 6
    add [highlight.ofs], 2
    mov [highlight.siz_], 2
    call printeaxvalue_hl

    mov dl, '/'
    call printchar

    movzx eax, byte ptr [si+bx+1]
    dec [highlight.ofs]
    mov [highlight.siz_], 1
    call printeaxvalue_hl

    mov dl, '/'
    call printchar

    movzx eax, byte ptr [si+bx+2]
    and al, 111111b
    inc [highlight.ofs]
    jmp printeaxvalue_hl

printchs endp

;--- check if it's an exfat directory
;--- this check is currently not really fool-proved

IsExfatDir proc
    push cx
    xor bx, bx
    mov cx, [wBps]
    shr cx, 5          ; 32 bytes per entry
    mov dl, 0
nextitem:
    mov al, [si+bx].EXFDIRP.etype
    cmp al, 80h or EXFPTC_ALLOCBM
    jz ok
    cmp al, 80h or EXFPTC_UPCASET
    jz ok
    cmp al, 80h or EXFPTC_VOLLABEL
    jz ok
    cmp al, 80h or EXFPTC_FILE
    jz ok
    cmp al, EXFSTCF_STREAM
    jz isc0
    cmp al, EXFSTCF_NAME
    jz isc1
    test al, 80h
    jnz notfound
addrnext:
    add bx, DIRENTSIZE
    loop nextitem
    cmp dl, 1          ; at least 1 "in use" entry must have been found
    pop cx
    ret
ok:
    inc dl
    jmp addrnext
isc0:                  ; secondary stream entry must directly follow primary file
    and bx, bx
    jz ok
    cmp [si+bx-DIRENTSIZE].EXFDIRP.etype, 80h or EXFPTC_FILE
    jz ok
    jmp notfound
isc1:                  ; secondary name entry must follow 0C0h or 0C1h entry
    and bx, bx
    jz ok
    cmp [si+bx-DIRENTSIZE].EXFDIRP.etype, EXFSTCF_NAME
    jz ok
    cmp [si+bx-DIRENTSIZE].EXFDIRP.etype, EXFSTCF_STREAM
    jz ok
notfound:
    pop cx
    stc
    ret

IsExfatDir endp

;--- scan read buffer if it contains a directory (FAT type)
;--- IN: SI=sector buffer
;--- OUT: not found: carry set
;---      found    : carry cleared
;--- must preserve DX, CX

IsDirectory proc

    cmp [filesys], FS_EXFAT
    jz IsExfatDir

    push cx

    xor bx, bx
    cmp byte ptr [si+bx], 0
    je notfound

;flok:
;    mov ch, byte ptr [wBps+1]          ; 16 entries every 512 bytes
;    shl ch, 4                          ; this puts 16 in ch if bps is 512

    mov ch, 512 / DIRENTSIZE

nextentry:

;    cmp byte ptr [si+12+bx], 0         ; NT series *does* use this byte,
;    jne notfound                       ; so it may not be 0 on drives that
;                                       ; have been messed with by NT
    mov cl, 10

    cmp byte ptr [si+bx], 0             ; first byte zero?
    je allzero

    test byte ptr [si+bx+DIR_ATTRIBUTES], 11000000b
    jnz notfound                        ; top two bits of attribute are
                                        ; reserved.  can't be used.
    cmp byte ptr [si+bx+DIR_ATTRIBUTES], 0Fh
    je lfn                              ; if attribute is 0F, then it's lfn

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
    test byte ptr [si+bx+DIR_ATTRIBUTES], VOLUME     ; can't also be a label.
    jnz notfound
    cmp dword ptr [si+bx+DIR_FILESIZE], 0            ; filesize must = 0   
    jne notfound
entrynotdirectory:

    cmp byte ptr [si+bx], 20h           ; first character cannot be a space
    je notfound
    cmp byte ptr [si+bx], 0E5h          ; first character can be E5h (del'd)
    je charok
nextchar:
    mov al, byte ptr [si+bx]
    call extvalidfilechar
    jc notfound
charok:
    inc bx
    dec cl
    jnz nextchar
    jmp donextentry

lfn:

    cmp word ptr [si+bx+DIR_CLUST_LOW], 0         ; low cluster word must = 0
    jne notfound                                  ; for long file names

    mov al, byte ptr [si+bx]

;    cmp al, 0ffh                                  ; wtf?
;    je nextletter
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
;    mov ax, bx                         ; odd sector size support
;    shr ax, 9
;    mov [sectofs], al

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
    mov cl, DIRENTSIZE
allzero2:
    cmp byte ptr [si+bx], 0
    jne notfound
    inc bx
    dec cl
    jnz allzero2
    dec ch
    jnz allzero
    jmp founddir

IsDirectory endp

;-------------------------------------------------------
spaceandcolon:                    ; i don't like this function, it was created
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

;--- read file to restore sectors/cluster/FAT/root/... (but not "restore chain")
;--- IN: eax = start sector
;---    [dwValue] = # of sectors to write
;---    [dwFilesize] = size of file to read
;--- OUT: sectors written to disk from file

readfile proc
;    mov dx, offset restoremsg
;    call printbottom

    mov edx, eax
    add edx, [dwValue]
    jc invalidperror
    dec edx
    cmp edx, [dwDataend]
    ja invalidperror

    push eax
    mov eax, [dwValue]
    movzx edx, [wBps]
    mul edx
    cmp [dwFilesize], eax
    pop eax

    mov dx, offset toosmall
    jb nuprinterror

    mov [handling], QUERY_SKIP           ; inside readfile

;    push [dwCurSector]

    mov [ioreq.dwSector], eax
    call openfilero
    mov dx, offset filenotfound
    jc error
    mov [wFilehandle], ax

readfileloop:

    mov ah, 3Fh                           ; read "one sector" of the file
    mov bx, [wFilehandle]
    mov cx, [wBps]
    mov dx, offset sectbuffer
    int 21h
    jnc noreaderror
    mov dx, offset errorread
error:
    call printerror
    stc
    jmp donefileread

noreaderror:

    call writesect
    jc donefileread

    inc [ioreq.dwSector]

    call checktime
    jc continue_loop
    call checkabort
    jne @F
    mov dx, offset abortdmsg              ; "abort writing to disk"
    call nuprinterror
    stc
    jmp donefileread
@@:
    mov eax, [dwValue]
    mov cx, offset restoremsg
    call printprogress
continue_loop:
    dec [dwValue]
    jnz readfileloop
    clc
donefileread:
;    pop [ioreq.dwSector]
    pushf
    call closefile
    mov [handling], ABORT_OPERATION       ; inside readfile
    call readcursect
    popf
    jc @F
    mov [menustackidx], 0                 ; if file op was successful, go back to main menu
    call updatescreen                     ; let the user see the new content
    mov dx, offset donewritedisk
    call nuprinterror
@@:
    ret
readfile endp

;-------------------------------------------------------
printentry proc                         ; prints the fat entry the cursor
    cmp [bRegion], RG_FAT               ; is currently in, in the top
    jne abortentry                      ; right of the screen

    call getentrynumber
    mov [scrn_col], 52
    mov dl, 8
    test eax, 0ffff0000h
    jnz @F
    test [filesys], FS_FAT32
    jnz @F
    mov dl, 4
    add [scrn_col], 4
@@:
    call rendernumhex
    call printstring

abortentry:
    ret
printentry endp
;-------------------------------------------------------
getkey:
    mov ah, 10h    ; use 10h instead of 00 to get ctrl-up, ctrl-dn, ... codes
    int 16h
    ret

;--- transform spot in dx to scrn_xy-value for ascii output

aspotcalc:
    and dh, 00000001b             ; max spot is 1FFh
    shl dx, 4                     ; set row pos in DH (0-15)
    shr dl, 4                     ; restore dl
    add dl, COLASC
;    inc dh
    add dh, ROWXXX                ; lines start at 1
@ret:
    ret

;-------------------------------------------------------
; enter a decimal value.
; used to enter sectors (# or count).
; IN:         EAX: maximum allowed value
;              DX: string to print at bottom line
; OUT:
;     if NC:  ECX / [dwValue]: returned value
;     if  C:  ESC pressed

getdecvalue proc

    call printbottom
    mov [dwMaxvalue], eax
    sub sp, 80-8
    mov di, sp
    mov byte ptr [di],0
tryagain:
    invoke getstring, di, 80-8, 0, 80-8, offset @ret
;--- returns ax=chars, dx=cursor ofs
    mov cx, ax
    jcxz abort
    mov si, sp
    push cx
    push cx
    pop ecx
nextblank:
    lodsb
    cmp al,' '                 ; skip leading blanks
    loopz nextblank
    inc cx
    dec si
    xor ebx, ebx
nextchar:
    lodsb
    cmp al, '9'
    ja invalkey
    cmp al, '0'
    jb invalkey
    movzx edx, al
    sub dl, '0'

    cmp ebx, 0ffffffffh / 10
    jnc invalvalue
    lea ebx, [ebx][ebx*4]
    shl ebx, 1
    add ebx, edx
    loop nextchar
donevalue:
    cmp ebx, [dwMaxvalue]
    ja invalvalue
    mov ecx, ebx
    mov [dwValue], ecx
    add sp, 80-8
    ret
abort:
    add sp,80-8
    stc
    ret
invalkey:
    dec si
@@:               ; skip trailing blanks
    lodsb
    cmp al, ' '
    loopz @B
    jz donevalue
invalvalue:
    mov ax, 0E07h
    int 10h
    jmp tryagain

getdecvalue endp

;--- display some values on line 0 (sector#, cluster#, ... )

printtopline proc
    pushad
    mov [scrn_xy], 0021           ; set row 0, col 21
    mov [bRegion], RG_UNDEFINED
    mov eax, [dwCurSector]

    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("%lu"), eax
    call printstring

    mov cl, 36
    sub cl, [scrn_col]
    call fillspace
    add [scrn_col], cl

;    mov [scrn_col], 36

    mov eax, [dwCurSector]

    cmp [ioreq.drvtype], DT_PHYSICAL
    je inphysical
    cmp [ioreq.drvtype], DT_CDROM
    je indata

    mov edx, [dwReserved]          ; [dwReserved] is initialized in FS_NTFS and FS_EXFAT
    cmp eax, edx
    jb inreserved

    test [filesys], FS_FATXX
    je indata

    movzx cx, [bFats]
    jcxz notinfat
anotherfat:
    add edx, [dwSpF]
    loop anotherfat
    cmp eax, edx
    jb infat

notinfat:                          ; not in reserved and not in fat
    mov edx, [dwRootSect]
    cmp eax, edx
    jb indata
    movzx ebx, [wRootsectors]
    add edx, ebx
    cmp eax, edx
    jae indata

    mov [bRegion], RG_ROOT

    mov dx, offset inrootmsg             ; "[root]
    test [filesys], FS_FAT32             ; root in data region?
    jnz dispclust

continuecount:
    call printstring
abortdc:
    mov cl, RIGHTCOL                     ; clear to last column
    sub cl, [scrn_col]
    call fillspace
    cmp [ioreq.drvtype], DT_PHYSICAL
    jne done
    mov [scrn_xy], 003Fh
    mov eax, [dwCurSector]
    cmp [ioreq.rwfunc], RWF_NEWINT13
    jnz @F
    test [diskinfobuffer.flags], 2   ;CHS valid?
    jz done
@@:
    call getchsx
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("CHS: %u/%u/%u"), ax, bx, cx
    call printstring
done:
    popad
    ret

inreserved:
    mov [bRegion], RG_RESERVED
    mov dx, offset inreservedmsg
    jmp continuecount

infat:
    mov [bRegion], RG_FAT
    push [scrn_xy]
    call printentry
    pop [scrn_xy]
    mov dx, offset infatmsg           ; "[FAT-"
    call printstring
    mov dl, '1'
    mov eax, [dwFat1end]
    cmp [dwCurSector], eax
    jb firstfat
    mov dl, '2'
firstfat:
    call printchar
    mov dl, ']'
    call printchar


    test [filesys], FS_FATXX
    je abortdc
    mov cl, 45
    test [filesys], FS_FAT32
    jnz @F
    mov cl, 49
@@:
    mov dl, cl
    sub cl, [scrn_col]
    call fillspace
    mov [scrn_col], dl
    mov dx, offset entrymsg           ; "Entry: "
    call printstring
    mov [scrn_col], 60
    jmp abortdc

setmbrview:
    mov [bRegion], VM_MBR
    mov dx, offset inmbrmsg
    call printstring
    jmp abortdc

inphysical:
    cmp [ioreq.bDrive], 80h           ; lower than 80h?
    jb indata                         ; not an hd - no mbr.
    test eax, eax
    jz setmbrview

indata:
    mov dx, offset indatamsg
dispclust:
    call printstring
;    mov dl, SPACE
;    call printchar

    test [filesys], FS_FATXX
    je abortdc

    or [bRegion], RG_DATA

    mov eax, [dwCurSector]
    call sector2cluster
    mov dl, 7                         ; cluster has max. 7 hex digits (8 for exfat!)
    test eax, 0ffff0000h
    jnz @F
    test [filesys], FS_FAT32
    jnz @F
    mov dl, 4
@@:
    push dx
    call rendernumhex
    mov ax, dx
    pop dx
    add dl, 9   ; sizeof "Cluster: "
    neg dl
    add dl, 60
    mov cl, dl
    sub cl, [scrn_col]
    push ax
    mov al, SPACE
    call fillchar
    pop ax
    mov [scrn_col], dl
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("%s%s"), offset szCluster, ax
    jmp continuecount

printtopline endp

;--- convert content of eax to dec num
;--- out: DX = start of string (without leading zeros)
;---      valuebuffer: holds string

rendernumdec proc
    push si
    push ebx
    push eax
    mov si, offset valuebuffer+10
    mov ebx, 10
    mov byte ptr [si], 0
@@:
    dec si
    xor edx, edx
    div ebx
    add dl, '0'
    mov byte ptr [si], dl
    and eax,eax
    jnz @B
    mov dx, si
;    cmp si, offset valuebuffer-1
;    jnz @B
;    lea dx, [si+1]
    pop eax
    pop ebx
    pop si
    ret
rendernumdec endp

;--- convert content of eax to hex number
;--- in: EAX=value, DL=digits
;--- out: DX=start of string
;---      valuebuffer: holds string

rendernumhex proc
    push si
    push eax
    mov si, offset valuebuffer+9
    mov byte ptr [si], 0
nextchar:
    dec si
    mov dh, al
    and dh, 0Fh
    ror eax, 4
    add dh, '0'
    cmp dh, '9'                         ; if AL was less than 10
    jbe @F                              ; then it's a hex number
    add dh, 7                           ; otherwise it's a letter
@@:
    mov [si], dh
    dec dl
    jnz nextchar
    mov dx, si
    pop eax
    pop si
    ret
rendernumhex endp

;--- in: AL = bits to display
;--- out: DX=start of string
;---      valuebuffer: holds string

rendernumbin proc
    push bx
    mov bx, offset valuebuffer
    push bx
    mov dh, 8
nextbit:
    cmp dh, 4                           ; 4th bit?  put a space.
    jne @F
    mov byte ptr [bx], SPACE
    inc bx
@@:
    mov dl, '0'
    rol al, 1
    adc dl, 0
    mov [bx], dl
    inc bx
    dec dh
    jnz nextbit
    mov [bx], dh
    pop dx
    pop bx
    ret
rendernumbin endp

;--- turn cursor on, get a key, then turn cursor off again

cursorgetkey proc
    pusha
    mov bp, sp
    mov bh, [vidpg]
    mov dx, [scrn_xy]
    mov ah, 02h                   ; set cursor pos
    int 10h
    mov cx, 0808h                 ; make cursor visible
    mov ah, 01h
    int 10h
    call getkey
    mov [bp+14], ax
    mov cx, 2000h                 ; hide cursor again
    mov ah, 01h
    int 10h
    popa
    ret
cursorgetkey endp

;--- print string: dx -> string

printstring proc
    pusha
    mov si, dx
    call cbuffer_offset    ;setup ES:DI to current screen pos
printstrloop:
    lodsb
    cmp al, 0
    je done
    stosb
    inc di
    jmp printstrloop
done:
    mov ax, si
    sub ax, dx
    dec al
    add [scrn_col], al
    popa
    ret
printstring endp

;--- this routine prints out 512/128
;--- bytes in the read buffer at current sectofs

printsector proc
    call bufferinsi

    mov dx, [wBps]
    sub dx, [sectofs]
    mov [rembytes], dx

if 0
    cmp [spot], dx
    jb @F
    dec dx
    mov ax, dx
    mov dl, [bHL]
@@:
    xor eax, eax
endif

    mov [scrn_xy], COLASC or (ROWXXX shl 8)
    xor cx, cx            ; cx=spot
    push si
nextchar1:
    lodsb
    mov dl, al
    cmp cx, [rembytes]
    jb @F
    mov dl, SPACE
@@:
    call printchar
    inc cx
    test cl, 0Fh
    jnz @F
    inc [scrn_row]
    mov [scrn_col], COLASC
@@:
    cmp cx, VIEWBYTES
    jnz nextchar1
    pop si

    cmp [displaymode], DM_BINARY
    je displaybinval

    xor cx, cx
    mov [scrn_xy], COLHEX or ( ROWXXX shl 8 )
nextchar2:
    lodsb
    cmp cx, [rembytes]
    jb @F
    mov dl, '-'
    call printchar
    call printchar
    jmp donechar1
@@:
    ror al, 4
    call nibout
    ror al, 4
    call nibout
donechar1:
    inc cx
    inc [scrn_col]
    test cl, 03h
    setz al
    add [scrn_col], al
    test cl, 0Fh
    jnz @F
    inc [scrn_row]
    mov [scrn_col], COLHEX
@@:
    cmp cx, VIEWBYTES
    jne nextchar2
    jmp printaddresses
nibout:
    mov ah, al
    and al, 0Fh
    add al, 90h
    daa
    adc al, 40h
    daa
    mov dl, al
    mov al, ah
    jmp printchar

displaybinval:

;--- just 128 bytes are displayed in binary

    mov bx, [spot]
    and bl, 80h
    mov cx, bx
    add si, bx
    add bx, 128
nextchar3:
    lodsb
    mov dx, cx
    call nspotcalc
    mov [scrn_xy], dx

    cmp cx, [rembytes]
    jb @F
    mov al, '-'
    push cx
    mov cl, 4
    call fillchar
    add [scrn_col], 5
    call fillchar
    pop cx
    jmp donechar2
@@:
    call rendernumbin
    call printstring
donechar2:
    inc cx
    cmp cx, bx
    jne nextchar3

;--- display the 32 offsets at position 1 (6 digits)

printaddresses:
    mov [scrn_col], 1
    mov [scrn_row], 00h
    mov dx, offset offsetmsg
    call printstring                    ; 'Offset:'
    mov [scrn_col], 13
    mov dx, offset szSector
    call printstring                    ; 'Sector:'
    movzx eax, [sectofs]

    mov bx, 10h                         ; 16 bytes per line in hex mode
    mov cx, 32                          ; 32 vertical lines for editing
    cmp [displaymode], DM_BINARY
    jne nextaddress

    mov dx, [spot]
    and dl, 10000000b
    add ax, dx
    mov bx, 4                           ; 4 bytes per line in binary mode

nextaddress:
    call printcrlf
    mov dl,6
    call rendernumhex
    call printstring
    add ax, bx
    loop nextaddress
    ret
printsector endp

;--- print value of current offset in row 0, update the entry# in fatview
;--- and set the 2 cursor attributes

printoffset proc

    mov [scrn_xy], 0009
    call spot2bufofs                    ; bx = sectofs + spot
    mov ax, bx

    mov dl,3
    call rendernumhex
    call printstring

    call printentry                     ; if in FAT, print current entry (=cluster)

    mov ax, [crsr_xy]
    mov [scrn_xy], ax
    jmp colorchar

printoffset endp

;-------------------------------------------------------
decolorchar:
    pusha
    mov ax, COL_DEFAULT or (COL_DEFAULT shl 8)    ; ah & al = COL_DEFAULT
    jmp startcolorchar

;--- set the 2 cursors hex/ascii part
;--- current screen pos is at hex/binary cursor

colorchar proc
    pusha
    mov ax, COL_EDIT or (COL_HIGHLIGHT shl 8)

; in: aL = color for character being edited
;     aH = color for character cursor is on

startcolorchar::
    call cbuffer_offset

    cmp [editmode], EM_DEFAULT
    je ecolor1
    xchg al, ah
ecolor1:
    mov byte ptr es:[di+1], al

    push [scrn_xy]
    mov dx, [spot]
    call aspotcalc          ;calculate screen pos for ascii
    mov [scrn_xy], dx

    call cbuffer_offset
    mov byte ptr es:[di+1], ah
    pop [scrn_xy]
    popa
    ret

colorchar endp

;--- fill char in AL CL times
;--- (no screen pos update!)

fillspace:
    mov al, SPACE
fillchar:
    push di
    push cx
    call cbuffer_offset
@@:
    stosb
    inc di
    dec cl
    jnz @B
    pop cx
    pop di
    ret

;--- print cell in AX CL times
;--- (no screen pos update!)

fillcell:
    push di
    push cx
    call cbuffer_offset
@@:
    stosw
    dec cl
    jnz @B
    pop cx
    pop di
    ret

;--- print character in DL

printchar:
    push di
    call cbuffer_offset
    mov byte ptr es:[di], dl
    inc [scrn_col]
    pop di
    ret

;--- clear sector area (lines 1-32, colums 9-61)
clearsecarea proc
    les di, [vidaddr]
    mov bx, [vidcolsize]
    add di, bx
    add di, 2*9
    mov ax, COL_DEFAULT shl 8 or SPACE
    mov dl, 32
@@:
    push di
    mov cx, 52
    rep stosw
    pop di
    add di, bx
    dec dl
    jnz @B
    ret
clearsecarea endp

;-------------------------------------------------------
; vinit: - check/set video mode, print copyright info.
; runs in real-mode even for wdex.

vinit proc

;--- check if video mode suits, else set 43x80 mode.
    mov di, 0B800h
    push ds
    push 0
    pop ds
    mov ax, ds:[44Ah] ;cols
    add ax, ax
    mov bx, ds:[44Eh] ;start offset video page
    cmp byte ptr ds:[463h],0b4h           ; monochrome mode?
    jnz @F
    mov di, 0B000h
@@:
    mov ch, ds:[484h] ;rows-1
    mov dl, ds:[462h] ;video page
    inc ch
    pop ds
    cmp ch,43                             ; current mode compatible?
    jae vmode_ok
    mov ax, 1200h                         ; EGA or better present?
    mov bl, 10h
    xor cx, cx
    int 10h
    or cx, cx
    jz fth
    mov bl, 30h
    mov ax, 1201h                         ; AL=01: 350 scan lines in next mode set
    int 10h
    mov ax, 3
    or bh, bh                             ; bit 0=1 -> mono mode in effect
    jz @F
    mov al, 7
    mov di, 0B000h
@@:
    int 10h                               ; set video mode 3/7
    mov ax, 1112h
    mov bl, 0
    int 10h                               ; select font 8x8 ROM
fth:
    mov ax, 80*2
    mov ch, 43
    xor bx, bx
    mov dl, 0
vmode_ok:
    mov [vidcolsize], ax
    mov [vidrows], ch
    mov [vidpg], dl
    mov word ptr [vidaddr+0], bx
    mov word ptr [vidaddr+2], di

    call clearscreen

    mov cx, 2000h
    mov ah, 01h                           ; hide cursor
    int 10h

    mov [scrn_xy], 1423h                  ; print version
    mov dx, offset introtext
    call printstring
    mov [scrn_xy], 1612h                  ; print copyright
    mov dx, offset copyright
    call printstring

    ret
vinit endp

clearscreen proc
    mov dl, 43
    les di, [vidaddr]
    mov ax, COL_DEFAULT shl 8 or SPACE
@@:
    push di
    mov cx,RIGHTCOL+1
    rep stosw
    pop di
    add di, [vidcolsize]
    dec dl
    jnz @B
    ret
clearscreen endp

    .const

helptext label byte
    db 13,10
    db "usage: wde [ option ] [ disk ]",13,10
    db "   where <disk> may be:",13,10
    db "     logical drive: a letter followed by a colon ( C:|D:|... )",13,10
    db "     hard disk:     a digit ( 0|1|... )",13,10
    db "     floppy disk:   a digit followed by a 'f' ( 0f|1f|... )",13,10
    db "   if no (valid) disk is given, the user will be prompted for one.",13,10
    db "   <option> may be:",13,10
    db "     -?: display this help text and exit",13,10
if ?SAFEMODE
    db "     -s: safe mode; no write access to disk",13,10
endif
if ?MOUNT
    db "     -m<n>: mount partition <n> as logical drive",13,10
endif
    db '$'

    .code

printhelp proc
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("%s %s$"), offset introtext, offset copyright
    mov ah, 9
    int 21h
    mov dx, offset helptext
    mov ah, 9
    int 21h
    mov ax, 4C00h
    int 21h
printhelp endp

;--- translate sector# in eax to 
;--- cylinder in cl[6.7]+ch, head in DH, sector in cl[0..5]
;--- modifies ecx, ebx, edx, eax

getchs proc
    movzx ecx, [heads]
    movzx ebx, [sectors]
    imul ebx, ecx      ;heads * sectors = sectors per cylinder

    xor edx, edx
    test ebx, ebx
    jz @F
    div ebx          ; gives cylinders in eax
@@:
    mov cl, ah
    shl cl, 6
    mov ch, al

    mov eax, edx
    xor edx, edx
    movzx ebx, [sectors]
    cmp bl, 0
    je @F
    div ebx
@@:
    mov dh, al
    inc dl
    and dl, 00111111b
    or cl, dl
    ret
getchs endp

;--- this routine is better and should replace getchs
;--- returns CHS in ax,bx,cx

getchsx proc
    movzx cx, [heads]
    movzx bx, [sectors]
    cmp bl,0
    jz @F
    imul bx, cx      ;heads * sectors = sectors per cylinder
    shld edx, eax, 16
    test bx, bx
    jz @F
    div bx           ; gives cylinders in eax
    push ax
    mov ax, dx
    xor dx, dx
    movzx cx, [sectors]
    div cx
    mov bx, ax      ; gives heads in bx
    mov cx, dx
    inc cx
    pop ax
@@:
    ret
getchsx endp


;--- generic write access.
;--- unlike readsect, [ioreq.pBuffer] may be set by caller of writesect()
;--- and [dwCurSector] is not modified.
writecursect:
    push [dwCurSector]
    pop [ioreq.dwSector]
writesect:
if ?SAFEMODE
    cmp [bSafe], 1   ;clears CF
    jz @F
endif
    mov [ioreq.bRW], RW_WRITE
    jmp diskaccess
if ?SAFEMODE
dummywrite:
    ret
endif

;--- generic read access. updates [dwCurSector] if read was successful

readsect:
    call diskaccess_read
    jc @F
    push [ioreq.dwSector]
    pop [dwCurSector]
@@:
    ret

;--- readcursect "rereads" current sector

readcursect:
    push [dwCurSector]
    pop [ioreq.dwSector]
diskaccess_read:
    mov [ioreq.pBuffer], offset sectbuffer
    mov [ioreq.bRW], RW_READ

; diskaccess handles all sector reading and writing in WDe for all disk types
;       IN:     [ioreq.bRW]      = 0=read, 1=write
;               [ioreq.dwSector] = the sector number to read
;               [ioreq.pBuffer]  = buffer for transfer
;               [handling]       = what to do when sector read/write fails
;       OUT:    NC/C             = success or fail
;                                  read: sector into [ioreq.pBuffer]
; variables that have been set when a disk was changed:  
;               [ioreq.bDrive]   = drive number to use
;               [ioreq.rwfunc]   = type of read/write function

diskaccess proc

    pushad

    .data
    align 2
acctab label word
    dw offset oldint13_access
    dw offset newint13_access
    dw offset int2x_access
    dw offset int2x_access
    dw offset cdrom_access
    dw offset cdrom_access
    dw offset file_access
    .code

    push ds
    pop es
    mov eax, [ioreq.dwSector]
    add eax, [dwDrivestart]
if ?SN64
    mov edi, [ioreq.dwSectorH]
    adc edi, [dwDrivestartH]
endif
    mov dx, [ioreq.pBuffer]
    movzx bx, [ioreq.rwfunc]
    shl bx,1
    call [bx+acctab]
    jc @F
    popad
    ret
@@:
    call access_error
    popad
    ret

;------------------------------

int2x_access:

    mov cx, -1
    lea bx, drivepacket
    mov [bx.DISKIO.startsec], eax         ; set sector #
    mov [bx.DISKIO.buffofs], dx
    mov [bx.DISKIO.buffseg], ds
    xor si, si                            ; 0 (read)
    cmp [ioreq.bRW], RW_WRITE
    jne @F                                ; default to reading for safety
    inc si                                ; 1 (write)
@@:
    cmp [ioreq.rwfunc], RWF_NEWLOGICAL
    je newlog_access

;--- access drive via int 25h/26h
;--- DS:BX -> disk read/write packet ( if CX == -1 )

oldlog_access:
    mov al, [ioreq.bDrive]
    cmp [ioreq.bRW], RW_WRITE
    je @F
    @int25
    ret
@@:
    @int26
    ret

;--- use new DOS 7 function
;--- DS:BX -> disk package, same as for int 25h/26h

newlog_access:
    mov dl, [ioreq.bDrive]
    inc dl
    mov ax, 7305h                       ; extended sector read/write
    @int21
    ret

;--- file image access

file_access:
    mov si, dx
    mov edx, [dwDataend]
    add edx, [dwDrivestart]
    cmp eax, edx
    ja fa_error

;    shl eax, 9                        ; always "sector size" 512 for files
    movzx edx, [wBps]
    mul edx
if 0                                  ; not needed, since dwDataend tells the file size
    mov edx, [dwRwfilesize]
    sub edx, 512
    cmp eax, edx
    ja fa_error
endif

    mov bx, [rwhandle]
    mov dx, ax                        ; offset into CX:DX
    shld ecx, eax, 16
    mov ax, 4200h                     ; seek from start of file
    int 21h

    mov ah, 3Fh                       ; read from file
    mov dx, si
    cmp [ioreq.bRW], RW_WRITE
    jne @F
    mov ah, 40h
@@:
    mov cx, [wBps]
    imul cx, [dapacket.sectors]
    mov bx, [rwhandle]
    int 21h
    ret
fa_error:
    stc
    ret

;--- read CDROM
;--- ES:BX -> device driver request header

cdrom_access:
    mov bx, offset cdheader
    add eax, CD_SECTOR_OFFSET         ; can't read first 10h sectors
    mov [bx].CDREQ.startsec, eax
    mov [bx].CDREQ.bufofs, dx
    mov [bx].CDREQ.cmd, 128           ; command code "read long"
    cmp [ioreq.bRW], RW_WRITE
    jne @F
    mov [bx].CDREQ.cmd, 134           ; "write long"
@@:
    clc                               ; fixes bug in Win9x
    movzx cx, [ioreq.bDrive]
    mov ax, 1510h                     ; cd-rom send device driver request in ES:BX
    @int2F
    jc ca_error                       ; device driver has not been called
    test byte ptr [bx].CDREQ.status+1, 80h ; check status word for error
    jnz ca_error
    ret
ca_error:
    stc
    ret

;--- read/write physical disk with extended int 13h functions (42h/43h)
;--- DS:SI -> disk address packet

newint13_access:
    lea si, dapacket
    mov [si].DAP.wBufferOfs, dx
    mov [si].DAP.wBufferSeg, ds         ; segment part of transfer address
    mov [si].DAP.dwStartLow, eax        ; set sector #
if ?SN64
    mov [si].DAP.dwStartHigh, edi
else
    mov [si].DAP.dwStartHigh, 0
endif

    mov dl, [ioreq.bDrive]
    mov ah, 42h
    cmp [ioreq.bRW], RW_WRITE
    jne @F
    mov ax, 4300h + NEWINT13_WRITE_FLAG
@@:
    stc                         ; bug circumvention
    @int13
    sti                         ; interrupt flag sometimes disabled
    ret

;--- use int 13h, AH=02/03, AL=sectors to read/write
;--- ES:BX -> buffer address
;--- DL=drive, DH & CX cylinder/head/sector

oldint13_access:
    push dx
    call getchs                 ; translate sector to c/h/s in dh/cx
    pop bx
    mov dl, [ioreq.bDrive]
    mov al, byte ptr [dapacket.sectors]
    mov ah, 02 
    cmp [ioreq.bRW], RW_WRITE
    jne @F
    mov ah,03h
@@:
    @int13
    ret

diskaccess endp

;--- called if an error occured inside diskaccess
;--- in: [handling]

access_error proc
    mov dx, offset sectorrerror       ; "Error reading Sector"
    cmp [ioreq.bRW], RW_WRITE
    jne @F
    mov dx, offset sectorwerror       ; "Error writing Sector"
@@:
    cmp [handling], IGNORE_ERRORS     ; inside access_error
    je done
    cmp [handling], ABORT_OPERATION   ; inside access_error
    je sectorerror2

    mov bx, [lastbottomtext]          ; save current menu text in BX

    invoke sprintf, offset sprintfbuffer, dx, [ioreq.dwSector]
    mov dx, offset sprintfbuffer
    call printbottom

    mov dx, offset sectorrerror3      ; "abort, skip, ignore all"
    cmp [handling], QUERY_SKIP        ; inside access_error
    je @F
    mov dx, offset sectorrerror2      ; "abort, zero-fill"
@@:
    call printstring
gak:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je secterrhandle
    cmp al,'A'
    jb gak
    or al,20h
    cmp al, 'a'
    je secterrhandle
    cmp [handling], QUERY_SKIP        ; inside access_error
    je checkskip
    cmp al, 'z'
    jne gak
;itsZ:                                ; zero-fill
    push ds
    pop es
    mov di, [ioreq.pBuffer]
    xor al, al
    mov cx, [wBps]                    ; wBps always set?
    rep stosb
itsS:                                 ; skip
    mov dx, bx
    call printbottom                  ; restore previous menu line
    jmp done

checkskip:
    cmp al, 's'
    je itsS
    cmp al, 'i'
    jne gak
    mov [handling], IGNORE_ERRORS     ; inside access_error
    jmp itsS

sectorerror2:    ;if ABORT_OPERATION is set
if ?DEBUG
    push eax
    mov eax, [ioreq.dwSector]
    call rendernumdec
    pop eax
else
    invoke sprintf, offset sprintfbuffer, dx, [ioreq.dwSector]
    mov dx, offset sprintfbuffer
endif
    call nuprinterror
secterrhandle:
    stc
done:
    ret

access_error endp

;--- display error msg at menu line, then wait for a key press

printerror proc
if 0 ; most likely useless now
    push dx
    call updatescreen
    pop dx
endif
nuprinterror::
    call printbottom
    mov dx, offset errormsg
    call printstring
    call getkey
    stc
    ret
printerror endp

;--- check char if it is a valid filename char
validpathchar proc
ife ?LFN
    cmp al, BACK_SLASH
    je validchar
    cmp al, COLON
    je validchar
    cmp al, PERIOD
    je validchar
endif
validfileinputchar::              ; <--- called by undelete
    cmp al, 'a'                   ; lower case letters allowed in paths
    jb validfilechar
    cmp al, 'z'
    ja validfilechar
    jmp validchar
extvalidfilechar::                ; <--- called by IsDirectory
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

if ?LFN
;--- for LFN, check for valid first file char
;--- although: a dot as single char is invalid as a filename
;---
;------------ !"#$%&'()*+,-./0123456789:;<=>? 
VIC textequ <10100000000000010000000000101011b>
validfirstfilechar proc
    cmp al, '\'
    stc
    jz done
    cmp al, '@'
    jnc done
    push ax
    mov edx, VIC
    sub al, 20h    ; 00h-1Fh are invalid
    jc @F
    and eax, 1Fh   ; we check codes 20h-3Fh (and backslash) only
    bt edx, eax
@@:
    pop ax
done:
    ret
validfirstfilechar endp
endif

;--- get a filename entered in menu line
;--- IN:  AX: tabproc
;--- OUT: CX=length of filename
;---      AH=last key scan code (check for TAB)
;---      [filenamebuffer]
;---      ax/di/dx/cx modified

getfilename proc
    mov dx, offset szFile
    call printbottom
    mov di, offset filenamebuffer
if ?LFN
    invoke getstring, di, sizeof filenamebuffer, 0, 80 - sizeof szFile, ax
    mov cx, ax
else
    xor cx, cx
getkeyagain:
    call cursorgetkey

    cmp al, ENTER_KEY
    je done
    cmp al, ESCAPE_KEY
    je abort
    cmp ah, BACKSPACE_SCAN
    je backspace
    cmp ah, TAB_SCAN
    je handle_tab

    cmp cx, 68
    je getkeyagain

    call validpathchar
    jc getkeyagain

    mov dl, al
    call printchar

    mov byte ptr [di], al
    inc di
    inc cx
    jmp getkeyagain

backspace:  
    jcxz getkeyagain                    ; no characters left to delete
    dec cx
    call backcommon
    dec di
    jmp getkeyagain
handle_tab:
    cmp bl, 0                           ; TAB exits only if called by setdrive
    jnz getkeyagain
abort:
    xor cx, cx
done:
    mov byte ptr [di], 0                ; null-terminate filename
endif
    ret
getfilename endp

;-------------------------------------------------------
cbuffer_offset:                 ; take what's in [scrn_xy] and set es:di to address
    push ax                       ; of the respective byte in the screen buffer
    push dx
    les di,[vidaddr]
    movzx ax, [scrn_row]
    mul [vidcolsize]
    movzx dx, [scrn_col]
    add dx, dx
    add ax, dx
    add di, ax
    pop dx
    pop ax
    ret

;--- transform at least in 2-digit decimal number

rendernumdec2 proc
    call rendernumdec
    cmp dx, offset valuebuffer+8
    jbe @F
    dec dx
    mov [valuebuffer+8],'0'
@@:
    ret
rendernumdec2 endp

;--- print date
;--- in: si = buffer
;---     bx = dir entry start spot
;---     dx = offset
;--- it's a "word" date, year is since 1980 (7 bits, 1980+127)
;--- yyyyyyymmmmddddd

printdate proc
    push bx
    add bx, dx
    mov [highlight.ofs], bx
    movzx eax, word ptr [si+bx]
    mov word ptr [highlight.siz_], 0202h
    push ax
    shr ax, 5
    and ax, 1111b
    jnz @F
    inc ax
@@:
    cmp ax, 12
    jbe @F
    mov ax, 12
@@:
    call rendernumdec2
    call printdatepart

    mov dl, '-'
    call printchar
    mov [highlight.siz_], 1
    pop ax
    push ax
    and ax, 11111b
    jnz @F
    inc ax
@@:
    call rendernumdec2
    call printdatepart

    mov dl, '-'
    call printchar
    inc byte ptr [highlight.ofs]
    mov [highlight.scsiz], 4
    pop ax
    shr ax, 9
    add ax, 1980                          ; dates start at 1980
    call rendernumdec
    call printdatepart
    inc [scrn_col]
    pop bx
    ret

printdatepart:
    call bshighlight
    jmp printstring

printdate endp

;--- print time
;--- in: si = buffer
;---     bx = dir entry start spot
;---     cx = offset
;---     dx = msec offset (or 0)
;--- a "word" time, seconds*2
;--- hhhhhmmmmmmsssss

printtime proc
    push bx
    add bx, cx
    movzx eax, word ptr [si+bx]
    inc bx
    mov [highlight.ofs], bx
    mov word ptr [highlight.siz_], 0201h

    push dx
    push ax
    shr ax, 11        ; get "hour" in bits 0-4
    cmp ax, 23
    jbe @F
    mov ax, 23
@@:
    call rendernumdec2
    call bshighlight
    call printstring

    mov dl, ':'
    call printchar
    dec [highlight.ofs]
    inc [highlight.siz_]   ; "minutes" cover 2 bytes
    pop ax
    push ax
    shr ax, 5         ; get "minute" in bits 0-5
    and ax, 111111b
    cmp ax, 59
    jbe @F
    mov ax, 59
@@:
    call rendernumdec2
    call bshighlight
    call printstring

    mov dl, ':'
    call printchar
    pop ax
    pop dx

    and dx, dx
    je  nodec
    pop bx
    push bx
    add bx, dx
    mov cl, byte ptr [si+bx]
    cmp cl, 199
    jb @F
    mov cl, 199
@@:
    cmp dl, DIR_CREATEMSEC   ; fix! this code works for standard creation time only
    mov dl, cl
    jnz nodec
    dec [highlight.ofs]      ; size is 2, and msecs are just 1 byte before hh:mm:ss time
    jmp dobshl
nodec:
    dec [highlight.siz_]
    xor dx, dx
dobshl:
    and ax, 11111b        ; get "seconds*2" in bits 0-4
    cmp ax, 29
    jbe @F
    mov ax, 29
@@:
    shl ax, 1

    push ax
    mov ax, dx
    xor dx, dx
    mov bx, 10
    div bx
    mov dx, ax
    pop ax
    add ax, dx
    cmp ax, 59
    jbe @F
    mov ax, 59
@@:
    pop bx
    call rendernumdec2
    call bshighlight
    jmp printstring

printtime endp

;-------------------------------------------------------

nspotcalc proc                  ; IN:  dx = [spot]
    push ax                     ; OUT: dx = [scrn_xy]
    mov ax, dx

    cmp [displaymode], DM_BINARY
    je binaryspotcalc
    shr dx, 4                   ; for use with hex view
;    inc dl
    add dl, ROWXXX              ; ---calculates where the current
    mov dh, dl                  ; hex byte should be put on the
                                ; screen for the buffer offset ax
    and al, 00001111b

    mov dl, al                  ; dl = al*3 + al/4 + 10
    add dl, al
    add dl, al
    shr al, 2
    add dl, al
    add dl, COLHEX
    pop ax
    ret
binaryspotcalc:
    shr dl, 2
    and dl, 00011111b
    mov dh, dl
;    inc dh
    add dh, ROWXXX
    and al, 00000011b

    mov ah, 13
    mul ah
    mov dl, al
    add dl, COLBIN
    pop ax
    ret
nspotcalc endp
;-------------------------------------------------------
getyn:                          ; prints [Y/N] on the screen
    mov dx, offset ynmsg        ; carry flag set if 'Y'
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

;    call unlock
if ?VDD
;--- exit vdd on nt platforms
    call exitvdd
endif

if 0
    mov ax, 500h  ;select active page
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
    mov ah, [vidrows]
    dec ah
    mov al, 0
    mov [scrn_xy], ax
    push ax

    call cbuffer_offset
    mov ax, 07*100h+SPACE;07=white on black
    mov cx, RIGHTCOL+1
    rep stosw
  
    mov cx, 0808h       ;make cursor visible and set shape
    mov ah, 01h
    int 10h
    pop dx
    mov bh, [vidpg]
    mov ah, 2           ;set cursor pos to bottom line
    int 10h
endif
if ?PM
    @loadvec [oldint24]
    mov bl, 24h
    mov ax, 0205h
    int 31h
else
    mov ax, 2524h
    lds dx, [oldint24]
    int 21h
endif
    mov ax, 4c00h
    int 21h
doret:
    ret
quit endp

;--- print menu at bottom line.
;--- menu to print is last item on menu stack.

printmenu proc

    push ds
    pop es
    movzx bx, [menustackidx]
    shl bx, 2
    movzx si,[bx][menustack].bMenuStart
    add si, offset startmenudefs
    mov dl, [bx][menustack].bSpaces      ; number of spaces between each item
    mov dh, '1'
    mov ch, [bx][menustack].bMenuSize
    mov bx, offset sprintfbuffer
    push bx
nextmenuitem:
    mov ah, [si]       ; load menu string index
    inc si
    cmp ah, -2
    jz skipitem
    mov di, offset menustrings  ; scan menu string table
    inc ah
    jmp checkbl
nextitem:
    mov al, 0
    mov cl, -1
    repnz scasb
checkbl:
    dec ah
    jnz nextitem

    xchg di, bx                 ; store "Fx-" prefix
    mov al,'F'
    mov ah, dh
    stosw
    mov al, '-'
    stosb
@@:                             ; store the menu string
    mov al, [bx]
    stosb
    inc bx
    cmp al, 0
    jnz @B
    dec di
    mov al, SPACE               ; store spaces between menu items
    push cx
    movzx cx, dl
    rep stosb
    pop cx
    xchg bx, di
skipitem:
    inc dh                      ; increase function key number
    dec ch
    jnz nextmenuitem
done:
    mov byte ptr [bx], 0
    pop dx
    jmp printbottom             ; and finally print the menu

printmenu endp

;--- getstringprompt: used by findstring and fillstring
;--- in:  -
;--- out: string in stringbuffer
;---      CX = string length

getstringprompt proc
    cmp [bHexString], 1
    jnz @F
    mov [bHexString], 0
    mov stringbuffer[0], 0   ;clear string buffer
@@:
    mov dx, offset szString
    call printbottom
    mov di, offset stringbuffer
    invoke getstring, di, sizeof stringbuffer, 0, sizeof stringbuffer, offset @ret
    mov cx, ax
    ret
getstringprompt endp

    include getstrng.inc

;-------------------------------------------------------
backcommon:
    dec [scrn_col]
    mov dl, SPACE
    call printchar
    dec [scrn_col]
    ret
;-------------------------------------------------------
movecursor:             ; IN:   ax = new [spot]
                        ;       dl = new [bHL]
    push [crsr_xy]
    pop [scrn_xy]
    call decolorchar      ; remove cursors at old pos
    mov [spot], ax
    mov [bHL], dl
    mov dx, ax
    call nspotcalc
    add dl, [bHL]
    mov [crsr_xy], dx
    jmp printoffset       ; and print new offset & cursors
  
;-------------------------------------------------------

checkabort:             ; sets equal flag if escape key was pressed
    push ax
    push dx
    mov ah, 06h           ; direct input is used since it takes
    mov dl, 0ffh          ; keys off the keybuffer
    int 21h
    cmp al, ESCAPE_KEY
    pop dx
    pop ax
    ret

;-------------------------------------------------------
; sets viewmode to DL

checksetview proc
    cmp [viewmode], dl              ; check if the "view" mode
    je no_viewmode_change           ; is already set.
    mov [funcmf4], -2               ; hack: remove "undelete"
    mov [ldfileoptf7], -2           ; hack: remove "chain"
    mov [viewmode], dl              ; set new view
clearviewarea::
    les di, [vidaddr]
    mov cx, [vidcolsize]
    mov ax, VIEWROW                 ; start of "view" area
    mul cx
    add di, ax
    mov dl, 8
@@:
    push di
    push cx
    mov ax, COL_DEFAULT shl 8 or SPACE
    mov cx, RIGHTCOL+1
    rep stosw
    pop cx
    pop di
    add di, cx
    dec dl
    jnz @B
no_viewmode_change:
    ret
checksetview endp

;-------------------------------------------------------
getnos:                               ; 'get number of sectors' from the
    pushad                            ; user; don't allow 0 - if so
    mov eax, [dwDataend]              ; then abort.
    sub eax, [dwCurSector]
    inc eax
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset szNoOfSectors, eax
    call getdecvalue
    jc @F
    stc
    jecxz @F
    clc
@@:
    popad
    ret

;-------------------------------------------------------
printbottom:
    mov [scrn_xy], BOTTOMROW*100h + 01h
    mov [lastbottomtext], dx
    call printstring

;--- fall thru
;--- clear rest of bottom line

clearbottom:
    push cx
    push ax
    mov cl, RIGHTCOL+1
    sub cl, [scrn_col]
    call fillspace
    pop ax
    pop cx
    ret

;--- find file
;--- IN: filenamebuffer = filename
;--- OUT: carry flag set if no file found
;---      else [DTA]: find first data block
findfile:
    pusha
if ?LFN
    call openfilero
    jc @F
    mov bx, ax
    mov ah, 3Eh
    int 21h
@@:
else
    mov dx, offset filenamebuffer ; buffer in DS:DX
    mov cx, 47h                   ; file attr mask
    mov ax, 4e00h                 ; findfirst
    int 21h
endif
    popa
    ret
findfileX:
if ?LFN
    pusha
    call openfilero
    jc @F
    mov bx, ax
    mov ax, 4202h
    xor cx, cx
    xor dx, dx
    int 21h
    mov word ptr [dwFilesize+0], ax
    mov word ptr [dwFilesize+2], dx
    mov ah, 3eh
    int 21h
@@:
    popa
else
    call findfile
    jc @F
    push bx
    mov ah, 2fh                   ; gets the current dta in ES:BX
    int 21h
    mov edx, dword ptr es:[bx+1Ah]
    pop bx
    mov [dwFilesize], edx
@@:
endif
    ret
;-------------------------------------------------------
closefile:
    mov ah, 3eh
    mov bx, [wFilehandle]
    int 21h
    ret

;--- write file
;--- in: dword [dwValue] = number of sectors to save
;---     eax             = start sector
;---     [wFilehandle]   = file to write to
;---     di              = function to call for progress display
;--- out: C if error
;--- this function is called:
;---  1.  once per cluster in savechain ( save a fat/file chain )
;---  2.  once in savedata ( save sector range, bs, fat, root )
;---  3.  once in dumpiso ( which is also used to save a partition! )

writefile proc

    mov [ioreq.dwSector], eax

;--- optimization: use packets of 16 sectors ( 8kB) for file writing.
;--- use the heap for transfers ( it's not restricted to 4 kB )
    mov ax, [wBps]
    mov si, 1
    cmp ax, 512               ; skip optimization for CDROMs
    ja @F
    mov si, 16
@@:
    imul ax, si
    call allocmem
    jc exit
    mov [ioreq.pBuffer], ax
    mov [ioreq.bRW], RW_READ             ; tell discaccess that we want to read
    mov [handling], QUERY_FILL           ; inside writefile
    movzx esi, si

writefileloop:
    call checktime
    jc @F
    call checkabort
    je abort
    call di
@@:
    sub [dwValue], esi
    jnc @F
    add esi, [dwValue]
    mov [dwValue], 0
@@:
;--- set both physical/logical sectors
    mov [drivepacket].sectors, si
    mov [dapacket].sectors, si
    call diskaccess
    jc done

    mov cx, [wBps]
    imul cx, si                          ; bytes to write = sectorsize * sectors
    mov bx, [wFilehandle]
    mov dx, [ioreq.pBuffer]
    mov ah, 40h                          ; write to file
    int 21h
    jc errorwrite
    cmp ax, cx
    jb diskfullerr
    add [ioreq.dwSector], esi
    cmp [dwValue], 0
    jnz writefileloop
done:
;--- do not modify flags until RET!
    mov [handling], ABORT_OPERATION      ; inside writefile
    mov cx, 1
    mov [drivepacket].sectors, cx        ; reset both sector counts
    mov [dapacket].sectors, cx
    mov ax, offset sectbuffer
    xchg ax, [ioreq.pBuffer]
    call freemem                         ; restore heap ( won't change flags )
exit:
    ret

abort:
    mov dx, offset abortfmsg
    jmp wferror
errorwrite:
    mov dx, offset filewriteerr
    jmp wferror
diskfullerr:
    mov dx, offset diskfullmsg
wferror:
    call nuprinterror
    stc
    jmp done

writefile endp

;--- open a file, access mode in BL, name in filenamebuffer
;--- out: C if error
;---      NC ok, file handle in AX

openfilero:
    mov bl, 0
openfile proc
    mov dx, 1    ; DL, bit 0: 1=open if file exists

;--- entry used by createfile,
;--- then DX=10010b:
;---         bit 1: replace/open file if it exists
;---         bit 4: create file if it doesn't exist

screatefile::

;--- BH, bit 4=1: allow 4GB-1 file size
;---     bit 5=1: return error, no int 24h

    mov bh, 30h
    mov si, offset filenamebuffer
    xor cx, cx
if ?LFN
    mov ax, 716Ch
    stc
    int 21h
    pushf
    cmp ax, 7100h
    jz @F
    popf
    ret
@@:
    popf
endif
    mov ax, 6c00h
    int 21h
    ret
openfile endp

;---
;--- out: C if error

createfile proc
    call findfile               ; perhaps better to call openfile?
    jnc fileexists
ccreatefile:
    mov dx, 10010b              ; replace file if it exists, else create it
    mov bl, 1                   ; (0=ro,1=wo,2=rw access)
    call screatefile
    jc error
    mov [wFilehandle], ax
    ret

fileexists:
    mov dx, offset owmsg        ; "file exists - append/overwrite/cancel?"
    call printbottom
getaoc:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je doabortf
    or al, 20h
    cmp al, 'c'
    je doabortf
    cmp al, 'o'
    je ccreatefile
    cmp al, 'a'
    jne getaoc
    mov bl, 1                   ; (0=ro,1=wo,2=rw access)
    call openfile               ; append
    mov dx, offset filecreateerr
    jc error
    mov [wFilehandle], ax
    mov bx, ax                  ; seek from end of file
    xor dx, dx
    xor cx, cx
    mov ax, 4202h
    int 21h
    ret
error:
    mov dx, offset filecreateerr
    jmp @F
doabortf:
    mov dx, offset abortfmsg
@@:
    call printerror
    stc
    ret
createfile endp
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

;------------------------------------------------------
; gethexstring: used by menus "fill hex" and "find hex";
;               return a hex string entered by user.
; IN:   -
; OUT:  NC if ok
;       CX = count of characters entered
;       stringbuffer = hex string gotten

gethexstring proc
    cmp [bHexString], 1
    jnz @F
    mov [bHexString], 0
    mov stringbuffer[0], 0   ;clear string buffer
@@:
    mov dx, offset szHex
    mov di, offset stringbuffer
    call dogethex
    jc done
    mov bx, sp
    test cl,1
    jz @F
    push 0
@@:
nextdigit2:
    lodsb
    sub al, '0'
    cmp al, 9
    jbe @F
    or al, 20h
    sub al, 31h-10
@@:
    push ax
    loop nextdigit2
    mov si, bx
    mov di, offset stringbuffer
    push ds
    pop es
nextnibble:
    sub si, 4
    mov al, [si+2]
    shl al, 4
    or al, [si+0]
    stosb
    cmp si, sp
    jnz nextnibble
    mov sp, bx
    mov cx, bx
    sub cx, si
    shr cx, 2
    mov [bHexString], 1         ; hexstring in stringbuffer
done:
    ret

;------------------------------------------------------
; gethexvalue:  used by "jumpto cluster" and "fill inc/dec".
; IN:           EAX: maxvalue
;               DX:  prompt
; OUT:          NC if ok
;               EBX: value gotten


gethexvalue::
    mov [dwMaxvalue], eax
    sub sp, 80-8
    mov di, sp
    mov byte ptr [di], 0
    call dogethex
nexttry:
    jc done2
    xor ebx, ebx
nextdigit:
    lodsb
    sub al, '0'
    cmp al, 9
    jb @F
    or al, 20h
    sub al, 31h-10
@@:
    test ebx, 0f0000000h
    jnz invalvalue
    shl ebx, 4
    or bl, al
    loop nextdigit
    cmp ebx, [dwMaxvalue]                 ; value smaller or equal to maximum?
    ja invalvalue
    add sp, 80-8
    ret
done2:
    add sp, 80-8
    stc
    ret
invalvalue:
    mov si, sp
    push offset nexttry
    jmp inval

dogethex:
    call printbottom
dogethex2:
    invoke getstring, di, 80-8, 0, 80-8, offset @ret
    mov si, di
    mov cx, ax
tryagain:
    stc
    jcxz dogethex_ex
    mov dx, cx
@@:
    lodsb
    cmp al,' '                 ; skip leading blanks
    loopz @B
    inc cx
    dec si
    push cx
    push si
nextchar:
    lodsb
    cmp al, '0'
    jb invalchar
    cmp al, '9'
    jbe validchar
    or al, 20h
    cmp al, 'a'
    jb invalchar
    cmp al, 'f'
    ja invalchar
validchar:
    loop nextchar
    pop si
    pop cx
    clc
dogethex_ex:
    ret
invalchar:
    pop si
    pop cx
inval:
    mov ax, 0e07h   ; beep!
    int 10h
    jmp dogethex2

gethexstring endp

;-------------------------------------------------------
; OUT:  si -> offset to current sectofs buffer
;       ax = offset within sectbuffer

bufferinsi:
    mov si, offset sectbuffer
    add si, [sectofs]
    ret

;-----------------------------------------------------------------
; OUT:  BX = current offset within buffer

spot2bufofs:
    mov bx, [sectofs]
    add bx, [spot]
    ret

;--- called from:
;--- 1. recursechain ( ctrl-left while in FAT )
;--- 2. jumpcluster  ( ctrl-right while in FAT )
;--- 3. savechain    ( to save a FAT chain )
;--- 4. restorechain ( to restore a FAT chain )

getcurrententry:                ; IN:  [dwCurSector], [spot]
    call getentrynumber         ; OUT: eax = data stored at current entry
    mov ebx, eax                ;      ebx = current entry #
    jmp getfatentry             ;      other reg's corrupted

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

;-------------------------------------------------------
if ?DEBUG

debugviewmode:
    push edx

    mov [scrn_xy], (VIEWROW+0) * 100h + 1
    mov dx, CStr('EAX: ')
    call printregister

    mov [scrn_xy], (VIEWROW+1) * 100h + 1
    mov dx, CStr('EBX: ')
    mov eax, ebx
    call printregister

    mov [scrn_xy], (VIEWROW+2) * 100h + 1
    mov dx, CStr('ECX: ')
    mov eax, ecx
    call printregister

    mov [scrn_xy], (VIEWROW+3) * 100h + 1
    mov dx, CStr('EDX: ')
    pop eax
    call printregister

    mov [scrn_xy], (VIEWROW+4) * 100h + 1
    mov dx, CStr('SI:  ')
    movzx eax, si
    call printregister

    mov [scrn_xy], (VIEWROW+5) * 100h + 1
    mov dx, CStr('DI:  ')
    movzx eax, di
    call printregister

    mov [scrn_xy], (VIEWROW+6) * 100h + 1
    mov dx, CStr('SP:  ')
    movzx eax, sp
    call printregister

    mov [scrn_xy], (VIEWROW+0) * 100h + 34
    mov dx, CStr('Stored EAX: ')
    mov eax, [storedeax]
    call printregister

    mov [scrn_xy], (VIEWROW+1) * 100h + 34
    mov dx, CStr('Stored EBX: ')
    mov eax, [storedebx]
    call printregister

    mov [scrn_xy], (VIEWROW+2) * 100h + 34
    mov dx, CStr('Stored ECX: ')
    mov eax, [storedecx]
    call printregister

    mov [scrn_xy], (VIEWROW+3) * 100h + 34
    mov dx, CStr('Stored EDX: ')
    mov eax, [storededx]
    call printregister

    mov [scrn_xy], (VIEWROW+4) * 100h + 34
    mov dx, CStr('Stored SI:  ')
    movzx eax, [storedsi]
    call printregister

    mov [scrn_xy], (VIEWROW+5) * 100h + 34
    mov dx, CStr('Stored DI:  ')
    movzx eax, [storeddi]
    call printregister

    ret

printregister:
    invoke sprintf, offset sprintfbuffer, CStr("%s %10lu (%08lX)"), dx, eax, eax
    mov dx, offset sprintfbuffer
    call printstring
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

;--- in lengthy operations, check if some timer interrupts have passed
;--- to avoid too many displays. Currently at least 5 ticks should be passed,
;--- which results in about 4 display updates per second.

checktime proc
    push ax
    push ds
    mov ds,[_0000H]
    mov ax, ds:[46Ch]
    pop ds
    push ax
    sub ax, [lasttick]
    cmp ax, 5
    pop ax
    jc @F
    mov [lasttick], ax
@@:
    pop ax
    ret
checktime endp

;-------------------------------------------------------
myint24:        ; this is the new int 24h to catch any critical errors
    mov al, 3   ; abort operation code
if ?PM
    @iret
else
    iret        ; int 24h would otherwise crash WDe with Abort/Retry/Fail
endif
;-----------------------------------------------------------------

END Start
