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
?DEBUG           EQU 0  ; 1=debug displays on ( prints on stdout/debug terminal )
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
?GPT             EQU 1  ; 1=support GPT
?CRCGPT          EQU 1  ; 1=check if CRC in GPT is correct
?MBRENTER        equ 1  ; handle Enter while in MBR
?SETFILEDATETIME equ 1  ; 1=set file's date & time when saving a file chain
?NOPTION         EQU 1  ; 1=support cmdline option -n
?POSDIR          EQU 1  ; 1=support directory pos

TRUE  equ 1
FALSE equ 0

BOTTOMROW        equ 42 ; last row (menu, messages)
MAXCOL           equ 79 ; last col
ROWXXX           equ 1  ; row where all displays start
VIEWROW          equ 34 ; start of "view" area
COLHEX           equ  9 ; column where hex display starts
COLBIN           equ 10 ; column where binary display starts
COLASC           equ 63 ; column where ascii display starts

;--- top line columns
COLOFFST         equ  1 ; column where text "offset:" is displayed
COLOFFS          equ  9 ; column where value of offset is displayed
COLSECTORT       equ 14 ; column where text "sector:" is displayed
COLSECTOR        equ 22 ; column where value of sector is displayed
COLREGION        equ 35 ; column where region "[xxxx]" is displayed
COLENDHEX        equ 59 ; end hex area ( used to display "cluster: xxx" )
COLCHS           equ 63 ; column where CHS: c/h/s is displayed

COLBSV1          equ 23 ; bootsector view pos 1
COLBSV2          equ 63 ; bootsector view pos 2
VIEWBYTES        equ 32*16 ; 32 rows a 16 bytes

CD_SECTOR_OFFSET EQU 10h  ; can't read first 16 sectors of CDs
DIRENTSIZE       EQU 32   ; size of directory entry (FATxx + exFAT)
PTABOFS          equ 1BEh ; offset partititon table in MBR

DARKMASK         equ 0F700h
NORMMASK         equ 0FF08h

;--- colors for the display
ifdef ?MONO
COL_EDIT         EQU 70h         ; just use black/white/grey
COL_DEFAULT      EQU 0fh
COL_INACTIVE     EQU 07h
COL_HIGHLIGHT    EQU 0F0h
COL_ERROR        EQU 0fh
else
;COL_EDIT         EQU 0cah        ; light green on red
COL_EDIT         EQU 0B0h        ; black on light cyan
COL_DEFAULT      EQU 1fh         ; white on blue
COL_INACTIVE     EQU 17h         ; light grey on blue
COL_HIGHLIGHT    EQU 30h         ; black on dark cyan
COL_GREENFG      EQU 1Ah         ; light green on blue
COL_STATTEXT     EQU 17h         ; light grey on blue
COL_REDFG        EQU 1Ch         ; light red on blue
COL_YELLOWFG     EQU 1Eh         ; light yellow on blue (directory names in ASCII section)
COL_WHITEFG      EQU 1Fh         ; light white on blue (file names in ASCII section)
endif

; "bRW" variable
RW_READ          EQU 0
RW_WRITE         EQU 1

; "bFilesys" variable
FS_UNDEFINED     EQU 0
FS_FAT12         EQU 1  ; bits 0-2 (FAT12-FAT32) must not be changed;
FS_FAT16         EQU 2  ; they are used to calculate a shift factor.
FS_FAT32         EQU 4
FS_EXFAT         EQU 8 or FS_FAT32
FS_FATXX         EQU FS_FAT12 or FS_FAT16 or FS_FAT32 or FS_EXFAT
FS_NTFS          EQU 16

; "bRegion" variable for figuring out what section we're on in the drive
; it's meant for FAT disks only - if bits 4-7 are 0, bits 0-3 may contain
; "viewmode" ( VM_MBR ).
; if "bRegion" does not have any of the lower 4 bits set, then
; it is set with a viewmode.
RG_UNDEFINED     EQU 0
RG_RESERVED      EQU 00010000b
RG_FAT           EQU 00100000b
RG_ROOT          EQU 01000000b
RG_DATA          EQU 10000000b

;--- "bViewmode" defines what the section at the bottom of the screen just above
;--- the menu is used to display (for additional information)
;--- VM_MBR to VM_DIRECTORY are tied to menu keys F2-F7!
VM_DATA          EQU 0  ; not manually set mode
VM_MBR           EQU 1
VM_BOOTSECTOR    EQU 2
VM_FAT12         EQU 3
VM_FAT16         EQU 4
VM_FAT32         EQU 5
VM_DIRECTORY     EQU 6
VM_FSINFO        EQU 7  ; not manually set mode     
if ?GPT
VM_GPTHDR        EQU 8  ; not manually set mode     
VM_GPTENTRY      EQU 9  ; not manually set mode     
endif

; "bEditmode" variable
EM_DEFAULT       EQU 0
EM_ASCII         EQU 1

; "bDisplaymode" variable
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

SFNENTRY struct
name_   db 11 dup (?)
bAttr   db ?     ;+0B
bRes    db ?     ;+0C
bCreMSec db ?    ;+0D ms past creation
wCreTime dw ?    ;+0E creation time (DOS 7)
wCreDate dw ?    ;+10 creation date (DOS 7)
wLADate  dw ?    ;+12 last access date (DOS 7)
wClHigh  dw ?    ;+14 hiword start cluster#
wLUTime  dw ?    ;+16 modified time
wLUDate  dw ?    ;+18 modified date
wClLow   dw ?    ;+1A loword start cluster#
dwSize   dd ?    ;+1C file size in bytes
SFNENTRY ends

; directory entry attribute bits
DA_READONLY      EQU 00000001b
DA_HIDDEN        EQU 00000010b
DA_SYSTEM        EQU 00000100b
DA_VOLUME        EQU 00001000b
DA_DIRECTORY     EQU 00010000b
DA_ARCHIVE       EQU 00100000b

; fat directory data offsets - replaced by SFNENTRY.x
;DIR_ATTRIBUTES   EQU 0Bh
;DIR_CREATEMSEC   EQU 0Dh
;DIR_CREATETIME   EQU 0Eh
;DIR_CREATEDATE   EQU 10h
;DIR_LASTACCDATE  EQU 12h
;DIR_CLUST_HIGH   EQU 14h
;DIR_LASTUPDTIME  EQU 16h
;DIR_LASTUPDDATE  EQU 18h
;DIR_CLUST_LOW    EQU 1Ah
;DIR_FILESIZE     EQU 1Ch

LFNENTRY struct
bIdx     db ?           ;+00
wName0   dw 5 dup (?)   ;+01 name chars 0-4
bAttr    db ?           ;+0B
         db ?           ;+0C
bChkSum  db ?           ;+0D chksum of SFNENTRY.name_
wName5   dw 6 dup (?)   ;+0E name chars 5-10
         dw ?           ;+1A
wNameB   dw 2 dup (?)   ;+1C name chars 11-12
LFNENTRY ends

;DIRLFN_CHKSUM    EQU 0Dh

; ascii
;BACKSPACE_KEY    EQU 8
;TAB_KEY          EQU 9
;CTRLENTER_KEY    EQU 10
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
ESCAPE_SCAN      EQU 01h
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
ALTPGUP_KEY      EQU 99h
ALTPGDN_KEY      EQU 0A1h
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

; "bChainmode" variable
NO_CHAIN         EQU 0
FILE_CHAIN       EQU 1
FAT_CHAIN        EQU 2

; "fromfat" variable
FF_FAT1          equ 0
FF_FAT2          equ 1

;--- macros

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

@mitem macro stridx, cmdofs, idx
ifnb <idx>
idx equ $ - startmenudefs
endif
    db stridx
_TEXT2 segment
    dw cmdofs
_TEXT2 ends
endm

CHSENT struct
bDH   db ?
bCL   db ?
bCH   db ?
CHSENT ends

;--- partition entry in an MBR

PTABENT struct
bBoot db ?
sCHS  CHSENT <?>    ; +1  start CHS
bType db ?
eCHS  CHSENT <?>    ; +5  end CHS
start dd ?          ; +8  start LBA
size_ dd ?          ; +12 size LBA
PTABENT ends

if ?GPT
;--- partition table header in a GPT
;--- located at LBA 1
;--- size of GPT is dwNumPE * dwSizPE - 128*128=16 kB -> 32 sectors (512)

GPTHDR struct
sig        db 8 dup (?);+0 "EFI PART"
dwRev      dd ?     ;+8 00 00 01 00
dwSizeHdr  dd ?     ;+12
dwCRC      dd ?     ;+16
dwRes1     dd ?     ;+20
qwCurLBA   dq ?     ;+24
qwBckLBA   dq ?     ;+32
qwFirstLBA dq ?     ;+40
qwLastLBA  dq ?     ;+48
guid       db 16 dup (?);+56
qwGPTLBA   dq ?     ;+72 start GPT partition entries 
dwNumPE    dd ?     ;+80 # of partition entries ( usually 128)
dwSizePE   dd ?     ;+84 size of partition entry (128)
dwCRCPE    dd ?     ;+88
;res2       db 420 dup (?)
GPTHDR ends

;--- partition table entry in a GPT
;--- usually located at LBA 2-33 ( 128 entries = 16 kB )

GPTENTRY struct
guidType   db 16 dup (?)
guidInst   db 16 dup (?)
qwFirstLBA dq ?
qwLastLBA  dq ?
qwFlags    dq ?
PartName   dw 36 dup (?)    ;UTF-16 name
GPTENTRY ends

;--- partition types:
;--- EFI system partition (ESP): C12A7328-F81F-11D2-BA4B-00A0C93EC93B
;--- BIOS boot partition (Grub): 21686148-6449-6E6F-744E-656564454649
;--- MS reserved partition:      E3C9E316-0B5C-4DB8-817D-F92DF00215AE

;--- qwFlags values
; bit 2: legacy
; bit 60: read-only
; bit 61: shadow copy
; bit 62: hidden
; bit 63: no drive letter
endif

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
ext_boot_sig    db ?    ;+0x1b 28h/29h
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
ext_boot_sig    db ?    ;+0x37  28h/29h
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

SECNO struct
union
b32 dd ?    ; used to access FAT logical drives
struct
l   dd ?
if ?SN64
h   dd ?
endif
ends
ends
SECNO ends

;--- this struct is used for communication with diskaccess()
;--- currently only a static member!

IOREQ struct
sectno     SECNO <>
bDrive     db ? ; drive number (bDrive ... drvtype must be one dword)
bRW        db ? ; distinguish between read/write
rwfunc     db ? ; what read/write function to use
drvtype    db ? ; physical/fat/cdrom/file
pBuffer    dw ?
IOREQ ends

MENULVLSHIFT equ 2 ; since size is 4

MENULVL struct  ; item for menu stack, size must be 4
bMenuStart db ?
bMenuSize  db ?
bSpaces    db ?
           db ?
MENULVL ends

NUMSECSTKITEMS equ 8
if ?SN64
SECSTKSHIFT equ 4
else
SECSTKSHIFT equ 3
endif

SECSTKITEM struct  ; item on "sector stack", size must be 8 (or 16)
dwSector SECNO <>
wSpot    dw ?
bFlags   db ?   ; bit 0: 1=item valid
         db ?
if ?SN64
         dd ?
endif
SECSTKITEM ends

HIGHLIGHT struct
ofs   dw ?    ; offset of var
siz_  db ?    ; "document" size
scsiz db ?    ; screen size
HIGHLIGHT ends

    .const

introtext       db 'WDe V1.1',0
copyright       db 'Copyright(C) 2005 Ben Cadieux, 2024 japheth',0
viderror        db "No EGA/VGA detected",13,10,'$'
cpuerror        db "No 80386+ CPU",13,10,'$'

owmsg           db 'File Exists - A(ppend), O(verwrite) or C(ancel)? ',0
fdmsg           db 'Floppy disk [y/N]? ',0
cdrcmsg         db 'R(aw) or C(ooked) mode? ',0
plmsg           db 'L(ogical) or P(hysical) disk? ',0
abmsg           db 'A(bove) or B(elow)? ',0
truncatemsg     db 'Truncate To Filesize',0
diskfullmsg     db 'Disk Full',0
quitmsg         db 'Quit',0
ynmsg           db ' [Y/n]? ',0

unknownmsg      db 'Unknown',0

partstrgs label byte
part00          db 'Unused',0
part01          db 'Fat12',0
part04060E      db 'Fat16',0
part050F        db 'Ext Fat',0
part07          db 'NTFS, exFAT',0
part0B0C        db 'Fat32',0
part82          db 'Linux Swap',0
part83          db 'Linux',0
partA5          db 'FreeBSD',0
;partA8          db 'OS-X',0
;partA6          db 'OpenBSD',0
;partA9          db 'NetBSD',0
;partEB          db 'BeOS',0
partEE          db 'EFI',0
partEF          db 'ESP',0
parthid         db 'Hid Fat',0 ;16,1B,1C,1E,8D,90,91,92,97,98,9A,9B

;--- define menu strings and identifiers (MS_xxx).
;--- identifiers are used as arguments in menu item definitions (@mitem).

?MIDX = 0
@mstring macro text, name_
ifnb <name_>
MS_&name_ equ ?MIDX
else
MS_&text equ ?MIDX
endif
    db '&text&',0
?MIDX = ?MIDX + 1
endm

MS_INACTIVE equ -1

menustrings label byte
    @mstring Save
    @mstring File
    @mstring Goto
    @mstring View
    @mstring Find
    @mstring Functions
    @mstring <Change Disk>, Change_Disk
    @mstring Sector
    @mstring <Boot Sector>, Boot_Sector
    @mstring Cluster
    @mstring Fat1
    @mstring Fat2
    @mstring Root
    @mstring <Data Area>, Data_Area
    @mstring <Save to File>, Save_to_File
    @mstring <Restore from File>, Restore_from_File
    @mstring Input
    @mstring MBR
    @mstring Partition1
    @mstring Partition2
    @mstring Partition3
    @mstring Partition4
if ?GPT
    @mstring <GPT Header>, GPT_Header
    @mstring GPT
endif
szPartition label byte
    @mstring Partition
    @mstring Chain
    @mstring <Dump CD As ISO>, Dump_CD_As_ISO
    @mstring Auto
    @mstring Directory
    @mstring String
    @mstring Hex
    @mstring Fill
    @mstring Restrict
    @mstring Fat
    @mstring Incremental
    @mstring Decremental
    @mstring Random
    @mstring 8Bit
    @mstring 12Bit
    @mstring 16Bit
    @mstring 32Bit
    @mstring Fat12
    @mstring Fat16
    @mstring Fat32
    @mstring Inverse
    @mstring Next
    @mstring Help
    @mstring $MFT
    @mstring BootSec
if ?EXT
    @mstring UnFormat
    @mstring UnDelete
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
writetofilemsg  db 'Writing File...',0

readingdrive    db 'Reading Drive...',0
recursemsg      db 'Recursing Chain... %s, curr. cluster %lX / %lX',0

searcherror     db 'No (more) Matches Found',0
abortwfmsg      db 'Aborted Writing File',0
abortwdmsg      db 'Aborted Writing to Disk',0

donewritefile   db 'Finished Writing File, %lu sector(s) written',0
donewritedisk   db 'Finished Writing to Disk',0
nodirentryfound db 'No Directory Entry Found With Start Cluster %lX',0
directoryscanmsg db 'Scanning Directory Tree..., curr. cluster %lX',0

filetoosmall    db 'File Too Small',0
filenotfound    db 'File Not Found',0
filetoobigmsg   db 'File Size Cannot Exceed 4GB-1',0

filereaderr     db 'Error Reading File',0
filewriteerr    db 'Error Writing File',0
filecreateerr   db 'Error Creating File',0

szInvalidRange  db 'Invalid Sector Range',0
szInvalidSect   db 'Sector %lu > last sector (%lu)',0

szSectorRErr    db 'Error Reading Sector %lu',0
szSectorRErr2   db ' - Abort/Zero-Fill [A/Z]? ',0
szSectorRErr3   db ' - Abort/Skip/Ignore All [A/S/I]? ',0
szSectorWErr    db 'Error Writing Sector %lu',0
invalstartclust db 'Invalid Start Cluster',0
nochainmsg      db 'Recursive Link Not Found',0
nosearchstring  db 'No search string defined yet',0
szDriveinvalid  db 'Drive invalid',0
invalclustmsg   db 'Cluster %lX invalid',0
endofchainmsg   db 'End of cluster chain reached',0
secsizetoobig   db 'Sector size exceeds 4K',0
if ?POSDIR
szDirNotFound   db 'Directory not found',0
endif
errormsg        db ' - Press Any Key',0

szMBRmsg        db '[MBR]',0
if ?GPT
szGPTHdrmsg     db '[GPT Hdr]',0
szGPTEntrymsg   db '[GPT]',0
endif
szReservedmsg   db '[Boot/Reserved]',0
szFATmsg        db '[Fat-%u]',0
szRootmsg       db '[Root]',0
szDatamsg       db '[Data]',0

;--- prompts
szHex           db 'Hex: ',0
szSector        db 'Sector: ',0
szCluster       db 'Cluster: ',0
szDrive         db 'Drive: ',0
szFilePrmt      db 'File: ',0
szPathPrmt      db 'Path: ',0
szString        db 'String: ',0
szNoOfSectors   db 'Number of Sectors (1-%lu): ',0

szSector2       db 'Sector (0-%lu): ',0
szCluster2      db 'Cluster (2-%lX): ',0
;szCluster3      db 'Start Cluster (2-%lX) of File/Dir to find: ',0

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

VIEWDEF struct
wLbl  dw ?
wProc dw ?
VIEWDEF ends

fifields label word
    VIEWDEF <DStr('Total Free Clusters: '), offset printvalue_hl>
    VIEWDEF <DStr('First Free Cluster:  '), offset printhex_hl>
numfifields equ ($ - offset fifields) / sizeof VIEWDEF

SPOS struct
col db ?
row db ?
SPOS ends

_BSS segment

vidaddr         dd ? ; start video buffer
stackbot        dw ? ; stack bottom
vidcolsize      dw ?
vidrows         db ?
vidpg           db ?
scrn_xy         SPOS <>; xy position on screen
spot            dw ? ; keeps count of what byte we're editing 0-511
oldcsrattr      dw ?
wSectOfs        dw ? ; because [spot] goes from 0-511, if we have sectors
                     ; that are >512 bytes, wSectOfs keeps track of what
                     ; 512-byte piece we're working with
;maxleft         db ?
bHL             db ? ; keeps track of whether we're editing high or low nibble
bFilesys        db ? ; file system (FAT-xx, exFAT, NTFS)

    align dword
fromfat         db ? ; FAT: fat to use for getfatentry/putfatentry
bFats           db ? ; FAT: number of fats
wSpC            dw ? ; FAT: sectors per cluster ( word for exFAT )
dwSpF           dd ? ; FAT: sectors per fat
dwFat1end       dd ? ; FAT: end of first fat
dwReserved      dd ? ; FAT: reserved sectors (start of fat)
wRootentries    dw ? ; FAT: number of root entries (unused)
wRootsectors    dw ? ; FAT: number of root sectors
dwFatSector     dd ? ; FAT: current sector in fat cache buffer
dwFat12start    dd ? ; FAT: stores the sector number when fat12
                     ;      view mode was selected
dwFat12fixsec   dd ? ; FAT: sector # for fat12 fix
dwDataStart     dd ? ; FAT: start sector of data region
dwLastCluster   dd ? ; FAT: total # of clusters on the drive
dwRootSect      dd ? ; FAT: start sector of root directory
dwRootCluster   dd ? ; FAT: root start cluster (FAT32)
dwCluster       dd ? ; FAT: used to store cluster# in "restore chain" 
dwBpC           dd ? ; FAT: bytes per cluster
dwCurrCluster   dd ? ; FAT: curr cluster while saving/restoring File/FAT chain
dwNumCluster    dd ? ; FAT: clusters to be saved in exFAT savechain/restorechain variant
if ?SETFILEDATETIME
dwFileDateTime  dd ?
endif
dwValue         dd ? ; variable for getting no of sectors
dwMaxvalue      dd ? ; stores max. value if reading numbers
dwFilesize      dd ? ; size of current image file, or current file chain to save
dwPartitions    dd ?,?,?,? ; MBR partitions start sectors
dwRwfilesize    dd ? ; filesize of image file for DT_FILE
qwDiskStart     dq ? ; sector offset to current disk start
currSector      SECNO <>; current sector in sectbuffer (logical/physical)
lastSector      SECNO <>; end of data (last sector) (logical/physical)
if ?GPT
startGPT        SECNO <>
bckGPTHdr       SECNO <>
dwGPTSize       dd ?
endif
highlight       HIGHLIGHT <>; area to highlight with viewmode

seed12          label dword
seed1           dw ?
seed2           dw ?
seed34          label dword
seed3           dw ?
seed4           dw ?

backupbs        dw ? ; FAT: backup boot sector location (FAT32)
fsinfo          dw ? ; FAT: fsinfo sector (FAT32)
wSpCcnt         dw ? ; FAT: helper var for "restore chain" (sectors per cluster counter)
wBps            dw ? ; current bytes per sector ( both physical/logical )
if ?NOPTION
wOptBps         dw ? ; bytes per sector set by cmdline option -n ( for image files only )
endif
rwhandle        dw ? ; file handle if device is DT_FILE
wFilehandle     dw ? ; file handle for file ops
wCylinders      dw ? ; disk geometry for int 13h, ah=02/03

hdnumber        db ? ; hard drive number partition belongs to
bSpCshift       db ? ; FAT: sectors per cluster for doing bitshifts
bRegion         db ? ; what part of the disk we're in
bViewmode       db ? ; see VM_xxx
bDisplaymode    db ? ; hex or binary
bEditmode       db ? ; what mode being edited in (ascii/default)
bStaticview     db ? ; 1=force viewmode, 0=autodetect viewmode

fillflag        db ?,?          ; see FL_ equates
srflag          db ?            ; "file ops" save/restore menu flag
bDriveflags     db ?            ; directs setdrive to ask for Filename(1) or Drive(0)
commandflag     db ?            ; used by unformat
bChainmode      db ?            ; type of chain to save/restore (FAT/FILE)

bHeads          db ?            ; heads returned by int 13h (08/48)
bSectors        db ?            ; sectors/track returned by int 13h (08/48)
handling        db ?            ; inside diskaccess(): how to handle errors
menustackidx    db ?            ; index for menustack
secstk_top      db ?            ; index for secstk
bHexString      db ?            ; 0/1=stringbuffer filled with string/hex value
if ?SAFEMODE
bSafe           db ?            ; "safe" mode cmdline option set?
endif
if ?MOUNT
bMount          db ?            ; mount partition + 1
endif
bTabSw          db ?            ; for switch disk <-> filename
bSkipFat        db ?            ; exFAT: set if file has no associated fat chain
;unlockdrv       db ?            ; unlock this drive if != 0
bSecSh          db ?            ; shift factor for current wBps
bIdx            db ?            ; curr index if lfns are displayed in dirview
bDark           db ?            ; 1=screen foreground color not bright
bShift          db ?            ; kbd shift status
bUpdateMenu     db ?            ; 1=menu update required
bUpdateScreen   db ?            ; 1=screen must be updated
bUpdateView     db ?            ; 1=view region must be updated
bIsDirectory    db ?            ; for "save file chain", 1 if file is a dir
if ?GPT
bTypeEE         db ?            ; EFI partition in MBR?
endif
    align dword
if ?DEBUG
starttime       dd ?            ; to measure time for lengthy operations
endif

oldint24        dd ?
                dw ?            ; add a word to oldint24 in case it runs in dpmi32
pFatCache       dw ?            ; local heap ptr to cached FAT sector
lasttick        dw ?            ; timer ticks since last call
rembytes        dw ?            ; remaining bytes when dealing with
                                ; non-standard sized sectors

    align dword
menustack       MENULVL 4 dup (<?>)  ; menu stack
secstk          SECSTKITEM NUMSECSTKITEMS dup (<>)  ; sector stack
if ?LFN
filenamebuffer  db 256 dup (?)
else
filenamebuffer  db 72 dup (?)   ; size must be at least 69, 72 used for alignment
endif
stringbuffer    db 74 dup (?)   ; buffered string for find/fill
stringlen       dw ?
sprintfbuffer   db 80 dup (?)   ; buffer for sprintf
ioreq           IOREQ <<>>
diskinfobuffer  DINFO1 <?>      ; buffer for int13h "get drive info"
cdheader        CDREQ <?>       ; cd device request header
drivepacket     DISKIO <?>      ; used by int 25h/26h and int 21h/ax=7305h
dapacket        DAP <?>         ; used by int 13h ah=42h/43h (extended read/write)
valuebuffer     db 11 dup (?)
                db ?            ; ensure there is at least 1 byte between valuebuffer and sectbuffer

BUFFSHIFT equ 12                ; sectbuffer must be a factor of 2

    align 4
sectbuffer      db (1 shl BUFFSHIFT) dup (?) ; read buffer for sector reading

_BSS ends

    .code

getstring proto stdcall :ptr, :word, :word, :word, :ptr

if ?PM
    include initpm.inc
    include wdepm.inc
endif

if ?VDD
    include wdent.inc   ; to access WDEVDD on NT platforms.
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
@dbgout macro text:vararg
endm
endif

    include sprintf.inc
if ?DEBUG
    include timer.inc
endif
    include debug.inc
    include setargv.inc

;--- main menu definition

    @mstart initialmenu
    @mitem MS_Help, helpscreen
    @mitem MS_File, submenu_file
    @mitem MS_Goto, submenu_jumpto
    @mitem MS_View, submenu_view
    @mitem MS_Find, submenu_find
    @mitem MS_Functions, submenu_functions
    @mitem MS_Save, savetodisk
    @mend initialmenu

Start proc

    mov dx, @data
    mov ds, dx
    pushf
    pushf
    pop ax
    or ah,70h       ; a 80386 will have bit 15 cleared
    push ax         ; if bits 12-14 are 0, it is a 80286
    popf            ; or a bad emulation
    pushf
    pop ax
    popf
    and ah,0f0h
    js @F           ; bit 15 set? then its a 8086/80186
    jnz is386
@@:
    mov dx, offset cpuerror
    mov ah, 9
    int 21h
    mov ax,4C01h
    int 21h

;--- setup small memory model

is386:
    cld
    mov [_psp], es
    mov ax, ss
    sub ax, dx
    shl ax, 4
    mov ss, dx
    add sp, ax    ; SS=DS=dgroup

    mov cx, es
    mov bx, ds
    sub bx, cx
    add bx, 1000h ; free memory beyond 64kB dgroup
    mov ah, 4ah
    int 21h
    jc quit

    push ds
    pop es        ; now ds=es=ss=dgroup

    mov di, offset startbss
    mov cx, sp
    sub cx, di
    shr cx, 1
    xor ax, ax
    rep stosw     ; clear _BSS (=.data?) and STACK segments

if ?VDD
    call initvdd         ; init vdd on nt platforms
endif

    mov [stackbot], sp
    mov [_mem], sp       ; set start of heap

if ?PM
    call initpm
    call initwdepm
endif

    mov es,[_psp]
    call _setargv        ; scan command line, setup _argc and _argv

    call main            ; won't return

Start endp

;--- check cmdline params and do video and other initialization.
;--- please note that _argc and _argv are no global variables,
;--- they're stack variables defined inside _setargv() and no
;--- longer valid once BP is changed/ SP is reset.

init_wde proc

    mov bx, [_argv]
    mov cx, [_argc]

_argv equ <>             ; "undefine" _argc & _argv
_argc equ <>

    add bx, 2            ; skip "filename" argument ( doesn't exist )
    dec cx

nextarg:
    jcxz no_drive
    mov si, [bx]
    add bx, 2
    lodsw
    cmp al, '/'
    jz handleoptions
    cmp al, '-'
    jz handleoptions
    dec cx
    jnz printhelp
    cmp al, '0'
    jb isfn
    cmp al, '9'
    jbe maybedrive
    mov bh, DT_LOGICAL
    or al, 20h
    cmp al, 'a'
    jb isfn
    cmp al, 'z'
    ja isfn
    sub al, 'a'
    cmp ah, ':'
    jnz isfn
    cmp byte ptr [si], 0
    jz has_drive
isfn:
    mov di, offset filenamebuffer
    sub si, 2
@@:
    lodsb
    stosb
    and al, al
    jnz @B
    mov bh, DT_FILE
    jmp has_drive
handleoptions:
    push cx
    call options
    pop cx
    dec cx
    jmp nextarg
maybedrive:
    mov bh, DT_PHYSICAL
    sub al, '0'
    or al, 80h
    cmp ah, 0
    jz has_drive
    or ah, 20h
    and al, 7fh
    cmp ah, 'f'
    jz has_drive
    jmp isfn
no_drive:
    mov al, -1
has_drive:
    pusha

    call setseeds1
    call vinit                  ; init video mode, init screen

if ?PM
    mov bl, 24h                 ; use DPMI to modify int vector, since
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
    jnz nomount
    movzx eax, [bMount]
    cmp al, 0
    jz nomount
    cmp al, -1                  ; mount physical as logical?
    jnz @F
    xor eax, eax
    jmp mlog
@@:
;--- setvariables moved partition startsectors in [dwPartitions]
    dec ax
    mov eax, [dwPartitions+eax*4]
    and eax, eax
    jz nomount
mlog:
    @dprintfln "mount as logical: start sector %lu", eax
    mov [ioreq.sectno], eax
    call readsect
    call mountdrive
nomount:
endif

if ?POSDIR
    test [bDriveflags], DF_DIR     ; a directory path given as cmdline argument?
    jz @F
    test [bFilesys], FS_FAT12 or FS_FAT16 or FS_FAT32
    jz @F
    call PosDir
@@:    
endif

    mov dx, initialmenu + linitialmenu shl 8
    mov cl, 3
    call initmenustack

    call printoffset            ; print current offset (=spot)
    ret

init_wde endp

if ?POSDIR

;--- search for directory DI in current sector

scanfordir proc
    @dprintfln "scanfordir: sector=%lu", [ioreq.sectno]
    mov si, offset sectbuffer
    mov cl, 512 / DIRENTSIZE
nextentry:
    cmp [si].SFNENTRY.name_, 0
    jz skipdir
    cmp [si].SFNENTRY.name_, 0E5h
    jz skipentry
    test [si].SFNENTRY.bAttr, DA_DIRECTORY
    jz skipentry
if 0
    cmp dword ptr [si].SFNENTRY.name_, "   ."
    jz skipentry
    cmp dword ptr [si].SFNENTRY.name_, "  .."
    jz skipentry
endif
    pusha
    mov cx, sizeof SFNENTRY.name_
    repz cmpsb
    popa
    jz found
skipentry:
    add si, sizeof SFNENTRY
    dec cl
    jnz nextentry
    xor ax, ax
    ret
skipdir:
    or ax, -1
    clc
    ret
found:
    @dprintfln "scanfordir: found directory at %lX", [ioreq.sectno]
    push [si].SFNENTRY.wClHigh
    push [si].SFNENTRY.wClLow
    pop eax
    push bx
    call setcluster
    pop bx
    stc
    ret
scanfordir endp

;--- if a directory path was given as cmdline argument and filesys is FAT,
;--- jump to directory in filenamebuffer

PosDir proc
    call jumptoroot
    mov bx, offset filenamebuffer
    sub sp, 256              ; alloca(256) for temp path
    push ds
    pop es
    mov di, sp               ; copy path given in cmdline to temp buffer on stack

    cmp byte ptr [bx+1],':'
    jnz @F
    add bx, 2
@@:
    cmp byte ptr [bx],'\'    ; absolute path given?
    jz abs_path
    mov si, bx
@@:
    lodsb
    stosb
    and al,al
    jnz @B

    mov si, offset filenamebuffer  ; get current directory in filenamebuffer

;--- LFN function 7160h will need a drive letter!

    mov al, [ioreq.bDrive]
    mov dl, al
    add al, 'A'
    mov ah, ':'
    mov [si], ax
    add si, 2
    mov byte ptr [si],'\'
    inc si
    inc dl
    call getcurrdir
    jc nocurrdir
    mov di, si
    mov al,0
    cmp [si],al                    ; current directory is root?
    jz @F
    mov cx,-1
    repnz scasb
    mov byte ptr [di-1],'\'        ; concat rel. path saved onto stack to current dir
@@:
    mov si, sp
@@:
    lodsb
    stosb
    and al,al
    jnz @B
nocurrdir:
abs_path:
    mov di, sp          ; translate LFN path to SFN path
;    mov si, bx
    mov si, offset filenamebuffer
@@:
    lodsb
    stosb
    and al,al
    jnz @B
    mov si, sp
;    mov di, bx
    mov di, offset filenamebuffer
    mov bx, di
    call getshortname   ; int 21h, ax=7160h will add drive letter & colon
    cmp byte ptr [bx+1],':'
    jnz @F
    add bx,2
@@:
    add sp, 256

dirfound:               ;<----
    cmp byte ptr [bx],'\'
    jnz @F
    inc bx
@@:
    cmp byte ptr [bx],0
    jz found
    cmp word ptr [bx],"."
    jz found
    cmp word ptr [bx],"\."
    jz found
;--- copy dir to 8.3 struct
_BSS segment dword public 'BSS'
dirsearch db sizeof SFNENTRY.name_ dup (?)
_BSS ends
    push ds
    pop es
    mov di, offset dirsearch
    push di
    mov cx, sizeof SFNENTRY.name_
    mov al,' '
    push cx
    rep stosb
    pop cx
    pop di
    push di
nextchar:
    mov al, [bx]
    cmp al, 0
    jz copydone
    cmp al, '\'
    jz copydone
ife ?LFN
    cmp al, 'a'
    jb @F
    sub al, 'a'-'A'
@@:
endif
    stosb
    inc bx
    loop nextchar
copydone:
    pop di

scannextdircluster:
    call IsRoot1216
    jc scannextsector
    mov cx, [wSpC]
scannextsector:
;--- read directory sector
    call readsect
    jc notfound
    push cx
    call scanfordir
    pop cx
    jc dirfound
    cmp ax,-1
    jz notfound
    inc [ioreq.sectno]
    loop scannextsector

;--- to be fixed: don't call sector2cluster if in root dir of FAT12/16
if 1
    call IsRoot1216
    jc notfound
endif
    
    mov eax, [ioreq.sectno]
    movzx ecx, [wSpC]
    sub eax, ecx
    call sector2cluster      ; may fail ( carry set ) - root dir of FAT12/16
    call getfatentry         ; get next cluster# in eax
    @dprintfln "PosDir: called getfatentry, eax=%lX", eax
    jc @F
    cmp eax, 2
    jb @F
    cmp eax, 0ffffff8h
    jnb @F
    call cluster2sector
    mov [ioreq.sectno], eax
    jmp scannextdircluster
@@:
notfound:
    mov dx, offset szDirNotFound
    call nuprinterror
found:
    ret

IsRoot1216:
    test [bFilesys], FS_FAT12 or FS_FAT16
    jz @F
    mov eax, [ioreq.sectno]
    call sector2cluster         ; returns C if in root dir
    mov cx, [wRootsectors]
@@:
    retn
PosDir endp

endif

;--- main program

main proc

    call init_wde
    mov sp, [stackbot]          ; reset SP after init_wde ( makes argc, argv invalid )
    mov bUpdateScreen, 1

main_loop:
    cmp bUpdateScreen, 0
    jz @F
    mov [handling], ABORT_OPERATION
    call updatescreen           ; print line 0 and sector area
@@:
    cmp bUpdateView, 0
    jz @F
    call updateview
@@:
    cmp bUpdateMenu, 0          ; menu to be printed?
    jz @F
    call printmenu
@@:
    push 1
    call showcursor
    call getkey
    push 0
    call showcursor

    push main_loop

    call checkmenukey           ; check for menu (=function) keys
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
    cmp [bEditmode], EM_ASCII
    je modascii
    cmp [bDisplaymode], DM_BINARY
    je modbinary
modhex:
    sub al, '0'                 ; check for valid hex digit
    cmp al, 9
    jbe digitok                 ; '0' - '9'?
    sub al, 'A' - '0'           ; 'A' - 'F' -> 0 - 5
    cmp al, 5
    jbe @F
    sub al, 20h                 ; check again for lower-case
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
    call spot2xy
    mov [scrn_xy], dx
    cmp [bDisplaymode], DM_HEX  ; hex or binary?
    je @F
    call rendernumbin
    jmp done_render
@@:
    mov dl, 2
    call rendernumhex
done_render:
    call printstring            ; display rendered number
    mov dx, bx
    call spot2xyasc
    mov [scrn_xy], dx
    mov cl, 1
    call fillchar               ; display ascii value
    jmp moveright
skipkey:
    ret

main endp

;--- handle cmdline options
;--- in: AH=option
;---     DS:SI
;--- BX must be preserved.

options proc
    mov al, ah
    and al, al
    jz error
    or al, 20h
if ?SAFEMODE
    cmp al, 's'
    jnz @F
    mov [bSafe], 1              ; deactivate all write access
    ret
@@:
endif
if ?MOUNT
    cmp al, 'm'
    jnz @F
    lodsb 
    and al, al
    jz undef
    sub al, '1'
    jc error
    cmp al, 4
    cmc
    jc error
    inc ax
    mov [bMount], al
    ret
undef:
    mov [bMount], -1
    ret
@@:
endif
if ?NOPTION
    cmp al, 'n'
    jnz @F
	call getdecnumber
	jc error
	mov [wOptBps], ax
	call setBps	; check if value is ok
	jc error
	ret
@@:
endif
error:
    jmp printhelp
options endp

if ?NOPTION

;--- atoi()
;--- in: DS:SI=string to convert
;--- out: NC, AX=number

getdecnumber proc
	xor dx,dx
nextchar:
	lodsb
	cmp al,0
	jz done
	cmp al,'0'
	jb error
	cmp al,'9'
	ja error
	sub al,'0'
	cbw
	xchg ax, dx
	shl ax, 1
	mov cx, ax
	shl ax, 2
	add ax, cx
	add ax, dx
	xchg ax, dx
	jnc nextchar
error:
	stc
	ret
done:
	xchg ax, dx
	ret
getdecnumber endp

endif

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
    CKey CTRLLEFT_KEY,     searchpredecessor
    CKey CTRLRIGHT_KEY,    jumpsuccessor
    CKey CTRLUP_KEY,       jumpstkpop
    CKey CTRLHOME_KEY,     jumptobootsector
    CKey CTRLEND_KEY,      jumptolastsect
    CKey TAB_SCAN,         changemode
if ?ALTKEYS
    CKey ALTPGUP_KEY,      prevcluster
    CKey ALTPGDN_KEY,      nextcluster
endif
lck1 equ ($ - ck) shr 1
    CKey CSRLEFT_KEY,      moveleft
    CKey CSRRIGHT_KEY,     moveright
    CKey CSRUP_KEY,        moveup
    CKey CSRDOWN_KEY,      movedown
    CKey HOME_KEY,         movefirst
    CKey END_KEY,          movelast
    CKey ESCAPE_SCAN,      handle_esc
lck equ ($ - ck) shr 1
    CKey ENTER_KEY,        handle_enter
    CKey 0Ah,              handle_ctlenter

;--- check ctrl keys
;--- AL=ascii code, AH=scan code

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
    scasb          ; enter key? ( is ascii value )
    jz @F          ; then jump to cluster ( in FAT or directory )
    inc di
    cmp ax, CTRLENTER_KEY ; check both ascii & scan code for this key (so ctrl-j won't work)
    je @F          ; jump to FAT/directory entry for current cluster/entry
    ret
@@:
    pop cx         ; skip return address
    dec di
    sub di, offset ckc
    cmp di, lck1
    jnb @F
    mov [bUpdateScreen], 1
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
    shl bx, MENULVLSHIFT
    add bx, offset menustack
    cmp cl, [bx].MENULVL.bMenuSize
    jb found
@@:
    ret
found:
    add cl, [bx].MENULVL.bMenuStart
    movzx bx, cl
    cmp [bx][startmenudefs], MS_INACTIVE
    jz @B
    shl bx, 1
    pop cx                      ; skip return address
    jmp cs:[bx][startmenucmds]  ; function tables are in the code segment

checkmenukey endp

;--- push a new level onto the menu stack
;--- there's room for 4 levels ( all are used )
;--- example: 0=initialcmds, 1=funccmds, 2=fillcmds, 3=incdeccmds
;--- in: DL=start, DH=size menu, CL=spaces between items

pushmenustack proc
    inc [menustackidx]
initmenustack::
    movzx bx, [menustackidx]
    shl bx, MENULVLSHIFT
    add bx, offset menustack
    mov [bx].MENULVL.bMenuStart, dl
    mov [bx].MENULVL.bMenuSize, dh
    mov [bx].MENULVL.bSpaces, cl
    mov [bUpdateMenu], 1
    ret

pushmenustack endp

resetmenustack proc
    mov [menustackidx], 0
    mov [bUpdateMenu], 1
    ret
resetmenustack endp

;--- set menuitem CL to AL
;--- if item changes AND is currently shown, set bUpdateMenu=1

setmenuitem proc
    push bx
    movzx bx, cl
    cmp al, [bx+startmenudefs]   ; will item change?
    jz done
    mov [bx+startmenudefs], al
    movzx bx, [menustackidx]
    shl bx, MENULVLSHIFT
    add bx, offset menustack
    mov ah, [bx].MENULVL.bMenuStart
    cmp cl, ah                   ; item below current menu start?
    jb done
    add ah, [bx].MENULVL.bMenuSize
    cmp cl, ah                   ; item below current menu end?
    adc [bUpdateMenu], 0
done:
    pop bx
    ret
setmenuitem endp

;--- handle ESC

handle_esc proc
    mov [bUpdateMenu], 1
    cmp [menustackidx], 0       ; in main menu?
    jz @F
    dec [menustackidx]          ; else pop one menu level
    ret
@@:
    call quit
    ret
handle_esc endp

;--- cursor move keys
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
    cmp [bEditmode], EM_ASCII
    je domove
    cmp [bDisplaymode], DM_BINARY
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
    cmp [bEditmode], EM_ASCII
    je domove
    cmp [bDisplaymode], DM_HEX
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

    cmp [bDisplaymode], DM_BINARY
    jne dontchangescreens
    mov bx, [spot]              ; figures out if we've crossed a 128-byte
    shl ax, 1                   ; barrier by checking if the high bits have
    shl bx, 1                   ; changed.  if so, then we need to redraw,
    cmp bh, ah                  ; otherwise there's no need to waste CPU.
    je dontchangescreens
    call printsector
    call printoffset
dontchangescreens:
;    call printoffset           ; is called by movecursor
done:
    mov bUpdateView, 1
    ret
domove endp

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
;--- called after setdrive() if no disk/path was given in cmdline
;--- AL = drive number
;--- BH = DT_PHYSICAL/DT_LOGICAL(=FAT)/DT_CDROM/DT_FILE

trydevice proc
    mov dx, offset readingdrive
    call printbottom

;    push [currSector]           ; if drive switching is unsuccessful,
    push dword ptr [ioreq.bDrive] ; some fields will have to be restored.
    push [wBps]                   ; might be used inside diskaccess()
if ?SN64
    push dword ptr [qwDiskStart+4]
endif
    push dword ptr [qwDiskStart+0]

    mov [ioreq.sectno], 0         ; attempt to read sector 0
    mov [ioreq.pBuffer], offset sectbuffer
    mov [ioreq.drvtype], bh
    mov dword ptr [qwDiskStart+0], 0
if ?SN64
    mov dword ptr [qwDiskStart+4], 0
endif
    push ax
    mov ax, 512
    call setBps
    pop ax
    cmp bh, DT_FILE
    jz  isfilename
    mov [ioreq.bDrive], al
    cmp bh, DT_LOGICAL
    jz trylogical
    call setphysvars              ; if ok, [ioreq.rwfuncs], [wBps] and [lastSector] are adjusted
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
    mov [wSectOfs],0
    call resetfatcache                ; clear fat sector cache
if ?SN64
    add sp, 4+4+2+4                   ; skip saved data on stack
else
    add sp, 4+2+4                     ; skip saved data on stack
endif
    ret
driveinvalid:
    mov dx, offset szDriveinvalid
    call nuprinterror
driveerror:                           ; if reading the new drive failed
    pop dword ptr [qwDiskStart+0]
if ?SN64
    pop dword ptr [qwDiskStart+4]
endif
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

isfilename:
if ?POSDIR
    call getfileattr
    test cl, DA_DIRECTORY       ; directory?
    jz @F
    call checkpath
    jmp trylogical
@@:
endif
    call findfileX
    jnc @F
    mov dx, offset filenotfound
    call nuprinterror           ; print error without screen update
    jmp driveerror
@@:
if ?NOPTION
	mov ax, [wOptBps]
	and ax, ax
	jz @F
	call setBps
@@:
endif
    mov eax, [dwFilesize]       ; file must be 1+ sectors in size
    movzx ecx, [wBps]
    cmp eax, ecx
    jnc @F
    mov dx, offset filetoosmall ; "File too small"
    call nuprinterror
    jmp driveerror
@@:
    mov [dwRwfilesize], eax
    mov bl, 2                   ; access mode (0=ro,1=wo,2=rw)
    call openfile
    mov [rwhandle], ax
    @dprintfln "trydevice: image file, size=%lu, handle=%u", [dwRwfilesize], ax
    mov [ioreq.rwfunc], RWF_FILE
    mov [dapacket.sectors], 1   ; used by file access!
    jmp tryread
trydevice endp

;--- v1.1: if a directory has been entered

DF_FN  equ 1

if ?POSDIR

DF_DIR equ 2

checkpath proc
    mov ah,19h
    int 21h
    cmp filenamebuffer+1,':'
    jnz @F
    mov al, [filenamebuffer]
    or al,20h
    sub al,'a'
@@:
    mov [ioreq.bDrive], al
    mov [ioreq.drvtype], DT_LOGICAL
    or [bDriveflags], DF_DIR
    ret
checkpath endp

endif

;--- enter a disk/drive/image filename
;--- exit: C if ESC pressed or a blank filename was entered
;---       NC, then drive in AL, drvtype in BH

setdrive proc
    test [bDriveflags], DF_FN   ; drive or filename to enter?
    jne fnreq
    mov dx, offset szDrive      ; prompt
    call printbottom            ; print on the bottom of the screen
    call darkclr
kbd_loop:
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
    sub al, 20h                 ; 20h is 'a'-'A', so 'a' = 0, 'b' = 2, etc
    cmp al, 26                  ; same concept as above
    jbe done
    jmp kbd_loop

hdphysical:
;--- this is for setting up the editing for a physical
;--- rather than logical drive. check if floppies are available.
    mov cl, al                  ; back up drive number
    mov es,[_0000H]
    test byte ptr es:[410h], 1  ; floppies available?
    jz nofds                    ; if no, skip asking

    mov dx, offset fdmsg        ; choose between floppy and HD
    call printbottom
@@:
    call cursorgetkey
    cmp al, ESCAPE_KEY
    je setdrive
    cmp al, ENTER_KEY
    je nofds
    or al,20h
    cmp al, 'y'
    je readasfd
    cmp al, 'n'
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
    xor [bDriveflags], DF_FN
    jmp setdrive
fnreq:
    mov [bTabSw], 0
    mov ax, tabsw
if ?POSDIR
    call getpath
else
    call getfilename
endif
    cmp [bTabSw], 1             ; exit with TAB?
    je handle_tabkey
    jcxz abort                  ; no chars entered, or ESC pressed
    mov bh, DT_FILE
done:
    clc
    ret
tabsw:
    mov [bTabSw], 1
    stc                         ; exit getstring when TAB is pressed
    ret
setdrive endp

;--- menuitem "Change Disk"

select_disk proc
@@:
    call setdrive
    jc done
    call trydevice
    jc @B
    call clearsecstack          ; changing drive invalidates sector stack
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
    db "PageUp        - Back 1 sector or 512 bytes",0
    db "PageDown      - Forward 1 sector or 512 bytes",0
    db "Ctrl+PageUp   - Back 100 sectors",0
    db "Ctrl+PageDown - Forward 100 sectors",0
    db "Tab           - Switch to/from ascii editing",0
    db "Shift+Tab     - Switch between hex and binary",0
    db "Ctrl+End      - Jump to last sector on drive",0
    db "Ctrl+Home     - Jump to first sector on drive",0
    db "Ctrl+Up       - Pop sector# from stack and jump to it",0
    db 0
    db "Keys in FAT region of (ex)FAT partitions:",0
    db 0
    db "Ctrl+Right    - Jump to next entry in chain",0
    db "Ctrl+Left     - Search previous entry in chain",0
    db "Enter         - Jump to current entry's data (=cluster)",0
    db "Ctrl+Enter    - Search directory entry with matching start cluster",0
    db 0
    db "Keys in Data region of (ex)FAT partitions:",0
    db 0    
    db "Ctrl+Right    - Jump to next cluster in chain",0
    db "Ctrl+Left     - Search previous cluster in chain",0
    db "Ctrl+Enter    - Jump to FAT entry for this cluster",0
if ?ALTKEYS
    db "Alt+PageUp    - Back 1 cluster",0
    db "Alt+PageDown  - Forward 1 cluster",0
endif
    db "Enter         - If in directory, jump to start cluster of entry",0
    db 0
    db "Keys in MBR/GPT of physical disks:",0
    db 0
    db "Enter         - Jump to start LBA of current PT entry",0
    db 0    
    db "On exFAT disks, a file may have no associated FAT chain; in such",0
    db "cases the file is stored contiguous and Ctrl+Left/Right won't work.",0
    db -1

    .code

helpscreen proc

    call clearscreen
    mov [scrn_xy], 0205h
    mov dx, offset quickhelptext
nextline:
    call printstring
    mov si, dx
nextchar:
    lodsb
    cmp al, 0
    jnz nextchar
    cmp byte ptr [si], -1
    jz done
    inc [scrn_xy.row]
    mov [scrn_xy.col], 5
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
    call clearviewarea
    call printoffset
    mov bUpdateScreen, 1
    ret
helpscreen endp

;--- main menu, item "save": rewrite current sector 

savetodisk proc
    mov dx, offset writetodiskmsg
    call printbottom
if ?SN64
    @dprintfln "savetodisk: currSector=%llu, ioreq.sectno=%llu", [currSector], [ioreq.sectno]
else
    @dprintfln "savetodisk: currSector=%lu, ioreq.sectno=%lu", [currSector], [ioreq.sectno]
endif
    call writecursect
    jc @F
    call resetfatcache                    ; make sure the fat cache is updated next time it's used
    mov dx, offset donewritedisk
    call nuprinterror
@@:
    ret
savetodisk endp

;--- submenu functions, menu item "restrict"

restrictsectors proc
    mov dx, offset abmsg                  ; "above/below"?
    call printbottom
    call darkclr
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
    mov eax, [currSector]              ; set the current sector as the
    mov [lastSector], eax                ; last sector of the drive
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
mountdrive::                            ; <--- mount [currSector] as boot sector of new logical drive
    mov dl, DT_LOGICAL
donesetpl:
    mov [ioreq.drvtype], dl

    call clearsecstack                  ; the sector stack becomes invalid if [qwDiskStart] changes

ife ?SN64
    mov eax, [currSector]               ; set the current sector as the
    add dword ptr [qwDiskStart+0], eax  ; first sector; this is added to
    sub [lastSector], eax               ; [currSector] for r/w, so adjust the
    xor eax, eax                        ; final sector accordingly
    mov [currSector], eax
else
    mov eax, [currSector.l]
    mov edx, [currSector.h]
    add dword ptr [qwDiskStart+0], eax
    adc dword ptr [qwDiskStart+4], edx
    sub [lastSector.l], eax
    sbb [lastSector.h], edx
    xor eax, eax
    mov [currSector.l], eax
    mov [currSector.h], eax
endif
    call setvariables
done:
    ret
restrictsectors endp

;--- submenu "functions"

submenu_functions proc

    @mstart funcmenu
    @mitem MS_Restrict, restrictsectors
    @mitem MS_Fill, submenu_fill
if ?EXT
    @mitem MS_INACTIVE, unformat, FUNCM_UNFORMAT
    @mitem MS_INACTIVE, undelete, FUNCM_UNDELETE
endif
    @mend funcmenu

    mov dx, funcmenu + 2 shl 8    ; only 2 menu items for non-fat file systems
    mov cl, 3
    test [bFilesys], FS_FATXX
    jz pushmenustack
if ?EXT
    mov al, MS_INACTIVE
    cmp [bFilesys], FS_EXFAT      ; no "unformat" for exFAT!
    jz @F
    mov al, MS_UnFormat
@@:
    mov cl, FUNCM_UNFORMAT
    call setmenuitem              ; set/remove "unformat"
endif
    mov cl, 3
    mov dh, lfuncmenu
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
    @mitem MS_Hex,         fillhex
    @mitem MS_String,      fillstring
    @mitem MS_Incremental, fillincr
    @mitem MS_Decremental, filldecr
    @mitem MS_Inverse,     fillinverse
    @mitem MS_Random,      fillrandom
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
    @mitem MS_8Bit,  fillbit8
    @mitem MS_12Bit, fillbit12
    @mitem MS_16Bit, fillbit16
    @mitem MS_32Bit, fillbit32
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

    push [currSector]
    pop [ioreq.sectno]

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
    call resetfatcache                    ; make sure the fat cache is updated next time it's used
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

    push [currSector]
    pop [ioreq.sectno]

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
    call diskaccess_write
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
    add [ioreq.sectno], edi
    push ds
    pop es
    mov di, offset sectbuffer
    or di,di                      ; clear zero flag!
done:
    clc
    ret
abort:
    mov dx, offset abortwdmsg     ; "abort writing to disk"
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
if ?SN64
    invoke sprintf, dx, CStr("%s (sector %llu, remaining %lu)"), cx, [ioreq.sectno], eax
else
    invoke sprintf, dx, CStr("%s (sector %lu, remaining %lu)"), cx, [ioreq.sectno], eax
endif
    call printbottom
    call darkclr3
    pop dx
    ret

;--- main menu tab & shift-tab keys

changemode proc
  cmp al, 0                     ; shift+tab?
  je @F
  xor [bEditmode], EM_ASCII     ; switch between ascii/regular editing
  ret
@@:
  xor [bDisplaymode], DM_BINARY ; switch between hex/binary editing
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
;--- in FAT: scan directory, search matching start cluster
;--- in Data: jump to FAT entry for current cluster

handle_ctlenter proc

    test [bFilesys], FS_FATXX   ; must be a FAT drive
    je done
    mov eax, [currSector]
    test eax, eax
    jz log2phys

    test [bRegion], RG_FAT
    jnz ctlenter_fat
    test [bRegion], RG_DATA
    jz done

;retcluster:
    call pushsecstack           ; push sector# in eax onto sector stack
    call sector2cluster         ; convert sector# to cluster#
    call go2entry               ; convert cluster# to [ioreq.sectno] + [spot] (location inside FAT)
    call readsect               ; read FAT sector set by go2entry
done:
    ret

;--- if we're on a logical drive, attempt
;--- to jump to respective phys. drive.
;--- won't work for ramdisks - also, the HD number in 
;--- the boot sector is generally a rather unreliable info.
log2phys:
if 1
;--- v1.1: if current disk is an image file, just reset [qwDiskStart];
;--- trydevice() cannot be called because [filenamebuffer] might have changed.
    cmp [ioreq.rwfunc], RWF_FILE; image file?
    jnz @F
    mov [ioreq.drvtype], DT_FILE
    xor eax, eax
    mov dword ptr [qwDiskStart], eax
    mov [ioreq.sectno], eax
    call readsect
    jmp log2phys_file
@@:
endif
    mov al, [hdnumber]
    and al, al
    jz @F
    mov bh, DT_PHYSICAL
    call trydevice
;    jnc drive_ok
    jc @F
log2phys_file:
    call setvariables           ; set all obtainable parameter variables
@@:
    ret

ctlenter_fat:
    cmp [bFilesys], FS_EXFAT    ; not yet for exFAT
    jz done
    call getentrynumber         ; translate [currSector][spot] to entry# in EAX
    mov ebx, eax
    jmp finddirentry

handle_ctlenter endp

;--- if "restrict" is used, all items on the sector stack become invalid

clearsecstack proc
    movzx bx, [secstk_top]
    dec bl
    and bl, NUMSECSTKITEMS-1    ; items must be a power of 2
    shl bx, SECSTKSHIFT
    mov [bx][secstk].bFlags, 0
    ret
clearsecstack endp

;--- push/pop items on/from sector stack

popsecstack proc
    push bx
    movzx bx, [secstk_top]
    dec bl
    and bl, NUMSECSTKITEMS-1
    shl bx, SECSTKSHIFT
    test [bx][secstk].bFlags, 1
    jz done
    mov [bx][secstk].bFlags, 0
    mov eax, [bx][secstk].dwSector
    dec [secstk_top]
    mov [ioreq.sectno], eax
    call readsect
    mov ax, [bx][secstk].wSpot
    mov dl, 0
    call movecursor
done:
    pop bx
    ret
popsecstack endp

;--- push sector# in eax onto sector stack

pushsecstack proc
    push bx
    movzx bx, [secstk_top]
    and bl, NUMSECSTKITEMS-1
    shl bx, SECSTKSHIFT
    mov [bx][secstk].dwSector, eax
    push [spot]
    pop [bx][secstk].wSpot
    mov [bx][secstk].bFlags, 1
    inc [secstk_top]
    pop bx
    ret
pushsecstack endp

;--- ctrl-left handling

searchpredecessor proc
    cmp [bRegion], RG_FAT               ; in FAT region?
    je recursefat
    test [bRegion], RG_DATA             ; or in data?
    jz done

    call getkbdstatus                   ; get kbd status in AH
    and ah, 11b                         ; mask out shift status
    mov [bShift], ah

    mov eax, [currSector]
    call sector2cluster                 ; get cluster number in EAX
    mov esi, preindata
    jmp recursefatdata
preindata:
    cmp [bShift], 0
    jz setcluster
    call cluster2sector                 ; if shift has been pressed
    movzx ecx, [wSpC]                   ; go to last sector of previous cluster
    dec ecx
    add eax, ecx
    jmp setsector

recursefat:
    call getentrynumber                 ; get eax = current entry number
    cmp eax, 2
    jb done                             ; valid entries start at 2
    mov esi, dochainjump                ; what to do if predecessor is found

recursefatdata:
    mov ebx, eax                        ; save start entry for ascending scan

;--- the old code assumed that the cluster that we search and that links to the
;--- current one is "below" ( hence it starts decrementing from the current
;--- cluster# ). This assumption was too optimistic, it's absolutely valid that
;--- a chain is "decending", that is, the predecessor has a higher entry#.
;--- However, it's a good strategy to first scan the lower entries.

    @getstarttime
    or edi, -1                          ; begin with decending from current entry#
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
    call darkclr3
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
    jne nextentry                       ; no...keep recursing
    jmp esi                             ; found

loop_done:
    add edi, +2                         ; no predecessor found "below"
    mov eax, ebx                        ; so the region "above" is to be scanned
    mov cx, CStr("ascending")
    jmp nextentry

chainnotfound:
    mov dx, offset nochainmsg           ; "recursive link not found"
    call printerror
done:
    @dprintduration "searchpredecessor"
    ret
searchpredecessor endp

;--- ctrl-right key handling.
;--- if in FAT, jump to linked (=next) entry in chain
;--- if in data region, jump to linked cluster in FAT

;--- for exFAT, it might be that the FAT entry is NULL -
;--- this usually means that the file is stored contiguous;
;--- and the successor ( if one exists ) is then the next cluster#.
;--- problem is that WDe doesn't know the file size and hence
;--- can't tell when the end is reached.

jumpsuccessor proc

    cmp [bRegion], RG_FAT
    je jumpfatsuccessor
    test [bRegion], RG_DATA
    jz done
;jumpdatasuccessor:
    mov eax, [currSector]
    mov [fromfat], FF_FAT1
    call sector2cluster                 ; get respective cluster number
    call getfatentry                    ; read fat entry
    jc done
    mov dx, offset endofchainmsg
    cmp eax, 0fffffffh
    jz nuprinterror
    jmp setcluster                      ; set the cluster# read from FAT
;-------------------------------------------------------
jumpfatsuccessor:

    call getcurrententry

dochainjump::             ; <--- for recurse ( Ctrl-left in FAT )

    cmp eax, 2            ; disregard ebx, which is the current entry #
    jb done               ; we only care about eax, the value stored there.
;    cmp eax, 0FFFFFF7h
;    jae done

    cmp eax, [dwLastCluster]
    ja done
    call go2entry                 ; will set [currSector] + [spot]=0
    mov eax, [currSector]
    cmp eax, [ioreq.sectno]
    jz done
    call readsect                 ; read the sector set by go2entry
done:
    ret
jumpsuccessor endp

;--- display error msg "invalid cluster # xxx"
;--- in: ebx=cluster# to display

invalclusterror proc
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset invalclustmsg, ebx
    jmp nuprinterror
invalclusterror endp

;--- handle Enter key
;--- in FAT area: jump to data area of cluster at current offset
;--- in DIR area: jump to starting cluster of dir entry
;--- in GPT area: jump to current partition's start LBA

handle_enter proc

if ?GPT
    cmp [bViewmode], VM_GPTENTRY        ; in GPT?
    je do_gptentry
endif
if ?MBRENTER
    cmp [bViewmode], VM_MBR             ; in MBR?
    je do_mbrentry
endif
    test [bFilesys], FS_FATXX           ; FAT disk?
    je done

    cmp [bViewmode], VM_DIRECTORY
    je do_direntry

    cmp [bRegion], RG_FAT
    jne done

    call getentrynumber                 ; get the cluster number for [currSector][spot]

;--- translate cluster# in eax, reset spot to 0.
;--- entry used by:
;--- 1. ctrl-left data region
;--- 2. ctrl-right data region
;--- 3. Goto Cluster menu item
;--- 4. alt-left & alt-right data region

setcluster::
    mov ebx, eax                        ; store in ebx for invalclusterror 
    call cluster2sector                 ; multiply it out to get the
setsector::
    cmp eax, [lastSector]                ; corresponding sector number
    ja invalclusterror                  ; verify that it's a valid sector
setsector2:
    mov [ioreq.sectno], eax
    call readsect
    xor ax, ax
    mov dl,0
    call movecursor
done:
    ret

;--- similar to setcluster, but save current pos onto stack

stacksetcluster:
    mov ebx, eax                        ; store in ebx for invalclusterror 
    call cluster2sector                 ; multiply it out to get the
stacksetsector:
    cmp eax, [lastSector]                ; corresponding sector number
    ja invalclusterror                  ; verify that it's a valid sector
    cmp eax, [currSector]              ; don't push sector# if dst==src
    jz setsector2
    push eax
    mov eax, [currSector]
    call pushsecstack                   ; push sector# in eax onto sector stack
    pop eax
    jmp setsector2

do_direntry:

;--- get the cluster# of the dir entry

    call bufferinsi
    mov bx, [spot]
    and bl, 11100000b

    cmp [bFilesys], FS_EXFAT            ; exFAT direntry structure?
    jz exfat_enter

    cmp [si+bx].SFNENTRY.bAttr, 0Fh     ; lfn entry?
    jz done
    mov ax, [si+bx].SFNENTRY.wClHigh
    shl eax, 16
    mov ax, [si+bx].SFNENTRY.wClLow

    cmp eax, 2
;--- jump to root directory if cluster# invalid?
;--- not generally, only if name of entry is ".."
;    jb jumptoroot
    jae stacksetcluster
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
    jmp stacksetcluster
isprim:
    and al, 1Fh
    cmp al, EXFPTC_ALLOCBM
    jz @B
    cmp al, EXFPTC_UPCASET
    jz @B
    ret
if ?MBRENTER
do_mbrentry:
    call bufferinsi
    cmp word ptr [si+1FEh], 0AA55h  ; don't jump if no signature
    jnz done
    mov ax, [spot]
    sub ax, PTABOFS     ; cursor in a partition entry?
    jb done
    cmp ax, 4*sizeof PTABENT
    ja done
    and al, 0F0h
    mov bx, PTABOFS
    add bx, ax
    mov al, [si+bx].PTABENT.bType
    cmp al, 0
    jz done
    mov eax, [si+bx].PTABENT.start
    add eax, [currSector]
    jmp stacksetsector
endif
if ?GPT
do_gptentry:
    call bufferinsi
    mov bx, [spot]
    and bl, 80h
 ife ?SN64
    cmp dword ptr [si+bx].GPTENTRY.qwFirstLBA+4, 0  ; ignore if LBA is not 32-bit
    jnz done
 endif
    mov eax, dword ptr [si+bx].GPTENTRY.qwFirstLBA+0
 if ?SN64
    mov edx, dword ptr [si+bx].GPTENTRY.qwFirstLBA+4
 endif
    jmp stacksetsector
endif

handle_enter endp

;--- submenu view

submenu_view proc

    @mstart viewmenu
    @mitem MS_Auto, autoview
    @mitem MS_MBR,  specview
    @mitem MS_Boot_Sector, specview
    @mitem MS_Fat12, specview
    @mitem MS_Fat16, specview
    @mitem MS_Fat32, specview
    @mitem MS_Directory, specview
    @mend viewmenu

    mov dx, viewmenu + lviewmenu shl 8
    mov cl, 2
    jmp pushmenustack

specview:
    sub ah, F1_KEY
    mov dl, ah
    cmp dl, VM_FAT12
    jne @F
    mov eax, [currSector]
    mov [dwFat12start], eax
@@:
    mov [bStaticview], TRUE
    jmp setviewmode  ;set viewmode to DL
;-------------------------------------------------------
autoview:
    mov [bStaticview], FALSE
    jmp detectview

submenu_view endp

if ?DEBUG
    .data?
level dw ?    ; level of subdirectory reentrance
    .code
endif

;--- scan entries in a directory sector for a specific start cluster
;--- in: ebx=cluster to find
;---     sector# in [ioreq.sectno]
;--- if directory entries are found, recursively call scanforcluster.

scandir proc
    @dprintfln "scandir(%u): sector=%lu", level, [ioreq.sectno]
    mov si, offset sectbuffer
    mov cl, 512 / DIRENTSIZE
nextentry:
    cmp [si].SFNENTRY.name_, 0
    jz skipdir
    cmp [si].SFNENTRY.name_, 0E5h
    jz skipentry
    cmp [si].SFNENTRY.bAttr, 0Fh
    jz skipentry
    mov ax, [si].SFNENTRY.wClHigh
    shl eax, 16
    mov ax, [si].SFNENTRY.wClLow
    cmp eax, 0
    jz skipentry
    cmp eax, ebx
    jz found
    test [si].SFNENTRY.bAttr, DA_DIRECTORY
    jz skipentry
    cmp dword ptr [si].SFNENTRY.name_, "   ."
    jz skipentry
    cmp dword ptr [si].SFNENTRY.name_, "  .."
    jz skipentry
    push cx
    push si
    push [ioreq.sectno]
    @dprintfln "scandir(%u, %s): calling scanforcluster", level, si
if ?DEBUG
    inc [level]
endif
    call scanforcluster
if ?DEBUG
    dec [level]
endif
    pop [ioreq.sectno]
    pop si
    pop cx
    jc found2
    call diskaccess_read
skipentry:
    add si, sizeof SFNENTRY
    dec cl
    jnz nextentry
    xor ax, ax
    ret
skipdir:
    or eax, -1
    clc
    ret
found:
    mov eax, [ioreq.sectno]
    mov dx, si
    sub dx, offset sectbuffer
    @dprintfln "scandir(%u): found cluster %lX at %X", level, ebx, dx
    stc
found2:
    ret
scandir endp

;--- scan directories to find cluster# in ebx
;--- in: cluster of directory in EAX

scanforclf1x:
    pushd 0
    mov eax, [dwRootSect]
    jmp scanxxx

scanforcluster proc
    @dprintfln "scanforcluster(%u): eax=%lX", level, eax

    call checktime
    jc @F
    call checkabort
    je abort
    push eax
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset directoryscanmsg, eax
    call printbottom
    pop eax
    call darkclr3
@@:

    push eax
    call cluster2sector
scanxxx::
    mov [ioreq.sectno], eax
    mov cx, [wSpC]
nextsector:
    push cx
    call diskaccess_read
    call scandir
    pop cx
    jc found
    cmp eax, -1
    jz dirdone
    inc [ioreq.sectno]
    loop nextsector
    pop eax
    call getfatentry
    @dprintfln "scanforcluster(%u): called getfatentry, eax=%lX", level, eax
    jc @F
    cmp eax, 2
    jb @F
    cmp eax, 0ffffff7h
    jb scanforcluster
@@:
    clc
    ret
dirdone:
found:
    lea sp, [esp+4]
    ret

;--- aborting; due to recursion SP has to be restored. 

abort:
    mov sp, bp
    call readcursect
    ret

scanforcluster endp

;--- find directory entry with specific start cluster (in EBX)

finddirentry proc
if ?DEBUG
    mov level, 0
endif
    mov bp, sp
    @dprintfln "finddirentry: ebx=%lX", ebx
    cmp ebx, 2
    jb _ret
    test [bFilesys], FS_FAT32
    jnz @F
    call scanforclf1x
    jnc denotfound
    jmp defound
@@:
    mov eax, [dwRootCluster]   ; FAT32 only
    cmp eax, ebx
    jnz @F
    mov eax, [dwRootSect]      ; it's the root cluster
    mov [ioreq.sectno], eax
    call readsect
    xor ax, ax
    jmp ffroot
@@:
    call scanforcluster
    jnc denotfound
defound:
    mov [bUpdateScreen], 1
    xchg eax, [currSector]
    call pushsecstack
    mov ax, dx
ffroot:
    mov dl, 0
    call movecursor
    ret
denotfound:
    call readcursect
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset nodirentryfound, ebx
    call nuprinterror
_ret:
    ret

finddirentry endp

;--- submenu "find": "string hex next MBR boot sector, FAT, directory,..."

submenu_find proc

    @mstart searchmenu
    @mitem MS_String, findstring
    @mitem MS_Hex, findhex
    @mitem MS_Next, findnext
    @mitem MS_INACTIVE, findfileentry
    @mitem MS_MBR, findmbr
    @mitem MS_BootSec, findbs
    @mitem MS_Fat, findfat
    @mitem MS_Directory, finddir
    @mend searchmenu

    mov dx, searchmenu + lsearchmenu shl 8
    mov cl, 2
    jmp pushmenustack

;--- find file
;--- current sector must be a directory

findfileentry:
if 0
    mov ax, _ret
    call getfilename
    jcxz _ret
endif
    ret

;--- find directories

finddir:
    mov bp, finddircb
    jmp findcommon
finddircb:
    call IsDirectory    ; see if current sector contains direntries
    ret

;--- find boot sector
;--- rather simple check for "jmp short" at pos 0 and
;--- bs signature at pos 1FCh

findbs:
    mov bp, findbscb
    jmp findcommon
findbscb:
    cmp dword ptr [si+1fch], 0AA550000h           ; check for boot sig ++
    jne @F
    cmp byte ptr [si], 0EBh                       ; check for jmp
    je _ret
@@:
    stc
_ret:
    ret

;--- find FAT
;
; This function is slightly bugged; the first byte is a media descriptor
; byte and only makes the partition more likely to be a certain type of
; fat.  Fat finding should only verify that the first byte is a valid
; media descriptor and then attempt to identify the fat type.
;
findfat:
    mov bp, findfatcb
    jmp findcommon
findfatcb: 
    xor bx, bx                    ; 14.4.2022: TEST, just to ensure that BX has a defined value
    cmp byte ptr [si], 0F0h       ; fat12
    je n12sfl                     ; n12sfl expects BX to be set up!
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
    je foundfat
findfat2:
    stc
foundfat:
    ret

;--- find MBR, checks
;--- 1. short jmp at pos 0
;--- 2. signature at pos 1FCh
;--- 3. no fsinfo signature at pos 1E4h
;--- 4. partition bytes

findmbr:
    mov bp, findmbrcb
    jmp findcommon
findmbrcb:
    cmp byte ptr [si+0], 0EBh
;    je skipmbr                         ; v0.50: check for "not equal"
    jne skipmbr
;--- v0.99: at offset 1FCh of an MBR are the last 2 bytes of last PT entry
;    cmp dword ptr [si+1fch], 0AA550000h ; mbr signature
    cmp word ptr [si+1feh], 0AA55h      ; mbr signature
    jne skipmbr
    cmp dword ptr [si+1e4h], 061417272h ; fsinfo sector signature
    je skipmbr                          ; annoying of microsoft to
                                        ; give it an MBR signature
    mov bx, PTABOFS                     ; bx = offset start partition table
    xor al, al
@@:
    mov ah, [si+bx].PTABENT.bBoot       ; "active" partition byte
    test ah, 01111111b                  ; any bits other than 7 set?
    jnz skipmbr                         ; yes, not a valid MBR.
    shl ah, 1                           ; shift bit 7 out of the register
    adc al, 0                           ; if it was 1, increase al
    add bx, sizeof PTABENT
;--- v0.99: there are 4 entries in PT, that is 1BEh + 40h = 1FEh
;    cmp bx, 1EEh
    cmp bx, PTABOFS + 4 * sizeof PTABENT
    jne @B
    cmp al, 1                           ; more than one active partition?
    je foundmbr                         ; no, MBR found.
skipmbr:
    stc
foundmbr:
    ret

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

    cmp [bDark],0
    jz @F
    call stdclr
    call clearviewarea
@@:
    call printtopline
    cmp [wBps], VIEWBYTES             ; in case the sector doesn't exactly fit on the screen, update offset
    jz @F
    call printoffset
@@:
    call printsector
    mov bUpdateScreen, 0

    mov bUpdateView, 1
    cmp [bStaticview], TRUE           ; forced view?
    je @F
    call detectview
@@:
    ret

updatescreen endp

;--- detect the view type

detectview proc
    mov dl, [bRegion]
    test dl, RG_RESERVED or RG_FAT or RG_ROOT or RG_DATA  ; known FAT region?
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
    cmp [currSector], 0
    je setbsview

	cmp [bFilesys], FS_FAT32
	jnz setdataview

    movzx eax, [backupbs]
    cmp [currSector], eax
    je setbsview
    movzx edx, [fsinfo]
    cmp [currSector], edx             ; in the fsinfo sector?
    je setfsview                      ; then set fsinfo view
    add edx, eax                      ; checks if we're in the backup
    cmp [currSector], edx               ; fsinfo sector...but it assumes
    je setfsview                      ; it's the same distance from the backupbs
setdataview:
    mov dl, VM_DATA                   ; as the main fsinfo is the main
    jmp setDLview                     ; bootsector, which is wrong.
setdirview:
if 1
    call dirview_ascii                ; if in dirview, colorize the ascii part
endif
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
    test [bFilesys], FS_FAT32
    jnz setDLview
    mov dl, VM_FAT16
    cmp [bFilesys], FS_FAT16
    je setDLview
    mov dl, VM_FAT12

    mov eax, [dwReserved]
    add eax, [dwSpF]
    cmp eax, [currSector]
    jbe @F
    sub eax, [dwSpF]
@@:
    mov [dwFat12start], eax
setDLview:
    call setviewmode                  ; set viewmode to DL
    ret
detectview endp

if 1

;--- render a nice ascii dirview
;--- show: 
;---  - file names in white
;---  - directories in bright yellow
;---  - rest in light gray

dirview_ascii proc
    cmp [bFilesys], FS_EXFAT          ; exFAT?
    jz dirview_ascii_exfat            ; needs special handling
    pusha
    mov si, offset sectbuffer
    mov [scrn_xy], COLASC or (ROWXXX shl 8)
    call cbuffer_offset
    mov cx, 512 / DIRENTSIZE
nextentry:
    cmp byte ptr [si], 0
    jz done
    push di
    mov ah, 0
    mov al, COL_STATTEXT        ; light grey
    cmp byte ptr [si], 0E5h
    jz @F
    mov ah, 1
    cmp byte ptr [si+0Bh], 0Fh  ; LFN?
    jz @F
    mov ah, 0
    mov al, COL_YELLOWFG        ; bright yellow
    test byte ptr [si+0Bh], 10h
    jnz @F
    mov al, COL_WHITEFG         ; bright white
@@:
    mov dl, 11
nextchar1:
    inc di
    stosb
    dec dl
    jnz nextchar1
    mov dl, 16-11
    mov al, COL_STATTEXT
nextchar2:
    inc di
    stosb
    dec dl
    jnz nextchar2
    pop di


    add di, [vidcolsize]
    push di
    mov dl, 16
nextchar3:
    inc di
    stosb
    dec dl
    jnz nextchar3
    pop di

if 1
    cmp ah, 0
    jz nolfn
    pusha
    sub di, [vidcolsize]
    mov si, offset lfntab
nextofs:
    lodsw
    movzx bx, al
    movzx cx, ah
    shl bx, 1
nextlfnchar:
    cmp bl, 10h*2
    jnz @F
    add di, [vidcolsize]
    sub di, 16*2
@@:
    mov byte ptr es:[di+bx+1], COL_GREENFG
    add bx, 2*2
    loop nextlfnchar
    cmp si, offset lfntab + 3*2
    jnz nextofs
    popa
nolfn:
endif

    add di, [vidcolsize]
    add si, DIRENTSIZE
    loop nextentry
done:
    popa
    ret
dirview_ascii endp

;--- the exFAT ascii part colorization is a bit simple yet.
;--- the names are colored white, the rest light grey.

dirview_ascii_exfat proc
    pusha
    mov si, offset sectbuffer
    mov [scrn_xy], COLASC or (ROWXXX shl 8)
    call cbuffer_offset
    mov cx, 512 / DIRENTSIZE
nextentry:
    mov ah, COL_STATTEXT
    cmp byte ptr [si], 0C1h
    jnz @F
    mov ah, 1Fh
@@:
    push di
    mov al, COL_STATTEXT
    inc di
    stosb
    mov al, ah
    mov dl, 15
@@:
    inc di
    stosb
    dec dl
    jnz @B
    pop di
    add di, [vidcolsize]
    push di
    mov dl, 16
@@:
    inc di
    stosb
    dec dl
    jnz @B
    pop di
    add di, [vidcolsize]
    add si, DIRENTSIZE
    loop nextentry
    popa
    ret
dirview_ascii_exfat endp

;--- if the view changes from dirview to another,
;--- the attributes in the ascii part have to be reset.

nodirview_ascii proc
    pusha
    mov [scrn_xy], COLASC or (ROWXXX shl 8)
    call cbuffer_offset
    mov ch, VIEWBYTES / 16
    mov al, COL_DEFAULT
nextrow:
    push di
    mov cl, 16
@@:
    inc di
    stosb
    dec cl
    jnz @B
    pop di
    add di, [vidcolsize]
    dec ch
    jnz nextrow
    popa
    ret
nodirview_ascii endp

endif

;--- IN: [stringbuffer]: search string
;---      CX: size of string
;---      AL: 0=normal start, 1=find next ( skips byte at spot pos )
;--- search starts at cursor pos of current sector

stringsearch proc

    push [currSector]
    pop [ioreq.sectno]

    call spot2bufofs                    ; bx = wSectOfs + spot

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
    dec [ioreq.sectno]              ; just read it, don't care about the cache anymore!
    call readsect                   ; use readsect to update currSector
    jmp sx1
@@:
    mov ax, di
    mov cl, [bSecSh]
    shr ax, cl
    call findreadadjust             ; expects sec# in AL
    movzx eax, ax
    add eax, [ioreq.sectno]
    mov [currSector], eax
    mov [bUpdateScreen], 1
sx1:
;--- set sector offset
    mov ax, 1
    mov cl, [bSecSh]
    shl ax, cl
    dec ax
    xor ax, VIEWBYTES - 1
    and ax, di
    mov [wSectOfs], ax

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
    mov eax, [lastSector]
    sub eax, [ioreq.sectno]
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

;   @dprintf "programming error in searchstring, di=%X dx=%X sector=%lu", di, dx, [ioreq.sectno]
;   ret

stringnotfound:
    pop ax
    @dprinttime "stringsearch; duration %lu ms"
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
    mov eax, [lastSector]           ; how many sectors exist until end?
    inc eax
    movzx edx, [dapacket.sectors]
    add [ioreq.sectno], edx
    add edx, [ioreq.sectno]
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

;--- common routine for find
;---  + directory
;---  + boot sector
;---  + fat
;---  + mbr
;--- starts with current sector
;--- out: SI=current 512-chunk of sector

findcommon proc

    mov [handling], QUERY_SKIP; inside findcommon
    push [currSector]        ; v0.99: init ioreq.sectno in case the
    pop [ioreq.sectno]        ; callback finds something at once.
nextfind:
    call bufferinsi
    call bp
    jnc doneX

    call checktime
    jc @F
    call checkabort
    je abort                  ; pop address, update screen, then RET
    mov eax, [lastSector]
    sub eax, [ioreq.sectno]
    mov cx, offset searchingmsg
    call printprogress
@@:
    mov ax, [wBps]            ; reached end of physical sector?
    sub ax, VIEWBYTES
    cmp [wSectOfs], ax
    jb dontrw
    mov eax, [ioreq.sectno] ; check if end of disk has been reached
    inc eax
    cmp eax, [lastSector]
    ja notfound
    mov [ioreq.sectno], eax ; not yet, try to read next sector
    call diskaccess_read
    jc abort
    mov [wSectOfs], 0
    jmp nextfind
dontrw:
    add [wSectOfs], VIEWBYTES
dontinc:
    jmp nextfind

doneX:                  ; found directory/fat/bs/mbr
    push [ioreq.sectno]
    pop [currSector]   ; update current sector
    ret
notfound:
    mov dx, offset searcherror ; "no (more) matches found"
    call nuprinterror
abort:
    call readcursect
    ret
findcommon endp

;--- file submenu

submenu_file proc

    @mstart filemenu               ; file menu cmd table
    @mitem MS_Save_to_File, submenu_fileoptions
    @mitem MS_Restore_from_File, submenu_fileoptions, FILEMENU_RESTORE
    @mitem MS_Change_Disk, select_disk
    @mend filemenu

    mov al, MS_Restore_from_File
    cmp [ioreq.drvtype], DT_CDROM
    jne @F
    mov al, MS_INACTIVE            ; for CDROMs, remove "restore"
@@:
    mov cl, FILEMENU_RESTORE
    call setmenuitem
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
;--- IN: [bChainmode] = FAT_CHAIN or FILE_CHAIN
;---     DI=routine to get entry# if FAT_CHAIN ( usually getcurrententry )

savechain proc
    mov [fromfat], FF_FAT1
    mov [bSkipFat], 0
    xor ebp, ebp                            ; ebp used to count sectors saved/restored
    cmp [bChainmode], FAT_CHAIN
    je beginfatchainsave

;--- we're in a directory and are to save a file chain

    call bufferinsi
    mov bx,[spot]
    and bl, 11100000b                       ; chop off 0-31 bytes to set bx to

    cmp [bFilesys], FS_EXFAT
    jz exfat_savechain

    mov eax, [si+bx].SFNENTRY.dwSize        ; filesize
    mov [dwFilesize], eax
    test [si+bx].SFNENTRY.bAttr, DA_DIRECTORY
    setnz [bIsDirectory]
if ?SETFILEDATETIME
    mov eax, dword ptr [si+bx].SFNENTRY.wLUTime
    mov [dwFileDateTime], eax
endif
    mov ax, [si+bx].SFNENTRY.wClHigh        ; high cluster word
    shl eax, 16
    mov ax, [si+bx].SFNENTRY.wClLow         ; low cluster word

savefilechain:                              ; <- common for both FATxx and exFAT file chain
    mov [dwCurrCluster], eax                ; back the cluster number up
    push eax
    mov ax, deliverfn
    call getfilename
    pop eax
    jcxz done                               ; cx=0 if user has ESCaped
    call cluster2sector                     ; returns -1 if outside of valid cluster range
    cmp eax, [lastSector]
    ja invalclust
    call getnextcluster
    jmp startchainsaving

deliverfn:
    cmp [bFilesys], FS_EXFAT
    jnz @F
    call getexfatname
    xor ax, ax
    ret
@@:
    call getfatxname
    xor ax, ax
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
    call srcommon                         ; get filename
    call di                               ; get cluster# to start with ( eax, ebx )
    mov [dwCurrCluster], eax
    mov eax, ebx
    call cluster2sector
    cmp eax, [lastSector]
    ja invalclust                         ; current entry is beyond data end

startchainsaving:
    push ax
    call createfile
    pop ax
    jc done

chainsaveloop:
    movzx ebx, [wSpC]                     ; writefile will write one cluster at a time
    mov [dwValue], ebx
    add ebp, ebx
    mov di, offset mydisp                 ; function address to call inside writefile
    call writefile
    jc done

    mov eax, [dwCurrCluster]
    call cluster2sector
    cmp eax, [lastSector]
    ja donechainsave
    call getnextcluster
    jmp chainsaveloop

getnextcluster:
    push eax
    mov eax, [dwCurrCluster]
    cmp [bSkipFat], 0       ; does a fat chain exist
    jz ncfromfat
    inc eax                 ; no, increment cluster#
    dec [dwNumCluster]
    jns dgnc                ; and check if EOF has been reached
    or eax, -1
    jmp dgnc
ncfromfat:
    call getfatentry        ; get next cluster# from fat chain
dgnc:
    mov [dwCurrCluster], eax
    pop eax
    ret

mydisp:
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("Writing file, %lu sectors written, saving cluster %lX..."), ebp, [dwCurrCluster]
    jmp printbottom

donechainsave:
    cmp [bChainmode], FAT_CHAIN          ; file chain?
    je notruncate

;--- if file chain is for a directory, file size is 0
;--- in this case, don't ask if file is to be truncated.
    cmp [bIsDirectory], 1
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
    mov bx, [wFilehandle]
    jnc @F
    mov dx, word ptr [dwFilesize+0]
    mov cx, word ptr [dwFilesize+2]
    mov ax, 4200h                       ; seek from start of file
    int 21h
    xor cx, cx                          ; write to file, 0 bytes (truncate)
    mov ah, 40h
;    mov bx, [wFilehandle]
    int 21h
@@:
if ?SETFILEDATETIME
    mov cx, word ptr [dwFileDateTime+0] ; set file's date & time
    mov dx, word ptr [dwFileDateTime+2]
;    mov bx, [wFilehandle]
    mov ax, 5701h                       ; set file date/time
    int 21h
endif
notruncate:
    call closefile

    call readcursect                    ; [currSector] is untouched
    mov eax, ebp
sectorswritten2file::
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset donewritefile, eax
    call nuprinterror
    ret

savechain endp

;--- called from submenu "file options"
;--- restore a cluster chain from a file
;--- IN: [bChainmode] = FAT_CHAIN or FILE_CHAIN
;        entry of file in DTA
;    DI: for FAT chains: routine to get entry#

restorechain proc
    call srcommon               ; calls findfile ( DTA set )

    cmp [bChainmode], FILE_CHAIN
    jz @F
    call di
    mov eax, ebx
    jmp restclusts
@@:
    mov [fromfat], FF_FAT1
    call bufferinsi
    mov bx, [spot]
    and bl, 11100000b

    cmp [bFilesys], FS_EXFAT
    jnz @F
    mov eax, [si+bx].EXFDIRSS.dwFirstCl
    test [si+bx].EXFDIRSS.secflgs, EXFPF_NOCHAIN
    jnz exfat_restorechain
    jmp restclusts
@@:
    mov [bSkipFat], 0
if 0                            ; chain is restored even if file isn't big enough
    mov eax, [dwFilesize]
    cmp eax, [si+bx].SFNENTRY.dwSize
    jb toosmallerr
endif
    mov ax, [si+bx].SFNENTRY.wClHigh
    shl eax, 16
    mov ax, [si+bx].SFNENTRY.wClLow

restclusts:

    push eax
    call cluster2sector
    cmp eax, [lastSector]
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
    cmp eax, [lastSector]
    ja clusterr
    mov [ioreq.sectno], eax
    mov ax, [wSpC]
    mov [wSpCcnt], ax

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
;--- so read the sector# in [ioreq.sectno] into sectbuffer
;--- and copy the missing bytes from sectbuffer to our write buffer.

    call diskaccess_read
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
    call diskaccess_write
    jc done
    cmp ax, cx                ; EOF reached?
    jne donerestchain

    dec [wSpCcnt]
    jz @F
    inc [ioreq.sectno]
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

    call readcursect
    mov dx, offset donewritedisk
    call printerror
;    call resetmenustack       ; auto return to main menu
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
    mov dx, offset filereaderr
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

;--- get current FAT entry
;--- IN:  [currSector], [spot]
;--- OUT: ebx=cur FAT entry, eax=data stored at cur FAT entry
;--- called by:
;---  1. jumpsuccessor  ( ctrl-right while in FAT )
;---  2. savechain/restorechain ( to get start cluster of FAT chain to save/restore)

getcurrententry proc
    call getentrynumber     ; translate [currSector][spot] to entry# in EAX
    mov ebx, eax            ; ebx = current entry #
    jmp getfatentry         ; other reg's corrupted
getcurrententry endp

;--- common routine for save/restore
;--- 1. prompt user to enter a filename
;--- 2. if "restore"-branch, check if file exists
;--- in case an error occurs, skip caller's return address and return.

srcommon proc
    push ax
    push di
    mov ax, sr_ok
    call getfilename
    pop di
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

;--- submenu "file options" for items "save to file"/"restore from file"

submenu_fileoptions proc

    @mstart cdfileoptmenu
    @mitem MS_Save_to_File, srsecrange
    @mitem MS_Dump_CD_As_ISO, dumpiso
    @mend cdfileoptmenu

;--- physical: F1=Input F2=MBR F3=P1 F4=P2 F5=P3 F6=P4

    @mstart pdfileoptmenu
    @mitem MS_Input, srsecrange
    @mitem MS_MBR, srsector0
    @mitem MS_Partition1, srhdcheck
    @mitem MS_Partition2, srhdcheck
    @mitem MS_Partition3, srhdcheck
    @mitem MS_Partition4, srhdcheck
    @mend pdfileoptmenu

;--- logical: F1=Input F2=Boot F3=Fat1 F4=Fat2 F5=Root F6=Partition [F7=chain]

    @mstart ldfileoptmenu
    @mitem MS_Input,       srsecrange
    @mitem MS_Boot_Sector, srsector0
    @mitem MS_Fat1,        srfat1
    @mitem MS_Fat2,        srfat2
    @mitem MS_Root,        srroot
    @mitem MS_Partition,   srdisk
    @mitem MS_INACTIVE, srchain, LDFILEOPT_CHAIN
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

;--- for FAT drives, refresh menu item "chain"

;    mov [bChainmode], NO_CHAIN      ; reset chain flag
    push cx
    mov ah, NO_CHAIN
    call setchainmode
    pop cx
    mov [bUpdateView], 1

;--- set menu "input, boot sector, fat1, ..."

    mov dx, ldfileoptmenu + lldfileoptmenu shl 8
    test [bFilesys], FS_FATXX      ; non-FAT drives?
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
    cmp [bChainmode], NO_CHAIN
    je @F
    mov di, offset getcurrententry ; for FAT save/restore: routine to get starting cluster 
srchain2:                          ; <- entry save/restore root entry
    cmp [srflag], SR_RESTORE
    je restorechain
    jmp savechain
@@:
    ret

;--- save/restore partition 1/2/3/4
;--- in: AH=function key (F3-F6)

srhdcheck:

    mov cl, ah
    sub cl, F3_KEY
    shl cl, 2                      ; 00-03 -> 00-0C
    movzx si, cl
    mov eax, [si][dwPartitions]
    shl cl, 2                      ; 00-0C -> 00-30
    movzx bx, cl
    add bx, PTABOFS + PTABENT.size_

;--- EAX = partition start sector, BX = offset in MBR for partition

    test eax, eax                  ; "empty" partition?
    jz donesr
    call srcommon

;--- read sector 0

    mov [ioreq.sectno], 0
    call diskaccess_read
    jc donesr
    mov ebx, dword ptr [sectbuffer+bx]   ; get size of partition
    mov [dwValue], ebx
    cmp [srflag], SR_RESTORE
    je endrestsectors
endsavedrive:                      ; <--- by srsecrange, srbs, srfatx, srroot
    call savedata
donesr:
    ret

;--- callback for savechain()/restorechain() to get the
;--- start cluster of the FAT chain to save.

getrootentry:
    mov eax, [dwRootCluster]
    mov ebx, eax
    call getfatentry
    ret

srroot:                            ; save/restore root dir
    test [bFilesys], FS_FAT32      ; FAT32?
    je @F
    mov [bChainmode], FAT_CHAIN    ; then use FAT chain save/restore
    mov di, offset getrootentry
    jmp srchain2
@@:
    call srcommon
    mov eax, [dwRootSect]
    movzx edx, [wRootsectors]
    mov [dwValue], edx
    cmp [srflag], SR_SAVE
    je endsavedrive
    jmp endrestsectors

restdrive:                         ; restore partition from file
    mov eax, [lastSector]
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
    mov eax, [currSector]
    jmp endsavedrive
@@:
    ret

restsecrange:                 ; restore sector range
    call srcommon             ; calls findfile
    mov eax, [dwFilesize]
    movzx ebx, [wBps]
if 0
    cmp eax, ebx
    jae filesizeok
toosmallerr:
    mov dx, offset filetoosmall
    call printerror
    ret
filesizeok:  
endif
;    mov eax, [dwFilesize]
    xor edx, edx
    div ebx
    cmp edx, 1
    cmc
    adc eax, 0
    jz nosr
    mov ebx, [lastSector]
    sub ebx, [currSector]
    inc ebx
    cmp eax, ebx                          ; if there are more sectors in the
    jbe mvok                              ; file than there are remaining
    xchg eax, ebx                         ; on the partition; then set number
mvok:                                     ; of partition sectors remaining
                                          ; as maxvalue
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset szNoOfSectors, eax
    call getdecvalue
    jc nosr
    mov eax, [currSector]
    jmp endrestsectors
nosr:
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
    cmp edx, [lastSector]
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
    call resetmenustack          ; if file op was successful, go back to main menu
    jmp sectorswritten2file

toobig::
    mov dx, offset filetoobigmsg
    jmp printerror

invalidperror::
    mov dx, offset szInvalidRange; "invalid sector range"
    jmp printerror

writeprogress::
    mov eax, [dwValue]
    mov cx, offset writetofilemsg 
    jmp printprogress

savedata endp

;--- dump cd to .iso-file, partition to image-file

dumpiso proc

    mov edx, [lastSector]
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
    @dprinttime "writefile duration: %lu ms"

donedump:
    pushf
    call closefile
    popf
    jc done
    mov eax, [lastSector]
    inc eax
    call sectorswritten2file
    call resetmenustack               ; leave file option menu, back to main menu
done:
    ret

dumpiso endp

if ?GPT

guid2string proc c pGuid:ptr BYTE, pszStr:ptr byte

    mov bx, pGuid
    add bx, 16
    mov cx, 8
    xor ax, ax
@@:
    dec bx
    mov al, [bx]
    push ax
    loop @B
    mov cl, 4
@@:
    sub bx, 2
    push word ptr [bx]
    loop @B
    push CStr("{%08lX-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}")
    push pszStr
    call sprintf
    add sp, 14*2
    ret

guid2string endp

endif

;--- submenu goto

submenu_jumpto proc

    @mstart pdjumpmenu
    @mitem MS_Input, jumptosector
    @mitem MS_MBR, jumptobootsector
    @mitem MS_Partition1, jumptop1
    @mitem MS_Partition2, jumptop2
    @mitem MS_Partition3, jumptop3
    @mitem MS_Partition4, jumptop4
    @mend pdjumpmenu

if ?GPT
    @mstart pd2jumpmenu
    @mitem MS_Input, jumptosector
    @mitem MS_MBR, jumptobootsector
    @mitem MS_GPT_Header, jumptogpthdr
    @mitem MS_GPT, jumptogpt
    @mend pd2jumpmenu
endif

    @mstart ldjumpmenu
    @mitem MS_Sector,      jumptosector
    @mitem MS_Cluster,     jumptocluster
    @mitem MS_Boot_Sector, jumptobootsector
    @mitem MS_Fat1,        jumptofat1
    @mitem MS_Fat2,        jumptofat2
    @mitem MS_Root,        jumptoroot
    @mitem MS_Data_Area,   jumptodata
    @mend ldjumpmenu

    @mstart ntfsjumpmenu
    @mitem MS_Sector,      jumptosector
    @mitem MS_Boot_Sector, jumptobootsector
    @mitem MS_$MFT,        jumptomft
    @mend ntfsjumpmenu

    mov cl, 2
;--- set menu "input, MBR, partition1, ..."
    mov dx, pdjumpmenu + lpdjumpmenu shl 8
if ?GPT
    cmp [bTypeEE], 0
    jz @F
    mov dx, pd2jumpmenu + lpd2jumpmenu shl 8
@@:
endif
    cmp [ioreq.drvtype], DT_PHYSICAL
    je @F
    mov dx, ntfsjumpmenu + lntfsjumpmenu shl 8
    cmp [bFilesys], FS_NTFS
    jz @F
    mov dx, ldjumpmenu + 1 shl 8  ; for CDFS, just jump to sector
    cmp [ioreq.drvtype], DT_CDROM
    je @F
    mov dh, lldjumpmenu
@@:
    jmp pushmenustack

jumptop1:
    mov ebx, [dwPartitions+0*sizeof dword]
    jmp donejump
jumptop2:
    mov ebx, [dwPartitions+1*sizeof dword]
    jmp donejump
jumptop3:
    mov ebx, [dwPartitions+2*sizeof dword]
    jmp donejump
jumptop4:
    mov ebx, [dwPartitions+3*sizeof dword]
    jmp donejump
if ?GPT
jumptogpthdr:
    mov ebx, 1
    jmp donejump
jumptogpt:
    mov ebx, [startGPT]
    jmp donejump
endif

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
    @dprintfln "jumptocluster %lX", ebx
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
    cmp [lastSector], ebx
    jb invalsect
    mov [ioreq.sectno], ebx
    call readsect
    jc @F
    call resetmenustack   ; auto return to main menu
@@:
done:
    ret

;--- sector# > lastSector, shouldn't happen if all checks work as expected...

invalsect:
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset szInvalidSect, ebx, [lastSector]
    jmp nuprinterror

;-------------------------------------------------------
jumptosector:
    mov eax, [lastSector]
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset szSector2, eax    ; "sector (0-x): "
    call getdecvalue
    jc done
    mov ebx, ecx
    jmp donejump

;--- ctrl-end

jumptolastsect::
    mov ebx, [lastSector]
    jmp donejump

submenu_jumpto endp

;--- updateview() is called for every key press in main menu,
;--- so don't do lengthy things here!

updateview proc

    .const
vmvectors label word
    dw offset dataview
    dw offset mbrview
    dw offset bootsectview
    dw offset fat12view
    dw offset fat16view
    dw offset fat32view
    dw offset dirview
    dw offset fsinfoview
if ?GPT
    dw offset gpthdrview
    dw offset gptentryview
endif
MAXVVECS equ ($ - offset vmvectors) / sizeof word
    .code

    mov bUpdateView, 0
    mov [scrn_xy], VIEWROW * 100h + 1
    call bufferinsi
    movzx bx,[bViewmode]
    cmp bl, MAXVVECS
    jnc dataview
    shl bx, 1
    jmp [bx][vmvectors]
dataview:
    ret

updateview endp

if ?GPT

 if ?CRCGPT

;--- fill the lookup table needed for CRC32 calculation
;--- it's currently filled whenever the GPTHDR crc value
;--- is to be displayed, which is quite often, since its
;--- called by updateview().

FillLookupCRC proc stdcall uses di pTable:ptr

    push ds
    pop es
    mov di, pTable
    mov cx, 256
    xor ebx, ebx
nextitem:
    push cx
    mov cx, 8
    mov eax, ebx
nextbit:
    shr eax, 1
    jnc @F
    xor eax, 0EDB88320h
@@:
    loop nextbit
    stosd
    pop cx
    inc bx
    loop nextitem
    ret
FillLookupCRC endp

;--- calculate CRC32 over a memory region

CalcCRC proc stdcall uses si di ebx pBuffer:ptr, wLength:word, pLookup:ptr
    mov cx, wLength
    mov si, pBuffer
    movzx edi, pLookup
    mov ebx, -1
nextchar:
    movzx eax,byte ptr [si]
    xor eax, ebx
    movzx eax, al
    mov eax, [edi][eax*4]
    shr ebx, 8
    xor ebx, eax
    inc si
    loop nextchar
    xor ebx, -1
    mov eax, ebx
    ret
CalcCRC endp

 endif

;--- GPT header view (located at LBA 1 on GPT-partitioned disks)

gpthdrview proc

    .data

VIEWENT struct
wOfs dw ?
wLbl dw ?
wFmt dw ?
VIEWENT ends

gpthdrviewtab label word
    VIEWENT <GPTHDR.sig,       DStr('Signature'),              0808h>
    VIEWENT <GPTHDR.dwSizeHdr, DStr('Size GPT Header'),        0A04h>
    VIEWENT <GPTHDR.dwCRC,     DStr('CRC (disk)'),             0804h>
if ?CRCGPT
    VIEWENT <0,                DStr('CRC (calculated)'),       0>
endif
    VIEWENT <GPTHDR.qwCurLBA,  DStr('Current LBA'),            1408h>
    VIEWENT <GPTHDR.qwBckLBA,  DStr('Backup LBA'),             1408h>
    VIEWENT <GPTHDR.qwFirstLBA,DStr('First LBA'),              1408h>
    VIEWENT <GPTHDR.qwLastLBA, DStr('Last LBA'),               1408h>
    VIEWENT <GPTHDR.qwGPTLBA,  DStr('Start GPT'),              1408h>
    VIEWENT <GPTHDR.dwNumPE,   DStr('Entries GPT'),            0A04h>
    VIEWENT <GPTHDR.dwSizePE,  DStr('Size GPT Entry'),         0A04h>
    VIEWENT <GPTHDR.dwCRCPE,   DStr('CRC GPT Entries'),        0804h>
lgpthdrviewtab equ ($ - offset gpthdrviewtab) / sizeof VIEWENT

    .code

    mov di, offset gpthdrviewtab
    mov cx, lgpthdrviewtab
nextitem:
    push cx
    call basicbs
    add di, sizeof VIEWENT

    mov cl, 9
    call fillspace

    pop cx
    mov [scrn_xy.col], 40
    test ch, 1
    jz @F
    call printcrlf
@@:
    inc ch
    dec cl
    jnz nextitem
    ret
basicbs:
    mov dx, [di].VIEWENT.wLbl
    call printstring
    call printcolclear
    mov cx, [di].VIEWENT.wFmt
    jcxz @F
    mov word ptr [highlight.siz_], cx
    mov dx, [di].VIEWENT.wOfs
    xor bx, bx
    call printvalue_hl
    ret
@@:
if ?CRCGPT
    sub sp, 256*4
    invoke FillLookupCRC, sp
    xor ebx, ebx
    xchg ebx, [si].GPTHDR.dwCRC
    invoke CalcCRC, si, sizeof GPTHDR, sp
    add sp, 256*4
    mov [si].GPTHDR.dwCRC, ebx
    invoke sprintf, addr sprintfbuffer, CStr("%08lX"), eax
    mov cl, 8
    cmp eax, ebx

;--- the calculated value is displayed green/red.
;--- better would be to display the CURRENT value those colors.

    mov al, COL_GREENFG
    jz @F
    mov al, COL_REDFG
@@:
    call fillattr
    mov dx, offset sprintfbuffer
    call printstring
endif
    ret

gpthdrview endp

;--- GPT entry view (LBA 2-33)

gptentryview proc

    .data

gptentviewtab label word
    VIEWENT <GPTENTRY.guidType,  DStr('Type'),                   2610h>
    VIEWENT <GPTENTRY.qwFirstLBA,DStr('First LBA'),              1408h>
    VIEWENT <GPTENTRY.qwLastLBA, DStr('Last LBA'),               1408h>
    VIEWENT <0,                  DStr('Size'),                   0>
    VIEWENT <GPTENTRY.qwFlags,   DStr('Flags'),                  1008h>
lgptentviewtab equ ($ - offset gptentviewtab) / sizeof VIEWENT

    .code

    mov bx,[spot]
    and bl, 080h

    mov di, offset gptentviewtab
    mov cx, lgptentviewtab
nextitem:
    push cx
    call basicbs
    add di, sizeof VIEWENT

    mov cl, 9
    call fillspace

    pop cx
    cmp [scrn_xy.col], 40
    mov [scrn_xy.col], 40
    jb @F
    call printcrlf
@@:
    loop nextitem

    mov cx, length GPTENTRY.PartName
    add si, bx
    lea si, [si].GPTENTRY.PartName
    mov di, offset sprintfbuffer
    push ds
    pop es
@@:
    lodsw
    stosb
    and ax, ax
    loopnz @B
    jz @F
    mov al, 0
    stosb
@@:
    dec di
    sub di, offset sprintfbuffer
    jz @F
    mov cx, di
    mov dx, CStr("Name: ")
    call printstring
    mov al, COL_DEFAULT
    call fillattr
    mov dx, offset sprintfbuffer
    call printstring
@@:
cleareol:
    mov cl, MAXCOL
    sub cl, [scrn_xy.col]
    call fillspace
    ret
basicbs:
    mov dx, [di].VIEWENT.wLbl
    call printstring
    mov dx, CStr(": ")
    call printstring
    call cleareol
    mov cx, [di].VIEWENT.wFmt
    jcxz @F
    mov word ptr [highlight.siz_], cx
    mov dx, [di].VIEWENT.wOfs
    call printvalue_hl
    ret
@@:
    mov eax, dword ptr [si+bx].GPTENTRY.qwLastLBA+0
    mov edx, dword ptr [si+bx].GPTENTRY.qwLastLBA+4
    sub eax, dword ptr [si+bx].GPTENTRY.qwFirstLBA+0
    sbb edx, dword ptr [si+bx].GPTENTRY.qwFirstLBA+4
    add eax, 1
    adc edx, 0
    shrd eax, edx, 11
    shr edx, 11
    invoke sprintf, addr sprintfbuffer, CStr("%llu MB"), edx::eax
    mov cl, 24
    mov al, COL_DEFAULT
    call fillattr
    mov dx, offset sprintfbuffer
    call printstring
    ret

gptentryview endp

endif

;--- filesystem info view

fsinfoview proc

    call bufferinsi
    mov bx, 01E8h
    mov [highlight.siz_], 4
    mov di, offset fifields
    mov cx, numfifields
nextitem: 
    push cx
    mov dx, [di].VIEWDEF.wLbl
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
    call [di].VIEWDEF.wProc
dtsc:
    add bx, sizeof dword
    call printcrlf
    add di, sizeof VIEWDEF
    pop cx
    loop nextitem
    ret

fsinfoview endp

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

    push bx

;--- scan forward to find first entry

@@:
    mov cl, [si+bx].LFNENTRY.bIdx
    test cl, 080h               ; stop if a "deleted" entry occurs
    jnz foundfirst
    and cl, 3Fh                 ; the LFN entries are located BEFORE the file entry
    cmp cl, 1                   ; and the first byte is an index, starting with 1
    jz foundfirst
    cmp bx,  512 - sizeof LFNENTRY ; last entry in this sector?
    jz foundfirst               ; then stop. This is then not the first, name is truncated
    cmp [si+bx+sizeof LFNENTRY].LFNENTRY.bAttr, 0Fh
    jnz foundfirst              ; stop if next entry is "non-lfn"
    add bx, sizeof LFNENTRY
    jmp @B
foundfirst:

;--- now display the entries, descending, until last entry or sector begin is reached.
;--- check if the indices increment nicely, else mark the LFN as "invalid" in view.

    mov al, [si+bx].LFNENTRY.bIdx
    and al, 3Fh
    mov [bIdx], al
nextentry:
    call dispentry
    jc entriesdone
    mov al, [si+bx].LFNENTRY.bIdx
    and al, 0C0h
    cmp al, 40h      ; last entry?
    jz entriesdone
    cmp bx, 0        ; start of sector reached?
    jz entriesdone
    sub bx, sizeof LFNENTRY
    mov al, [si+bx].LFNENTRY.bIdx ; LFN entries must have an "descending" index
    inc [bIdx]
    and al, 3Fh
    cmp al, [bIdx]   ; is index incrementing?
    jz @F
    mov [bIdx], -1   ; mark LFN as invalid
@@:
    cmp [si+bx].LFNENTRY.bAttr, 0Fh
    jz nextentry
    mov [bIdx], -1
entriesdone:
    mov dl, '"'
    call printchar

;--- clear rest of view region

@@:
    cmp [scrn_xy.row], VIEWROW+5
    jz @F
    call printcrlf
    mov ax, COL_DEFAULT shl 8 or SPACE
    mov cl, 78
    call fillcell
    jmp @B
@@:
    pop bx           ; restore current entry

    mov dx, CStr('(deleted)')
    cmp byte ptr [si+bx], 0E5h
    jz wronglfn
    mov dx, offset sprintfbuffer
    cmp [bIdx], -2   ; wrong checksum?
    jz wronglfn
    cmp [bIdx], -1   ; chain correct?
    jnz done
    mov dx, CStr("(invalid)")
wronglfn:
    mov [scrn_xy], (VIEWROW+1) * 100h + 1
    call printstring
done:
    ret

    .const

lfntab label byte  ; LFN char position & size within dir entry
    db LFNENTRY.wName0, length LFNENTRY.wName0 ; pos  1, length 5
    db LFNENTRY.wName5, length LFNENTRY.wName5 ; pos 14, length 6
    db LFNENTRY.wNameB, length LFNENTRY.wNameB ; pos 28, length 2

    include oemchars.inc

    .code

;--- display ONE entry

dispentry:
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
    mov ah, MAXCOL-1
    sub ah, al
    mov [highlight.scsiz], al
    shl al, 1
    mov [highlight.siz_], al
    jz noprint
    sub ah, [scrn_xy.col]
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
if 1
;--- is checksum correct?
;--- the checksum byte calculation needs the SFN,
;--- so it's done here only if the SFN is in the same sector

    mov sprintfbuffer, 0
    movzx ax, [si+bx].LFNENTRY.bIdx
    and al, 3Fh
    shl ax, 5
    add ax, bx
    cmp ax, 512
    jnc nochksum
    mov di, ax
    add di, si
    mov cx, sizeof SFNENTRY.name_ ;11
    mov ah, 0
@@:
    mov al, [di]
    ror ah, 1
    add ah, al
    inc di
    loop @B
    movzx cx, [si+bx].LFNENTRY.bChkSum
    cmp ah, cl
    jz nochksum
    movzx ax, ah
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("(chksum incorrect, %X/%X)"), ax, cx
    mov [bIdx],-2
    stc
nochksum:
endif
    ret

;--- translate character

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
    mov [scrn_xy.col], 11
    mov dl, '"'
    call printchar
    popa
    ret

lfnview endp

;--- in: si=sector buffer
;---     bx=current dir entry

exfat_dirview proc

;--- (de)activate "Chain"

    mov ah, NO_CHAIN
    cmp [si+bx].EXFDIRP.etype, 0C0h          ; file stream entry?
    jnz @F
    mov ah, FILE_CHAIN
@@:
    call setchainmode

;    mov [scrn_xy], VIEWROW * 100h + 1
    mov cl, 78
    mov ax, COL_DEFAULT shl 8 or SPACE
    call fillcell
    inc [scrn_xy.row]
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

    mov di, 0

;--- scan downwards (remaining in sector) to get the name predecessors

    and bx, bx
    jz fncont_nextrow
@@:
    cmp [si+bx-DIRENTSIZE].EXFDIRS.etype, EXFSTCF_NAME
    jnz fncont_nextrow
    dec di
    sub bx, DIRENTSIZE
    jnz @B

fncont_nextrow:          ;<--- next row
    inc [scrn_xy.row]
    mov [scrn_xy.col], 1
    mov dl,'"'
    call printchar
fncont:                  ;<--- next name entry

    cmp di, 0            ; displaying current entry?
    jnz notfirst
    push bx              ; yes, then highlight
    lea bx, [bx].EXFDIRSN.name_
    mov [highlight.ofs], bx
    mov cl, 0
@@:
    mov ax, [si+bx]
    and ax, ax
    jz @F
    add bx, 2
    inc cl
    cmp cl, length EXFDIRSN.name_
    jnz @B
@@:
    pop bx
    mov [highlight.scsiz], cl
    shl cl, 1
    mov [highlight.siz_], cl
    call bshighlight
notfirst:
    mov cx, length EXFDIRSN.name_
    push si
    lea si, [si+bx].EXFDIRSN.name_
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
    inc di
    add bx, DIRENTSIZE
    cmp [scrn_xy.col], MAXCOL-15
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
    inc [scrn_xy.row]
    mov [scrn_xy.col], 1

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
    mov [scrn_xy.col],1
    inc [scrn_xy.row]
    mov dx, CStr("start cluster: ")
    call printstring
    mov [highlight.siz_], 4
    mov dx, EXFDIRP.dwFirstCl
    call printhex_hl
    mov dx, CStr(", size: ")
    call printstring
    mov word ptr [highlight.siz_], 1408h
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

    cmp [bFilesys], FS_EXFAT
    jz exfat_dirview

;--- de(activate) "chain" in "file options" menu.

    mov ah, NO_CHAIN
    cmp byte ptr [si+bx], 0      ; dir entry empty?
    jz @F
    cmp byte ptr [si+bx], 0E5h   ; v1.0: entry deleted? ( don't allow chain save/restore then )
    jz @F
;    cmp [si+bx].SFNENTRY.bAttr, 0Fh  ; LFN entry?
;    jz @F
    test [si+bx].SFNENTRY.bAttr, DA_VOLUME ; disk label or LFN entry?
    jnz @F
    mov ah, FILE_CHAIN
@@:
    call setchainmode

if ?EXT
;--- (de)activate "undelete" in "functions" menu depending on current entry status

    mov al, MS_INACTIVE
    cmp byte ptr [si+bx], 0E5h
    jnz @F
    cmp [si+bx].SFNENTRY.bAttr, 0Fh  ; LFN entry?
    jz @F
    mov al, MS_UnDelete
@@:
    mov cl, FUNCM_UNDELETE
    call setmenuitem
endif

;    mov [scrn_xy], VIEWROW * 100h + 1

;--- attribute value of 0Fh (R/O+hidden+system+volume) indicates a LFN entry

    call clearentryview

    cmp [si+bx].SFNENTRY.bAttr, 0Fh
    jz lfnview
    cmp byte ptr [si+bx],0
    jz done

    mov [scrn_xy.col], 5
    mov dx, CStr("Name: ")
    call printstring
    mov di, offset sprintfbuffer
    mov dx, di
    push ds
    pop es
    push si
    add si, bx
    mov cx, 11
    cmp [si].SFNENTRY.bAttr, 08  ; volume?
    je copyvol
    mov cl, 8
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
copyvol:
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
    mov [scrn_xy.col], 40+12
    mov dx, CStr("(deleted)")
    call printstring
@@:
    call printcrlf

    inc [scrn_xy.col]

;--- print created date+time

    mov dx, offset createdmsg
    call printstring

    mov dx, SFNENTRY.wCreDate ;DIR_CREATEDATE
    call printdate

;--- minute+second

    mov cx, SFNENTRY.wCreTime ;DIR_CREATETIME
    mov dx, SFNENTRY.bCreMSec ;DIR_CREATEMSEC
    call printtime

    mov dl, '.'
    call printchar

    mov [highlight], (101h shl 16) or SFNENTRY.bCreMSec ; DIR_CREATEMSEC
    add [highlight.ofs], bx
    call bshighlight

    movzx ax, [si+bx].SFNENTRY.bCreMSec
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

    mov [scrn_xy.col], 40

;--- print attributes

    mov dx, offset attributesmsg
    call printstring

    mov dx, SFNENTRY.bAttr ;DIR_ATTRIBUTES
    call printattr
    call printcrlf

;--- print last access date

    mov dx, offset accessedmsg    ; last accessed
    call printstring

    mov dx, SFNENTRY.wLADate ;DIR_LASTACCDATE
    call printdate

;--- print cluster

    mov [scrn_xy.col], 40+3
    mov dx, offset szCluster
    call printstring

;--- hiword cluster only displayed if it's != 0000 or filesys is FAT32/exFAT
    mov [highlight], (0302h shl 16) or SFNENTRY.wClHigh ;DIR_CLUST_HIGH
    add [highlight.ofs], bx
    mov ax, [si+bx].SFNENTRY.wClHigh
    and ax, ax
    jnz @F
    test [bFilesys], FS_FAT32
    jz nohighcl
@@:
    call bshighlight
    mov dl, 3
    call rendernumhex
    call printstring
nohighcl:
    mov [highlight.scsiz], 4
    add [highlight.ofs], SFNENTRY.wClLow - SFNENTRY.wClHigh ;(DIR_CLUST_LOW - DIR_CLUST_HIGH)
    call bshighlight

    mov dl, 4
    mov ax, [si+bx].SFNENTRY.wClLow
    call rendernumhex
    call printstring

    call printcrlf

;--- print last modified date

    mov dx, offset modifiedmsg    ; last modified
    call printstring

    mov dx, SFNENTRY.wLUDate ;DIR_LASTUPDDATE
    call printdate
    xor dx, dx
    mov cx, SFNENTRY.wLUTime ;DIR_LASTUPDTIME
    call printtime

;--- print size

    mov [scrn_xy.col], 40+3+3

    mov dx, offset sizemsg
    call printstring

    mov [highlight.siz_], 4
    mov dx, SFNENTRY.dwSize ;DIR_FILESIZE
    call printvalue_hl
done:
    ret

clearentryview:
    mov cx, 4 shl 8 or (MAXCOL-1)
;    mov ax, COL_DEFAULT shl 8 or SPACE
    mov ax, COL_STATTEXT shl 8 or SPACE
@@:
    call fillcell
    inc [scrn_xy.row]
    dec ch
    jnz @B
    sub [scrn_xy.row], 4
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

;--- set AH=chainmode and menu item "Chain"

setchainmode proc

    mov al, MS_INACTIVE
    cmp ah, NO_CHAIN
    jz @F
    mov al, MS_Chain
@@:
    mov [bChainmode], ah
    mov cl, LDFILEOPT_CHAIN
    call setmenuitem
    ret

setchainmode endp

;--- FAT32/EXFAT view - 7 rows and 9 clusters/row are shown.
;--- in total that fits in 15 lines: 0,36,72,108,144,180,216,252,288,324,360,396,432,468,504
;--- ( the last line has 2 items only )

CLUSTER_PER_ROW = 9
CLBYTES_PER_ROW = CLUSTER_PER_ROW * sizeof dword

fat32view proc

    mov ah, FAT_CHAIN
    call setchainmode

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
    mov [scrn_xy.col], 4
    inc [scrn_xy.row]
    dec ch
    jnz nextrow
    ret
done:
    mov cl, 7 * 7 + 6  ; 7 clusters, 7 digits/cluster, 6 spaces
    jmp fillspace

fat32view endp
  
;--- FAT16 view - 7 rows and 15 clusters/row are shown
;--- that fits in 18 rows: 0,30,60,90,120,150,180,210,240,270,300,330,360,390,420,450,480,510

CLUSTER_PER_ROW = 15
CLBYTES_PER_ROW = CLUSTER_PER_ROW * sizeof word

fat16view proc

    mov ah, FAT_CHAIN
    call setchainmode

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
    mov [scrn_xy.col], 3
    inc [scrn_xy.row]
    dec ch
    jnz nextrow
    ret
done:
    mov cl, 14 * 4 + 13   ; 14 clusters, 4 digits/cluster, 13 spaces (=69)
    jmp fillspace

fat16view endp

CLUSTER_PER_ROW = 18
CLBYTES_PER_ROW = 27 ; that's 18 * 1.5 (12 bits/entry)

;--- FAT12 view
;--- to be fixed: currently the view is filled with 7 full lines,
;--- although there might be less valid clusters.   

fat12view proc

    mov ah, FAT_CHAIN
    call setchainmode

    xor ebx, ebx
    call getentrynumberX
    mov di, ax

    mov [highlight], 03020000h

    xor ax, ax                          ; this little loop figures out
    mov bx, [spot]                      ; where to start displaying
buf12fix:                               ; fat12 entries, since an entire
    cmp bx, 4 * CLBYTES_PER_ROW         ; sect ofs (512 bytes) of 3-nibbles
    jb donebuffix                       ; won't fit in the view area.
    sub bx, CLBYTES_PER_ROW
    add ax, CLBYTES_PER_ROW
    add di, CLUSTER_PER_ROW
    add [highlight.ofs], CLBYTES_PER_ROW
    cmp ax, 300
    jbe buf12fix
donebuffix:

;    call bufferinsi
    mov si, offset sectbuffer           ; use sectbuffer directly here!

;--- fat12pad modifies bytes around [si]; this is no problem
;--- it's ensured that there's at least 1 byte free before sectbuffer
;--- and behind it there's also space, unless sector size is 4 kB -
;--- rather unlikely for FAT12

    push [currSector]
    call fat12pad

    add si, ax

    mov eax, [currSector]

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
    movzx ebx, [wSectOfs]        ;???
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
    cmp [scrn_xy.col], 75
    jne @F
    mov [scrn_xy.col], 3
    inc [scrn_xy.row]
@@:
    cmp [scrn_xy], (VIEWROW+7) * 100h + 3  ;check if we reached bottom of view area
    ret

fat12view endp

;-------------------------------------------------------

    .const

ptypes label byte
    db 0, 1, 4, 6, 0Eh, 0Bh, 0Ch, 05h, 0Fh
    db 16h, 1Bh, 1Ch, 1Eh, 8Dh, 90h, 91h, 92h, 97h, 98h, 9Ah, 9Bh
    db 07, 82h, 83h, 0A5h, 0EEh, 0EFh
NUMPTYPES equ $ - offset ptypes

pstrofs label byte
    db offset part00     - offset partstrgs
    db offset part01     - offset partstrgs
    db offset part04060E - offset partstrgs
    db offset part04060E - offset partstrgs
    db offset part04060E - offset partstrgs
    db offset part0B0C   - offset partstrgs
    db offset part0B0C   - offset partstrgs
    db offset part050F   - offset partstrgs
    db offset part050F   - offset partstrgs

    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs
    db offset parthid    - offset partstrgs

    db offset part07     - offset partstrgs
    db offset part82     - offset partstrgs
    db offset part83     - offset partstrgs
    db offset partA5     - offset partstrgs
    db offset partEE     - offset partstrgs
    db offset partEF     - offset partstrgs

    .code

printparttype proc uses di

    mov di, offset ptypes
    mov cx, NUMPTYPES
    push ds
    pop es
    repnz scasb
    jnz dontshowpart
    add di, NUMPTYPES-1
    mov dl, ' '
    call printchar
    movzx dx, byte ptr [di]
    add dx, offset partstrgs
    call printstring
dontshowpart:
    ret

printparttype endp

;--- physical disk MBR view
;--- si=sector buffer

mbrview proc

    .const

MBRVIEW struct
wFmt    dw ?
wProc   dw ?
bPos    db ?
MBRVIEW ends

mbrviewtab label MBRVIEW
    MBRVIEW <0100h, offset printpart,  1>
    MBRVIEW <0201h, offset printtype,  3>
    MBRVIEW <0201h, offset printbi,   20>
    MBRVIEW <0A04h, offset printschs, 25>
    MBRVIEW <0A04h, offset printechs, 37>
    MBRVIEW <0A04h, offset printslba, 49>
    MBRVIEW <0A04h, offset printsize, 60>
if 1
    MBRVIEW <0A04h, offset printMB,   71>
endif
endview label byte

    .code

    mov [scrn_xy.row], VIEWROW
if 1
    mov dx, CStr("P Type             Boot Start-CHS   End-CHS     Start-LBA  Size       MB")
else
    mov dx, CStr("P Type             Boot Start-CHS   End-CHS     Start-LBA  Size")
endif
    call printstring
    inc [scrn_xy.row]
    mov [scrn_xy.col], 1
    mov cl, MAXCOL-1
    mov al, '-'
    call fillchar

    xor cx, cx
    mov bx, PTABOFS

nextpart:
    push cx
    inc [scrn_xy.row]
    mov [scrn_xy.col], 3
    mov ax, COL_DEFAULT shl 8 or SPACE
    mov cl, 71-3
    call fillcell

    pop cx
    push cx

    mov di, offset mbrviewtab
@@:
    mov al, [di].MBRVIEW.bPos
    mov [scrn_xy.col], al
    mov ax, [di].MBRVIEW.wFmt
    mov word ptr [highlight.siz_], ax
    call [di].MBRVIEW.wProc
    add di, sizeof MBRVIEW
    cmp di, offset endview
    jnz @B
    mov cl, MAXCOL
    sub cl, [scrn_xy.col]
    call fillspace
    add bx, sizeof PTABENT
    pop cx
    inc cx
    cmp cx, 4
    jnz nextpart
    ret

;--- print partition#

printpart:
    mov dx, cx
    add dl, '1'
    call printchar
    ret

;--- print partition type (hex and name)

printtype:
    lea ax, [bx].PTABENT.bType
    mov [highlight.ofs], ax
    call bshighlight

    mov al, [si+bx].PTABENT.bType
    mov dl, 2
    call rendernumhex
    call printstring

    call printparttype
    retn

;--- print boot indicator

printbi:
    mov [highlight.ofs], bx
    call bshighlight

    mov al, [si+bx].PTABENT.bBoot
    mov dl, 2
    call rendernumhex
    call printstring
    retn

;--- print start CHS

printschs:
    push bx
    lea bx, [bx].PTABENT.sCHS
    call printchs
    pop bx
    retn

;--- print end CHS

printechs:
    push bx
    lea bx, [bx].PTABENT.eCHS
    call printchs
    pop bx
    retn

;--- print start LBA

printslba:
    mov dx, PTABENT.start
    call printvalue_hl
    retn

;--- print size LBA

printsize:
    mov dx, PTABENT.size_
    call printvalue_hl
    retn

;--- print size LBA in MB

if 1
printMB:
    mov eax, [si+bx].PTABENT.size_
    shr eax, 11         ; div 512 
    adc eax, 0          ; round
    call rendernumdec
    call printstring
    retn
endif

mbrview endp

;--- print CHS of a partition table entry in MBR
;--- SI=sector buffer
;--- BX=offset to CHS (start/end) in partition entry

printchs proc

    mov [highlight.ofs], bx

    movzx eax, [si+bx].CHSENT.bCH
    mov ah, [si+bx].CHSENT.bCL
    shr ah, 6
    inc [highlight.ofs]
    mov [highlight.siz_], 2
    call printeaxvalue_hl

    mov dl, '/'
    call printchar

    movzx eax, [si+bx].CHSENT.bDH
    dec [highlight.ofs]
    mov [highlight.siz_], 1
    call printeaxvalue_hl

    mov dl, '/'
    call printchar

    movzx eax, [si+bx].CHSENT.bCL
    and al, 3Fh
    inc [highlight.ofs]
    jmp printeaxvalue_hl

printchs endp

;--- boot sector view
;--- si=sector buffer

bootsectview proc

    .data

;--- FAT BPB struct

bsviewtab label word
    VIEWENT <BPB.bytes_sector,    DStr('Bytes per Sector'),    0502h>
    VIEWENT <BPB.sectors_cluster, DStr('Sectors per Cluster'), 0301h>
    VIEWENT <BPB.reserved_sectors,DStr('Reserved Sectors'),    0502h>
    VIEWENT <BPB.num_fats,        DStr('FATs'),                0301h>
    VIEWENT <BPB.root_entries,    DStr('Maximum Root Entries'),0502h>  ; FAT1x only
    VIEWENT <BPB.media_byte,      DStr('Media Descriptor'),    0301h>
bs_spf label word
    VIEWENT <0,                   DStr('Sectors per Fat'),        0h>
bs_st label VIEWENT
    VIEWENT <BPB.sectors_track,   DStr('Sectors per Track'),   0502h>
    VIEWENT <BPB.no_of_tracks,    DStr('Tracks'),              0502h>
    VIEWENT <BPB.hidden_sectors,  DStr('Partition Start'),     0A04h>
bs_psec label word
    VIEWENT <0,                   DStr('Sectors in Partition'),   0h>  ; sectors (FAT12 or FAT16/FAT32)
bs_hd label word
    VIEWENT <0,                   DStr('Hard Disk Number'),    0301h>
lbsviewtab equ ($ - offset bsviewtab) / sizeof VIEWENT
    VIEWENT <EBPB_FAT32.root_startcl,DStr('Root Start Cluster'),0A04h>   ; FAT32 only
    VIEWENT <EBPB_FAT32.fs_info_start,DStr('FSInfo Sector Number'),0502h>; FAT32 only
    VIEWENT <EBPB_FAT32.bs_copy_start,DStr('Backup B.S. Location'),0502h>; FAT32 only

    .code

;    mov [scrn_xy], VIEWROW * 100h + 1

    cmp [bFilesys], FS_NTFS
    jz bsntfsview
    cmp [bFilesys], FS_EXFAT     ; don't test flags here, no jump wanted for FAT12/16/32!
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

;--- check if it's FAT32. This will cause to print 3 FAT32 specific fields.
;--- since there's not enough space, fields sectors/track and tracks# are suppressed then.

    mov ch, 2
    mov cl, lbsviewtab
    mov bx, BPB.sec_per_fat1x
    mov dx, 0502h
    mov ax, EBPB.phys_drive
    cmp [si].BPB.sec_per_fat1x, 0
    jnz @F
    add cl, 3
    mov bx, EBPB_FAT32.sec_per_fat32
    mov dx, 0A04h
    mov ax, EBPB_FAT32.phys_drive
    mov ch, 0
@@:
    mov byte ptr [bs_st.wFmt], ch
    mov byte ptr [bs_st.wFmt+sizeof VIEWENT], ch
    mov word ptr [bs_spf+0], bx
    mov word ptr [bs_spf+4], dx
    mov word ptr [bs_hd+0], ax

    mov ch, 0
nextitem:
    cmp byte ptr [di].VIEWENT.wFmt, 0
    jz skipitem
    push cx
    call basicbs

    mov cl, 9
    call fillspace

    pop cx
    mov [scrn_xy.col], 40
    test ch, 1
    jz @F
    call printcrlf
@@:
    inc ch
skipitem:
    add di, sizeof VIEWENT
    dec cl
    jnz nextitem

    mov dx, CStr("Signature")
    call printstring
    call printcolclear
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
    mov bx, [di].VIEWENT.wOfs
    mov dx, [di].VIEWENT.wLbl
    mov cx, [di].VIEWENT.wFmt

    mov word ptr [highlight.siz_], cx
    call printstring
    call printcolclear
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

bootsectview endp

bsntfsview proc

    .data

;--- NTFS BPB struct

bsntfsviewtab label word
    VIEWENT <BPB.bytes_sector,    DStr('Bytes Per Sector'),    0502h>
    VIEWENT <BPB.sectors_cluster, DStr('Sectors Per Cluster'), 0301h>
    VIEWENT <BPB.reserved_sectors,DStr('Reserved Sectors'),    0502h>
    VIEWENT <BPB.media_byte,      DStr('Media Descriptor'),    0301h>
    VIEWENT <BPB.hidden_sectors,  DStr('Partition Start'),     0A04h>
    VIEWENT <28h,                 DStr('Sectors In Partition'),0A04h>
    VIEWENT <30h,                 DStr('$MFT Cluster'),        1408h>
    VIEWENT <38h,                 DStr('Backup $MFT Cluster'), 1408h>
lbsntfsviewtab equ ($ - offset bsntfsviewtab) / sizeof VIEWENT

    .code

    mov di, offset bsntfsviewtab
    mov cx,lbsntfsviewtab
nextitem:
    push cx
    call basicbs
    add di, sizeof VIEWENT

    mov cl, 9
    call fillspace

    pop cx
    mov [scrn_xy.col], 40
    test ch, 1
    jz @F
    call printcrlf
@@:
    inc ch
    dec cl
    jnz nextitem
    ret
basicbs:
    mov bx, [di].VIEWENT.wOfs
    mov dx, [di].VIEWENT.wLbl
    mov cx, [di].VIEWENT.wFmt

    mov word ptr [highlight.siz_], cx
    call printstring
    call printcolclear
    mov dx, bx
    xor bx, bx
    call printvalue_hl
    ret
bsntfsview endp

bsexfatview proc

    .data

bsexfatviewtab label word
    VIEWENT <EXFAT.dqHidden,  DStr('Start of Partition'),   1408h>
    VIEWENT <EXFAT.dqSize,    DStr('Sectors In Partition'), 1408h>
    VIEWENT <EXFAT.dwFatOfs,  DStr('Reserved Sectors'),     0A04h>
    VIEWENT <EXFAT.dwFatSiz,  DStr('Size of FAT'),          0A04h>
    VIEWENT <EXFAT.dwClHpOfs, DStr('Start Data Region'),    0A04h>
    VIEWENT <EXFAT.dwClCnt,   DStr('Clusters'),             0A04h>
    VIEWENT <EXFAT.dwRootCl,  DStr('Start Root Dir'),       0A04h>
    VIEWENT <EXFAT.wFSRev,    DStr('FS Revision'),          0502h>
    VIEWENT <EXFAT.wVolFlgs,  DStr('Volume Flags'),         0502h>
    VIEWENT <EXFAT.bBpSShift, DStr('BytesPerSector Shift'), 0301h>
    VIEWENT <EXFAT.bSpCShift, DStr('SecPerCluster Shift'),  0301h>
    VIEWENT <EXFAT.bNumFats,  DStr('No of FATs'),           0301h>
lbsexfatviewtab equ ($ - offset bsexfatviewtab) / sizeof VIEWENT

    .code

    mov di, offset bsexfatviewtab
    mov cx, lbsexfatviewtab
nextitem:
    push cx
    call basicbs
    add di, sizeof VIEWENT

    mov cl, 9
    call fillspace

    pop cx
    mov [scrn_xy.col], 40
    test ch, 1
    jz @F
    call printcrlf
@@:
    inc ch
    dec cl
    jnz nextitem
    ret
basicbs:
    mov bx, [di].VIEWENT.wOfs
    mov dx, [di].VIEWENT.wLbl
    mov cx, [di].VIEWENT.wFmt

    mov word ptr [highlight.siz_], cx
    call printstring
    call printcolclear
    mov dx, bx
    xor bx, bx
    call printvalue_hl
    ret
bsexfatview endp

;--- "emulate" a cr,lf sequence

printcrlf:
    mov [scrn_xy.col], 1
    inc [scrn_xy.row]
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
if ?GPT
    cmp word ptr highlight.siz_, 2610h  ; print a guid?
    jnz @F
    lea ax,[si+bx]
    mov dx, offset sprintfbuffer
    invoke guid2string, ax, dx
    pop bx
    jmp isstr
@@:
endif
    mov eax, [si+bx]
    cmp [highlight.siz_], 8
    jnz noqword
    mov edx, [si+bx+4]
    cmp highlight.scsiz, 8  ;output also 8 ( then it's a string )
    jnz isnum
    mov bx, offset sprintfbuffer
    mov dword ptr [bx+0], eax
    mov dword ptr [bx+4], edx
    mov byte ptr  [bx+8],0
    mov dx, bx
    pop bx
    jmp isstr
isnum:
    mov cx, 10
    cmp highlight.scsiz, 16
    jnz @F
    mov cx, 16
@@:
    invoke i64toa, edx::eax, offset sprintfbuffer, cx
    pop bx
    mov dx, ax
    mov ax, offset sprintfbuffer+22
    sub ax, dx
    mov [highlight.scsiz], al
isstr:
    call bshighlight
    jmp printstring
noqword:
    pop bx
    cmp [highlight.siz_], 4
    jae printeaxvalue_hl
    movzx eax, ax
    cmp [highlight.siz_], 2
    jae printeaxvalue_hl
    mov ah, 0
printeaxvalue_hl:
    cmp word ptr [highlight.siz_], 0804h
    jnz @F
    mov dl, 8
    call rendernumhex
    jmp dohighlight
@@:
    call rendernumdec
    push ax
    mov ax, offset valuebuffer+10  ;calculate string size
    sub ax, dx
    mov [highlight.scsiz], al
    pop ax
dohighlight:
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

    test [bFilesys], FS_FATXX
    jz notfat
    test [bRegion], RG_DATA
    jz done
    mov bx, ax
    mov eax, [currSector]
    call sector2cluster
    jc done
    cmp bh, ALTPGUP_KEY
    setnz cl
    sub cl, 1
    cmc
    movsx ecx, cl
    adc ecx, 0
    add eax, ecx
    jmp setcluster
done:
    ret

;--- v1.1: if not FAT and sector size > 512, go to next/prev sector

notfat:
	cmp [wBps], 512
	jbe done
	cmp ah, ALTPGUP_KEY
	jnz incr_sector
;--- decr_sector won't set pos to sector offset 0,
;--- so we have
	mov eax, [currSector]
	cmp eax, 0
	jnz @F
	mov eax, [lastSector]
	inc eax
@@:
	dec eax
	mov [ioreq.sectno], eax
	call readsect
	jc @F
	jmp checkcursorbounds
@@:
	ret

nextcluster endp
endif

;--- main menu pgup, pgdown, ctrl-pgup, ctrl-pgdown keys

nextsect1000:
    mov eax, [currSector]
    add eax, 100
    jmp donextsect

;--- main menu, pgdn key

nextsect:
    add [wSectOfs], VIEWBYTES
checkcursorbounds:
    mov dx, [wSectOfs]
    mov ax, [wBps]                        ; if (wSectOfs <= bps), then
    cmp ax, dx                            ; we've not paged down completely
    jbe incr_sector
    sub ax, dx
    dec ax
    cmp [spot], ax
    jbe @F
    call movecursor
@@:
    ret
incr_sector:
    mov eax, [currSector]
    inc eax
donextsect:
    cmp eax, [lastSector]
    jbe @F
    sub eax, [lastSector]
    dec eax
@@:
    mov [ioreq.sectno], eax
    call readsect
    jc @F
    mov [wSectOfs],0
@@:
    ret

;--- main menu, pgup key

prevsect:
    cmp [wSectOfs], 0
    jnz @F
decr_sector:
    mov eax, [currSector]
    dec eax
    jmp dolastsect
@@:
    sub [wSectOfs], VIEWBYTES
    jnc @F
    mov [wSectOfs], 0
@@:
    ret

;--- main menu, ctrl-pgup key

prevsect1000:
    mov eax, [currSector]
    sub eax, 100
dolastsect:
    cmp eax, [currSector]
    jb golastsect
    not eax

    mov ebx, [lastSector]
    sub ebx, eax
    mov eax, ebx
golastsect:
    mov [ioreq.sectno], eax
    call readsect
    jc @F
    mov dx, [wBps]
    sub dx, VIEWBYTES
    mov [wSectOfs], dx
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
    mov ax, 7302h                ; in WDeX, DOS calls are translated
    int 21h                      ; to "simulate real-mode interrupt"
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
    cmp [hVdd], -1
    jnz dontlock
endif

;--- lock logical valume. Required by Win9x only?
;--- should there be a corresponding unlock (86A/486A) when done with the drive???
;--- current status is: don't unlock (causes troubles in real DOS), under Win95 both locks fail.

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
;--- in: AX=size
;--- modifies CX

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
;---      [lastSector]
;---      [wCylinders], [bHeads], [bSectors]

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
    mov [lastSectorH], edx
endif
    mov [lastSector], eax
    mov ax, [si].DINFO1.bps
    call setBps
    jc secsizeerror 
    mov ax,word ptr [si].DINFO1.cyls
    mov bl,byte ptr [si].DINFO1.heads
    mov cl,byte ptr [si].DINFO1.secs
    mov [wCylinders], ax
    mov [bHeads], bl
    mov [bSectors], cl
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
    mov [bHeads], dh
    mov [bSectors], cl
    and [bSectors], 00111111b
    and cl,3
    xchg cl,ch
    mov [wCylinders], cx
    mov ax, 512
    call setBps
    movzx eax, [wCylinders]             ; CHS -> LBA
    movzx ebx, dh                       ; heads*cylinders
    mul ebx
    add eax, ebx                        ; + heads
    mov bl, [bSectors]
    mul ebx                             ; * sectors
    dec eax                             ; - 1
    mov [lastSector], eax
    mov [diskinfobuffer.flags], 2
    mov [ioreq.rwfunc], RWF_OLDINT13
done:
    ret

setphysvars endp

if ?GPT

;--- if partition type EE has been detected, read GPT header values

getGPTvars proc
    mov [ioreq.sectno], 1
    call diskaccess_read
    jc exit
    mov si, offset sectbuffer
    mov eax, dword ptr [si].GPTHDR.qwGPTLBA+0
    mov [startGPT.l], eax
if ?SN64
    mov eax, dword ptr [si].GPTHDR.qwGPTLBA+4
    mov [startGPT.h], eax
endif
    mov eax, dword ptr [si].GPTHDR.qwBckLBA+0
    mov [bckGPTHdr.l], eax
if ?SN64
    mov eax, dword ptr [si].GPTHDR.qwBckLBA+4
    mov [bckGPTHdr.h], eax
endif

    mov eax, [si].GPTHDR.dwNumPE
    mul [si].GPTHDR.dwSizePE
    mov [dwGPTSize], eax
    call readcursect
exit:
    ret
getGPTvars endp

endif

;--- disk change. obtain all info
;--- IN:   [ioreq.drvtype], [ioreq.bDrive] & [ioreq.rwfunc]
;--- sector 0 read in sectbuffer
;--- for logical devices: disk type may be FAT, NTFS, EXFAT

setvariables proc
    call setseeds2

    mov [bFilesys], FS_UNDEFINED        ; reset FAT type

    cmp [ioreq.drvtype], DT_CDROM
    je cdsetvars
    cmp [ioreq.drvtype], DT_FILE        ; file access?
    je filesetvars
    cmp [ioreq.drvtype], DT_PHYSICAL
    jne logicalsetvars
copypartitioninfo:
if ?GPT
    cmp [sectbuffer+PTABOFS].PTABENT.bType, 0EEh; "EFI" partition?
    setz bTypeEE
    jnz @F
    call getGPTvars
@@:
endif
    push ds                             ; sets variables p1-p4
    pop es                              ; for jumping to partitions
    mov di, offset dwPartitions         ; on physical drives
    mov si, offset sectbuffer + PTABOFS + PTABENT.start
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
    mov [lastSector], eax
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
    cmp word ptr [si+11], 0               ; bytes per sector must be 0 for exFAT
    jnz assumefat
    cmp eax, "AFXE"
    jnz assumefat
    mov eax, [si+7]
    cmp eax, "   T"
    jz isexfat
assumefat:

    cmp [ioreq.rwfunc], RWF_FILE          ; image file?
    jnz @F
    mov ax, [si].BPB.bytes_sector         ; then use sector size from boot sector ( if it's a real
    call setBps                           ; physical/logical drive, we already got it )
    jc secsizeerror
@@:
    movzx ax, [si].BPB.sectors_cluster    ; sectors per cluster
    mov [wSpC], ax

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
    mov [wRootentries], ax
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
if 0 ; v1.1 code replaced
    cmp [ioreq.rwfunc], RWF_FILE              ; don't set lastSector if image file
    jz @F
    mov [lastSector], eax
@@:
else
    cmp [ioreq.rwfunc], RWF_FILE
    jnz @F
    cmp eax, [lastSector]                     ; image file size large enough to cover last sector?
    ja  nolsset                               ; if no, don't adjust lastSector
@@:
    mov [lastSector], eax
nolsset:
endif

;--- calculate size of data region ( lastsector - ( reserved + fatsectors + rootsectors[fat12/16] )

    push eax
    mov eax, [dwSpF]
    movzx ecx, [bFats]
    mul ecx
    mov ebx, eax    ; ebx=size of fats
    pop eax
    movzx ecx, [wRootsectors]
    sub eax, [dwReserved]
    sub eax, ebx
    sub eax, ecx


    mov cl, [bSpCshift]
    shr eax, cl     ; eax=clusters

;--- check boot signature of EBPB. if 28h/29h, it's no FAT32

    mov ch, [si].EBPB.ext_boot_sig
    and ch, 0FEh
    cmp ch, 28h
    jz nofat32

;--- set FAT file system depending on cluster#

    mov ch, FS_FAT32
    cmp eax, 65525
    jae @F
nofat32:
    mov ch, FS_FAT16
    cmp eax, 4085
    jae @F
    mov ch, FS_FAT12
@@:
    add eax, 2
    mov [dwLastCluster], eax
    mov [bFilesys], ch

;--- set start of root ( reserved + size fats )

    mov eax, ebx
    add eax, [dwReserved]
    mov [dwRootSect], eax

    cmp ch, FS_FAT32
    jne not_fat32

    push eax
    mov al, [si].EBPB_FAT32.phys_drive    ; hard drive number
    mov [hdnumber], al
    mov ax, [si].EBPB_FAT32.bs_copy_start ; backup boot sector
    mov [backupbs], ax
    mov ax, [si].EBPB_FAT32.fs_info_start ; filesystem info sector
    mov [fsinfo], ax
    mov ax, [wSpC]
    mov [wRootsectors], ax                ; wRootsectors isn't reliable for FAT32
    mov eax, [si].EBPB_FAT32.root_startcl
    mov [dwRootCluster], eax

    sub eax, 2                          ; root start cluster valid?
    jc @F
    mov cl, [bSpCshift]
    shl eax, cl
    add [dwRootSect], eax
@@:
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
    mov bx, [wSpC]
    add eax, ebx
datastartiscorrect:
    mov [dwDataStart], eax

    mov eax, [dwReserved]
    add eax, [dwSpF]
    mov [dwFat1end], eax                ; calculate end of fat 1 area

    movzx eax, [wBps]                   ; calculate bytes per cluster
    mov bx, [wSpC]
    mul ebx
    mov [dwBpC], eax
donegetvars:
    ret

isntfs:
    mov [bFilesys], FS_NTFS
    mov eax, [si+28h]
    dec eax
    mov [lastSector], eax
    movzx ax, [si].BPB.sectors_cluster
    mov [wSpC], ax
    mov ecx, [si][30h]   ; it's actually a qword
    movzx eax,al
    mul ecx
    mov [dwRootSect], eax
    mov [dwReserved], eax
    ret

isexfat:
    mov [bFilesys], FS_EXFAT
    mov eax, dword ptr [si].EXFAT.dqSize+0
ife ?SN64
    dec eax
    cmp dword ptr [si].EXFAT.dqSize+4, 0
    jz @F
    or eax, -1
@@:
else
    mov edx, dword ptr [si].EXFAT.dqSize+4
    sub eax, 1
    sbb edx, 0
    mov [lastSector.h], edx
endif
    mov [lastSector.l], eax
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

    mov ax, 1
    mov cl, [si].EXFAT.bSpCShift 
    mov [bSpCshift], cl
    shl ax, cl
    mov [wSpC], ax
    movzx edx, [wBps]
    movzx eax, ax
    push eax
    mul edx
    mov [dwBpC], eax
    pop eax
    mov edx, [dwRootCluster]
    sub edx, 2
    mul edx
    add eax, [dwDataStart]
    mov [dwRootSect], eax
    mov ax, [wSpC]
    mov [wRootsectors], ax        ; [wRootsectors] just one cluster!
    ret
secsizeerror:
    mov dx, offset secsizetoobig
    call printerror
    ret

filesetvars:
    @dprintfln "setvariables, DT_FILE"
    mov eax, [dwRwfilesize]
    shr eax, 9                    ; bytes/sector is 512 as long as image file is "physical"
    jz @F
    dec eax
@@:
    sub eax, dword ptr [qwDiskStart+0]
    mov [lastSector], eax
if 1
;--- image files are "physical" as default ( they won't show MBR automatically! )
;--- Use "GoTo" and "Restrict" to select a logical disk
    mov [ioreq.drvtype], DT_PHYSICAL
    mov [diskinfobuffer.flags], 0
    jmp copypartitioninfo
else
    ret
endif

setvariables endp

;-------------------------------------------------------

;*******************************************************
; CALLS
;*******************************************************
include FATFS.INC
;-------------------------------------------------------

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

;--- scan read buffer if it contains directory entries (FAT type)
;--- IN: SI=sector buffer
;--- OUT: not found: carry set
;---      found    : carry cleared
;--- must preserve DX, CX

IsDirectory proc

    cmp [bFilesys], FS_EXFAT
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

;    cmp [si+bx].SFNENTRY.bRes, 0       ; NT series *does* use this byte,
;    jne notfound                       ; so it may not be 0 on drives that
;                                       ; have been messed with by NT
    mov cl, 10

    cmp [si+bx].SFNENTRY.name_, 0       ; first byte zero?
    je allzero

    test [si+bx].SFNENTRY.bAttr, 11000000b
    jnz notfound                        ; top two bits of attribute are
                                        ; reserved.  can't be used.
    cmp [si+bx].SFNENTRY.bAttr, 0Fh
    je lfn                              ; if attribute is 0F, then it's lfn

notlfn:
    inc cl
    cmp [si+bx].SFNENTRY.bCreMSec, 199  ; tenth of a second for
    ja notfound                         ; creation time (0-199)
    
    mov ax, [si+bx].SFNENTRY.wLUDate    ; test "last update" date
                                        ; to see if it exceeds any
                                        ; hour/minute/etc boundaries
    test al, 00011111b
    jz notfound
    shr ax, 5
    and al, 00001111b
    jz notfound
    cmp al, 12
    ja notfound

    mov ax, [si+bx].SFNENTRY.wCreDate   ; test "creation" date
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

    mov ax, [si+bx].SFNENTRY.wClHigh
    shl eax, 16
    mov ax, [si+bx].SFNENTRY.wClLow

    cmp eax, 0FFFFFF7h                          ; cluster can't be EOC and
    jae notfound                                ; the top nibble must = 0
    cmp dword ptr [si+bx].SFNENTRY.wLUTime, 0   ; check both time/date (pointless?)
    je notfound

    test [si+bx].SFNENTRY.bAttr, DA_DIRECTORY   ; directory?
    jz entrynotdirectory
    test [si+bx].SFNENTRY.bAttr, DA_VOLUME      ; can't also be a label.
    jnz notfound
    cmp [si+bx].SFNENTRY.dwSize, 0              ; "size" of directories "should" be 0
    jne notfound
entrynotdirectory:

    cmp [si+bx].SFNENTRY.name_, 20h             ; first character cannot be a space
    je notfound
    cmp [si+bx].SFNENTRY.name_, 0E5h            ; first character can be E5h (del'd)
    je charok
nextchar:
    mov al, [si+bx].SFNENTRY.name_
    call extvalidfilechar
    jc notfound
charok:
    inc bx
    dec cl
    jnz nextchar
    jmp donextentry

lfn:

    cmp [si+bx].SFNENTRY.wClLow, 0              ; low cluster word must = 0
    jne notfound                                ; for long file names

    mov al, byte ptr [si+bx]

;    cmp al, 0ffh                               ; wtf?
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
;    mov [wSectOfs], al

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

;--- bootsector view:
;--- print ':' then clear the rest to pos 23/63

printcolclear proc
    mov dl, ':'
    call printchar
    mov cl, COLBSV1
    sub cl, [scrn_xy.col]
    jnc @F
    mov cl, COLBSV2
    sub cl, [scrn_xy.col]
@@:
    call fillspace
    add [scrn_xy.col], cl
    ret
printcolclear endp

;--- read file to restore sectors/cluster/FAT/root/... (but not "restore chain")
;--- IN: eax = start sector
;---    [dwValue] = # of sectors to write to disk
;---    [dwFilesize] = size of file to read
;--- OUT: sectors written to disk from file

readfile proc
;    mov dx, offset restoremsg
;    call printbottom

;--- check if sector limits are ok
    mov edx, eax
    add edx, [dwValue]
    jc invalidperror
    dec edx
    cmp edx, [lastSector]
    ja invalidperror

;--- check filesize: must be large enough to cover the sectors;
;--- the last sector may be covered partially only.
    push eax
    mov eax, [dwValue]
    movzx ecx, [wBps]
    mul ecx
    mov edx, eax
    pop eax
    sub edx, [dwFilesize]         ; ok if file size >= sector*bps
    jbe @F
    cmp edx, ecx                  ; last sector covered partially?
    mov dx, offset filetoosmall
    jnb nuprinterror
@@:
    mov [handling], QUERY_SKIP           ; inside readfile

;    push [currSector]

    mov [ioreq.sectno], eax
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
    mov dx, offset filereaderr
error:
    call printerror
    stc
    jmp donefileread

noreaderror:

	cmp ax, cx
	jz @F
	pusha
	mov cx, ax
	call allocmem
	mov di, ax
	push ds
	pop es
	mov si, dx
	push cx
	rep movsb
	push ax
	call diskaccess_read
	pop ax
	pop cx
	mov si, ax
	mov di, dx
	rep movsb
	call freemem
	popa
@@:
    call diskaccess_write
    jc donefileread

    inc [ioreq.sectno]

    call checktime
    jc continue_loop
    call checkabort
    jne @F
    mov dx, offset abortwdmsg             ; "abort writing to disk"
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
;    pop [ioreq.sectno]
    pushf
    call closefile
    mov [handling], ABORT_OPERATION       ; inside readfile
    call readcursect
    popf
    jc @F
    call resetmenustack                   ; if file op was successful, go back to main menu
    call updatescreen                     ; let the user see the new content
    mov dx, offset donewritedisk
    call nuprinterror
@@:
    ret
readfile endp

;--- prints the fat entry the cursor is currently in,
;--- in the top right of the screen

printentry proc
    cmp [bRegion], RG_FAT
    jne done

    call getentrynumber
    mov cl, COLENDHEX
    mov dl, 8
    test eax, 0ffff0000h
    jnz @F
    test [bFilesys], FS_FAT32
    jnz @F
    mov dl, 4
@@:
    sub cl, dl
    mov [scrn_xy.col], cl
    mov cl, dl

    call rendernumhex

    mov al, COL_DEFAULT
    call fillattr

    call printstring
done:
    ret
printentry endp

;--- get a key from keyboard; use 10h instead of 00 to get ctrl-up, ctrl-dn, ... codes

getkey:
    mov ah, 10h
    int 16h
    ret

;--- transform spot in dx to value for [scrn_xy] ( ascii output )

spot2xyasc:
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
    call darkclr
    push bp
    sub sp, 80-8
    mov si, sp
    mov byte ptr [si],0
    xor cx, cx
    mov al, MAXCOL
    sub al, [scrn_xy.col]
    mov ah, 0
    mov bp, ax
tryagain:
    invoke getstring, si, 80-8, cx, bp, offset @ret
    mov di, dx                 ; returns ax=chars, dx=cursor ofs
    mov cx, ax
    stc
    jcxz abort
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
    clc
abort:
    lea sp, [esp+80-8]
    pop bp
    ret
invalkey:
    dec si
@@:               ; skip trailing blanks
    lodsb
    cmp al, ' '
    loopz @B
    jz donevalue
invalvalue:
    mov cx, di
    mov si, sp
    mov bh, [vidpg]
    mov ax, 0E07h ; "display" bell
    int 10h
    jmp tryagain

getdecvalue endp

;--- display some values on line 0 (sector#, cluster#, ... )

printtopline proc
    pushad
    mov [bRegion], RG_UNDEFINED

    mov [scrn_xy], COLSECTOR
    mov cl, 10
    mov al, COL_DEFAULT
    call fillattr

    mov eax, [currSector]
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("%lu"), eax
    call printstring

    mov cl, COLREGION
    sub cl, [scrn_xy.col]
    call fillspace
    add [scrn_xy.col], cl
    mov cl, sizeof szReservedmsg - 1 ;"[boot/reserved]", "[fat-x]", "[root", "[data]"
    mov al, COL_DEFAULT
    call fillattr

    mov eax, [currSector]

    cmp [ioreq.drvtype], DT_PHYSICAL
    je inphysical
    cmp [ioreq.drvtype], DT_CDROM
    je indata

    mov edx, [dwReserved]          ; [dwReserved] is initialized in FS_NTFS and FS_EXFAT
    cmp eax, edx
    jb inreserved

    test [bFilesys], FS_FATXX
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

    mov dx, offset szRootmsg           ; "[root]
    test [bFilesys], FS_FAT32          ; root in data region?
    jnz dispclust

continuecount:
    call printstring                   ; print [boot/reserved] or cluster# 
abortdc:
    mov cl, MAXCOL                     ; clear to last column
    sub cl, [scrn_xy.col]
    call fillspace
    cmp [ioreq.drvtype], DT_PHYSICAL
    jne done
    test [diskinfobuffer.flags], 2     ; CHS valid?
    jz done
    mov [scrn_xy], (0 shl 8) or COLCHS
    mov dx, CStr("CHS: ")
    call printstring
    mov cl, 11
    mov al, COL_DEFAULT
    call fillattr
    mov eax, [currSector]
    call getchsx
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, CStr("%u/%u/%u"), ax, bx, cx
    call printstring
done:
    popad
    ret

inreserved:
    mov [bRegion], RG_RESERVED
    mov dx, offset szReservedmsg
    jmp continuecount

infat:
    mov [bRegion], RG_FAT
    mov cx, 1
    mov eax, [dwFat1end]
    cmp [currSector], eax
    jb @F
    inc cx
@@:
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, offset szFATmsg, cx  ; "[FAT-x]"
    call printstring

    test [bFilesys], FS_FATXX
    je abortdc
    mov cl, COLENDHEX - 15
    test [bFilesys], FS_FAT32
    jnz @F
    mov cl, COLENDHEX - 11
@@:
    mov dl, cl
    sub cl, [scrn_xy.col]
    call fillspace
    mov [scrn_xy.col], dl
    mov cl, sizeof entrymsg - 1
    mov al, COL_STATTEXT
    call fillattr
    mov dx, offset entrymsg           ; "Entry: "
    call printstring
    call printentry
    mov [scrn_xy.col], COLENDHEX      ; column where hex region ends
    jmp abortdc

setphysview:
    mov [bRegion], cl                 ; bits 0-3 of bRegion may contain "view"
    call printstring
    jmp abortdc

inphysical:
    cmp [ioreq.bDrive], 80h           ; lower than 80h?
    jb indata                         ; not an hd - no mbr.
    mov dx, offset szMBRmsg
    mov cl, VM_MBR
    test eax, eax
    jz setphysview
if ?GPT
    cmp [bTypeEE], 0
    jz indata
    mov dx, offset szGPTHdrmsg
    mov cl, VM_GPTHDR
    cmp eax, 1
    jz setphysview
    cmp eax, [bckGPTHdr]
    jz setphysview

    cmp eax, [startGPT]
    jb indata
    mov ebx, [dwGPTSize]
    shr ebx, 9                        ; fix: sectorsize=512
    push ebx
    add ebx, [startGPT]
    mov dx, offset szGPTEntrymsg
    mov cl, VM_GPTENTRY
    cmp eax, ebx
    pop ebx
    jb setphysview
    mov esi, [bckGPTHdr]
    sub esi, ebx
    cmp eax, esi
    jae setphysview
endif

indata:
    mov dx, offset szDatamsg
dispclust:
    call printstring
;    mov dl, SPACE
;    call printchar

    test [bFilesys], FS_FATXX
    je abortdc

    or [bRegion], RG_DATA

    mov eax, [currSector]
    call sector2cluster
    mov dl, 7                         ; cluster has max. 7 hex digits (8 for exfat!)
    test eax, 0ffff0000h
    jnz @F
    test [bFilesys], FS_FAT32
    jnz @F
    mov dl, 4
@@:
    push dx
    call rendernumhex
    mov ebx, eax
    mov ax, dx
    pop dx
    mov ch, dl
    add dl, sizeof szCluster - 1
    neg dl
    add dl, COLENDHEX
    mov cl, dl
    sub cl, [scrn_xy.col]
    push ax
    mov al, SPACE
    call fillchar
    mov [scrn_xy.col], dl

    mov cl, sizeof szCluster - 1
    mov al, COL_STATTEXT
    call fillattr
    mov dx, offset szCluster
    call printstring
if 1
    mov eax, ebx
    mov [fromfat], FF_FAT1
    call getfatentry
    and eax, eax       ; cluster "in use"?
    mov al, COL_DEFAULT
    jz @F
    mov al, COL_GREENFG; then display number in green text
@@:
    mov cl, ch
    call fillattr
endif
    pop dx            ; get rendered cluster#
    jmp continuecount ; and display it

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
    add [scrn_xy.col], al
    popa
    ret
printstring endp

;--- this routine prints out 512/128
;--- bytes in the read buffer at current sector offset

printsector proc
    call bufferinsi

    mov dx, [wBps]
    sub dx, [wSectOfs]
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
    call cbuffer_offset
nextchar1:
    lodsb
    cmp cx, [rembytes]
    jb @F
    mov al, SPACE
@@:
    stosb
    inc di
    inc cx
    test cl, 0Fh
    jnz @F
    inc [scrn_xy.row]
    mov [scrn_xy.col], COLASC
    call cbuffer_offset
@@:
    cmp cx, VIEWBYTES
    jnz nextchar1
    pop si

    cmp [bDisplaymode], DM_BINARY
    je displaybinval

    xor cx, cx
    mov [scrn_xy], COLHEX or ( ROWXXX shl 8 )
    call cbuffer_offset
nextchar2:
    lodsb
    cmp cx, [rembytes]
    jb @F
    mov al, '-'
    stosb
    inc di
    stosb
    inc di
    jmp donechar1
@@:
    ror al, 4
    call nibout
    ror al, 4
    call nibout
donechar1:
    inc cx
    add di, 2
    test cl, 03h
    jnz @F
    add di, 2
@@:
    test cl, 0Fh
    jnz @F
    inc [scrn_xy.row]
    mov [scrn_xy.col], COLHEX
    call cbuffer_offset
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
    stosb
    inc di
    mov al, ah
    ret

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
    call spot2xy
    mov [scrn_xy], dx

    cmp cx, [rembytes]
    jb @F
    mov al, '-'
    push cx
    mov cl, 4
    call fillchar
    add [scrn_xy.col], 5
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

;--- display the 32 offsets at position 1 (4 digits)

printaddresses:
    mov [scrn_xy], 0 shl 8 or COLOFFST
    mov al, COL_STATTEXT
    mov cl, sizeof offsetmsg - 1
    call fillattr
    mov dx, offset offsetmsg
    call printstring                    ; 'Offset:'

    mov [scrn_xy.col], COLSECTORT
    mov al, COL_STATTEXT
    mov cl, sizeof szSector - 1
    call fillattr
    mov dx, offset szSector
    call printstring                    ; 'Sector:'

    movzx eax, [wSectOfs]
    mov bx, 10h                         ; 16 bytes per line in hex mode
    mov cx, 32                          ; 32 vertical lines for editing
    cmp [bDisplaymode], DM_BINARY
    jne nextaddress

    mov dx, [spot]
    and dl, 10000000b
    add ax, dx
    mov bx, 4                           ; 4 bytes per line in binary mode

nextaddress:
    call printcrlf
    mov dl, 4                           ; render 4 digits
    call rendernumhex
    call printstring
    add ax, bx
    loop nextaddress
    ret
printsector endp

;--- print value of current offset (=spot) in row 0.
;--- in FAT view, print the entry#

printoffset proc

    mov [scrn_xy], COLOFFS
    mov cl, 3
    mov al, COL_DEFAULT
    call fillattr
    call spot2bufofs                    ; bx = wSectOfs + spot
    mov ax, bx
    mov dl,3
    call rendernumhex
    call printstring

    call printentry                     ; in FAT view, print current entry# (=cluster)
    ret

printoffset endp

;--- showcursor: (re)set color of 2 cursors
;--- set the 2 cursors hex/ascii part
;--- current screen pos is at hex/binary cursor
;    mov ax, COL_DEFAULT or (COL_DEFAULT shl 8)    ; ah & al = COL_DEFAULT

showcursor proc

    pusha
    mov bp, sp
;    @dprintfln "showcursor(%u)", word ptr [bp+16+2]
    mov ax, COL_EDIT or (COL_HIGHLIGHT shl 8)
    cmp [bEditmode], EM_DEFAULT
    jz @F
    xchg al, ah
@@:
    cmp byte ptr [bp+16+2], 1
    jz @F
    mov ax, [oldcsrattr]
@@:
    push [scrn_xy]

    mov dx, [spot]
    call spot2xy
    add dl, [bHL]
    mov [scrn_xy], dx
    call cbuffer_offset
    mov cl, es:[di+1]
    mov es:[di+1], al
    mov dx, [spot]
    call spot2xyasc          ;calculate screen pos for ascii
    mov [scrn_xy], dx
    call cbuffer_offset
    mov ch, es:[di+1]
    mov es:[di+1], ah

    pop [scrn_xy]

    cmp byte ptr [bp+16+2], 1
    jnz @F
    mov [oldcsrattr], cx
@@:
    popa
    ret 2

showcursor endp

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

;--- set attr in AL CL times
;--- (no screen pos update!)

fillattr:
    push di
    push cx
    call cbuffer_offset
@@:
    inc di
    stosb
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
    inc [scrn_xy.col]
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

vinit proc

;--- check if video mode suits, else set 43x80 mode.
    push ds
    push _0000H
    pop ds
    mov ax, ds:[44Ah] ;cols
    add ax, ax
    mov bx, ds:[44Eh] ;start offset video page
    mov di, 0B800h
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
    int 10h                               ; returns BH=00 if color mode
    or cx, cx
    jz noegavga
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
    mov ax, 80*2
    mov ch, 43
    xor bx, bx
    mov dl, 0
vmode_ok:
    mov [vidcolsize], ax
    mov [vidrows], ch
    mov [vidpg], dl
    mov word ptr [vidaddr+0], bx
if ?PM
    mov cx, di
    mov dx, di
    shl dx, 4
    shr cx, 12
    mov bx, word ptr [vidaddr+2]
    mov ax, 7
    int 31h
else
    mov word ptr [vidaddr+2], di
endif
    les di, [vidaddr]
    mov ax, COL_STATTEXT shl 8 or SPACE
    mov cx,MAXCOL+1
    rep stosw

    call clearscreen

    mov cx, 2000h                         ; hide cursor
    mov ah, 01h                           ; set text mode cursor shape
    int 10h

    mov [scrn_xy], 1423h                  ; print version
    mov dx, offset introtext
    call printstring
    mov [scrn_xy], 1612h                  ; print copyright
    mov dx, offset copyright
    call printstring
    ret
noegavga:                                 ; v1.0: exit if no acceptable video adapter
if ?PM
    call exitwdepm
endif
    mov dx, offset viderror
    mov ah, 9
    int 21h
    mov ax, 4C01h
    int 21h
vinit endp

clearscreen proc

    mov [scrn_xy], 0
    mov cl, MAXCOL+1
    call fillspace

    les di, [vidaddr]
    add di, [vidcolsize]
    mov dl, 43-1
    mov ax, COL_DEFAULT shl 8 or SPACE
@@:
    push di
    mov cx,MAXCOL+1
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
    db "usage: wde [ options ] [{disk | path}]",13,10
    db "   disk:",13,10
    db "     logical drive - a letter followed by a colon ( C:|D:|... )",13,10
    db "     hard disk     - a digit ( 0|1|... )",13,10
    db "     floppy disk   - a digit followed by a 'f' ( 0f|1f|... )",13,10
    db "   path:",13,10
    db "     name of an image file or a directory",13,10
    db "   options:",13,10
    db "     -?: display this help text and exit",13,10
if ?SAFEMODE
    db "     -s: safe mode; no write access to disk/image",13,10
endif
if ?MOUNT
    db "     -m[n]: mount disk or partition (n={1|2|3|4}) as logical drive",13,10
endif
    db "     -n<size>: set sector size (must be a power of 2)",13,10
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
;--- to prepare for int 13h, ah=02/03.
;--- modifies ecx, ebx, edx, eax

getchs proc
    movzx ecx, [bHeads]
    movzx ebx, [bSectors]
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
    movzx ebx, [bSectors]
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

;--- translate sector# in eax to CHS in ax,bx,cx.
;--- to display CHS in topline.

getchsx proc
    movzx cx, [bHeads]
    movzx bx, [bSectors]
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
    movzx cx, [bSectors]
    div cx
    mov bx, ax      ; gives heads in bx
    mov cx, dx
    inc cx
    pop ax
@@:
    ret
getchsx endp


;--- generic write access.
;--- [currSector] is not modified.
writecursect:
    push [currSector]
    pop [ioreq.sectno]
diskaccess_write:
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

;--- generic read access. updates [currSector] if read was successful

readsect:
    call diskaccess_read
    jc @F
    push [ioreq.sectno]
    pop [currSector]
    mov [bUpdateScreen], 1
@@:
    ret

;--- readcursect "rereads" current sector

readcursect:
    push [currSector]
    pop [ioreq.sectno]
diskaccess_read:
    mov [ioreq.pBuffer], offset sectbuffer
    mov [ioreq.bRW], RW_READ

; diskaccess handles all sector reading and writing in WDe for all disk types
;       IN:     [ioreq.bRW]      = 0=read, 1=write
;               [ioreq.sectno]   = the sector number to read
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
    mov eax, [ioreq.sectno.l]
    add eax, dword ptr [qwDiskStart+0]
if ?SN64
    mov edi, [ioreq.sectno.h]
    adc edi, dword ptr [qwDiskStart+4]
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
    cmp [ioreq.rwfunc], RWF_NEWLOGICAL
    je newlog_access

;--- access drive via int 25h/26h
;--- DS:BX -> disk read/write packet ( if CX == -1 )

;oldlog_access:
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
    cmp [ioreq.bRW], RW_WRITE
    setz al
    movzx si, al                      ; si, bit 0: 0=read, 1=write
    mov dl, [ioreq.bDrive]
    inc dl
    mov ax, 7305h                     ; extended sector read/write
    @int21
    ret

;--- file image access

file_access:
    mov si, dx
    mov edx, dword ptr [qwDiskStart+0]; firstSector is always physical
    add edx, [lastSector]             ; last sector is physical/logical
    cmp eax, edx
    ja fa_error

;    shl eax, 9                        ; always "sector size" 512 for files
    movzx edx, [wBps]
    mul edx
if 0                                  ; not needed, since lastSector tells the file size
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
    cmp [handling], IGNORE_ERRORS     ; inside access_error
    je done
    mov ax, offset szSectorRErr       ; "Error reading Sector %lu"
    cmp [ioreq.bRW], RW_WRITE
    jne @F
    mov ax, offset szSectorWErr       ; "Error writing Sector %lu"
@@:
    mov dx, offset sprintfbuffer
    invoke sprintf, dx, ax, [ioreq.sectno]
    cmp [handling], ABORT_OPERATION   ; inside access_error
    je sectorerror2

;--- handling QUERY_FILL and QUERY_SKIP

;--- v0.99: save current menu text in BX?
;--- this won't work anymore, since menu text is rendered in sprintfbuffer
;    mov bx, [lastbottomtext]

    call printbottom
    mov dx, offset szSectorRErr3      ; "abort, skip, ignore all"
    cmp [handling], QUERY_SKIP        ; inside access_error
    je @F
    mov dx, offset szSectorRErr2      ; "abort, zero-fill"
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
    mov cx, [wBps]                    ; wBps is always set
    rep stosb
itsS:                                 ; skip
;    mov dx, bx                       ; v0.99: can't work anymore
;    call printbottom                 ; restore previous menu line
    call printmenu                    ; just refresh current menu 
    clc
    jmp done

checkskip:
    cmp al, 's'
    je itsS
    cmp al, 'i'
    jne gak
    mov [handling], IGNORE_ERRORS     ; inside access_error
    jmp itsS

sectorerror2:                         ; if ABORT_OPERATION is set
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
    call darkclr
    call getkey
    stc
    ret

darkclr3::
    cmp [bDark], 3
    jz @F
    inc [bDark]
    cmp [bDark], 3
    jz darkx
@@:
    ret
darkclr::
    mov [bDark], 1
darkx:
    pushf
    pusha
    mov [bUpdateScreen], 1
    mov ax, DARKMASK
    jmp swtclr
stdclr::
    mov [bDark], 0
    pushf
    pusha
    mov ax, NORMMASK
    mov ch, 32
    jmp @F
swtclr:
    mov ch, BOTTOMROW-1
@@:
    les di, [vidaddr]
    add di, [vidcolsize]
    mov dl, MAXCOL
    inc di
nextrow:
    push di
    mov cl, dl
nextattr:
    mov dh, es:[di]
    and dh, ah
    or  dh, al
    mov es:[di], dh
    add di, 2
    dec cl
    jnz nextattr
    pop di
    add di, [vidcolsize]
    dec ch
    jnz nextrow
    popa
    popf
    ret

printerror endp

;--- check char if it is a valid filename char
;--- AL must be preserved

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
    and al, al
    js checkoem
    cmp al, 'a'                   ; no lower case letters
    jae invalidchar
validchar:
    clc
    ret
invalidchar:
    stc
    ret
checkoem:
;--- check special chars
    push bx
    mov bl, al
    and bl, 7Fh
    mov bh, 0
    bt [oembittab],bx
    pop bx
    jnc invalidchar
    jmp validchar
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

;--- getpath: get a path ( filename/directory )
;--- getfilename: get a filename
;---   entered in menu row.
;--- IN:  AX: tabproc
;--- OUT: CX=length of path
;---      AH=last key scan code (check for TAB)
;---      [filenamebuffer]
;---      ax/di/dx/cx modified

if ?POSDIR
getpath:
    mov dx, offset szPathPrmt
    jmp get_fn_or_path
endif

getfilename proc
    mov dx, offset szFilePrmt
get_fn_or_path::
    call printbottom
    mov di, offset filenamebuffer
if ?LFN
    call darkclr
    invoke getstring, di, sizeof filenamebuffer, 0, 80 - sizeof szFilePrmt, ax
    mov cx, ax
else
    xor cx, cx
kbd_loop:
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
    je kbd_loop

    call validpathchar
    jc kbd_loop

    mov dl, al
    call printchar

    mov byte ptr [di], al
    inc di
    inc cx
    jmp kbd_loop

backspace:  
    jcxz kbd_loop              ; no characters left to delete
    dec cx
    call backcommon
    dec di
    jmp kbd_loop
handle_tab:
    cmp bl, 0                  ; TAB exits only if called by setdrive
    jnz kbd_loop
abort:
    xor cx, cx
done:
    mov byte ptr [di], 0       ; null-terminate filename
endif
    ret
getfilename endp

;-------------------------------------------------------
cbuffer_offset:                ; take what's in [scrn_xy] and set es:di to address
    push ax                    ; of the respective byte in the screen buffer
    push dx
    les di,[vidaddr]
    movzx ax, [scrn_xy.row]
    mul [vidcolsize]
    movzx dx, [scrn_xy.col]
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
    inc [scrn_xy.col]
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
    cmp dl, SFNENTRY.bCreMSec ; DIR_CREATEMSEC   ; fix! this code works for standard creation time only
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

;--- convert an offset (=spot) to a screen coordinate
;--- IN:  dx = spot
;--- OUT: dx = scrn row/col

spot2xy proc
    push ax
    mov ax, dx

    cmp [bDisplaymode], DM_BINARY
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
spot2xy endp
;-------------------------------------------------------
;--- prints " [Y/n]" on the screen
;--- carry flag set if 'Y'
getyn proc
    mov dx, offset ynmsg
    call printstring
    call darkclr
nextkey:
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
    jne nextkey
returnn:
    clc
    ret
returny:
    stc
    ret
getyn endp
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
    mov ax, 500h  ; select active page
    int 10h
    mov ah, 12h
    mov bl, 10h   ; get EGA info
    xor cx, cx
    int 10h
    or cx, cx     ; returns CH=feature, CL=switch, BH:00=color,01=mono
    jz doneset    ; jump if no EGA/VGA
    mov bl, 30h
    mov ax, 1202h ; set 400 scan lines
    int 10h
    mov ax, 7
    or bh, bh
    jnz @F
    mov al, 3
@@:
    int 10h
doneset:
else
    mov dh, [vidrows]
    dec dh
    mov dl, 0
    mov [scrn_xy], dx
    mov bh, [vidpg]
    mov ah, 2           ; set cursor pos to bottom line
    int 10h
    mov cx, 0808h       ; make cursor visible and set shape
    mov ah, 1
    int 10h
    mov ax, 07*100h+SPACE; 07=white on black
    mov cl, MAXCOL+1
    call fillcell
endif
if ?PM
    @loadvec [oldint24]
    mov bl, 24h
    mov ax, 0205h
    int 31h
    call exitwdepm
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
    cmp ah, MS_INACTIVE
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
    mov byte ptr [bx], 0
    pop dx
    call printbottom             ; and finally print the menu
    mov [bUpdateMenu], 0
    ret

printmenu endp

;--- getstringprompt: used by findstring and fillstring
;--- in:  -
;--- out: string in stringbuffer
;---      CX = string length

getstringprompt proc
    call darkclr
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
    dec [scrn_xy.col]
    mov dl, SPACE
    call printchar
    dec [scrn_xy.col]
    ret
;-------------------------------------------------------
movecursor:             ; IN:   ax = new [spot]
                        ;       dl = new [bHL]
    mov [spot], ax
    mov [bHL], dl
    jmp printoffset     ; and print new offset (=spot) 
  
;-------------------------------------------------------

checkabort:             ; sets equal flag if escape key was pressed
    push ax
    push dx
    mov ah, 06h         ; direct input is used since it takes
    mov dl, 0ffh        ; keys off the keybuffer
    int 21h
    cmp al, ESCAPE_KEY
    pop dx
    pop ax
    ret

;---
;--- set viewmode to DL.
;--- if viewmode changes, set bUpdateView to true.
;--- modifies ES, DI

setviewmode proc
    cmp [bViewmode], dl             ; if viewmode won't change
    je exit                         ; do nothing
if ?EXT
    mov cl, FUNCM_UNDELETE
    mov al, MS_INACTIVE
    call setmenuitem                ; remove "undelete"
endif
    mov cl, LDFILEOPT_CHAIN
    mov al, MS_INACTIVE             ; remove "chain"
    call setmenuitem
    cmp [bViewmode], VM_DIRECTORY   ; is old view directory?
    jnz @F
    call nodirview_ascii            ; restore ascii part to def. color
@@:
    mov [bViewmode], dl             ; set new view
clearviewarea::                     ; <--- called by updatescreen, helpscreen
    les di, [vidaddr]
    mov cx, [vidcolsize]
    mov ax, VIEWROW                 ; start of "view" area
    mul cx
    add di, ax
    mov dl, 7
;    mov ax, COL_DEFAULT shl 8 or SPACE
    mov ax, COL_STATTEXT shl 8 or SPACE
@@:
    push di
    push cx
    mov cx, MAXCOL+1
    rep stosw
    pop cx
    pop di
    add di, cx
    dec dl
    jnz @B
    mov bUpdateView, 1
exit:
    ret
setviewmode endp

;-------------------------------------------------------
getnos:                               ; 'get number of sectors' from the
    pushad                            ; user; don't allow 0 - if so
    mov eax, [lastSector]             ; then abort.
    sub eax, [currSector]
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
    mov [scrn_xy], (BOTTOMROW shl 8) + 1
;    mov [lastbottomtext], dx
    call printstring
    mov [bUpdateMenu], 1

;--- fall thru
;--- clear rest of bottom line

clearbottom:
    push cx
    push ax
    mov cl, MAXCOL+1
    sub cl, [scrn_xy.col]
    call fillspace
    pop ax
    pop cx
    ret

if ?POSDIR
;--- get file attribute in CX
;--- IN: filenamebuffer = filename

getfileattr proc
    xor cx, cx
    mov dx, offset filenamebuffer
if ?LFN
    mov bl, 0        ; action: 00=get file attributes
    mov ax, 7143h
    stc
    int 21h
    jc error
    cmp ax, 7100h
    jz error
    clc
    ret
error:
endif
    mov ax, 4300h
    int 21h
    ret
getfileattr endp

;--- get current directory
;--- IN: SI -> buffer
;---     DL = drive (00=current)

getcurrdir proc
if ?LFN
    mov ax, 7147h
    stc
    int 21h
    jc error
    cmp ax, 7100h
    jz error
    clc
    ret
error:
endif
    mov ah, 47h
    int 21h
    ret
getcurrdir endp

;--- IN: SI=path LFN
;---     DI=short name

getshortname proc
if ?LFN
    mov cx,1
    mov ax,7160h
    stc
    int 21h
    jc error
    cmp ax, 7100h
    jz error
    ret
error:
endif
nextchar:
    lodsb
    cmp al,'a'
    jb @F
    cmp al,'z'
    ja @F
    sub al, 'a' - 'A'
@@:
    stosb
    and al,al
    jnz nextchar
    ret
getshortname endp

endif

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

    mov [ioreq.sectno], eax

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
    add [ioreq.sectno], esi
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
    mov dx, offset abortwfmsg
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
    mov bl, 0    ; BL, bit 0-2: access mode, 4-7: sharing modes
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

;--- createfile: called by savechain(), savedata(), dumpiso()
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
    mov dx, offset abortwfmsg
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
    mov bx, sizeof stringbuffer
    xor ax, ax
    call gethexdi
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

gethexstring endp

;------------------------------------------------------
; gethexvalue:  used by "jumpto cluster" and "fill inc/dec".
; IN:           EAX: maxvalue
;               DX:  prompt
; OUT:          NC if ok
;               EBX: value gotten

gethexvalue proc

    mov [dwMaxvalue], eax
    mov bx, 80-8
    sub sp, bx
    mov di, sp
    mov byte ptr [di], 0
    mov ax, chkrou
    call gethexdi
    lea sp, [esp+80-8]
    ret

;--- callback
;--- si=hex chars
;--- cx=no of chars
;--- out: ebx=hex value
;--- if error, dx and bx must be restored

chkrou:
    push bx               ; bx must be restored if error
    xor ebx, ebx
    push cx
nextdigit:
    lodsb
    sub al, '0'
    cmp al, 9
    jbe @F
    or al, 20h
    sub al, 31h-10
@@:
    test ebx, 0f0000000h
    jnz invalvalue
    shl ebx, 4
    or bl, al
    loop nextdigit
    cmp ebx, [dwMaxvalue] ; value smaller or equal to maximum?
    ja invalvalue
    pop cx
    add sp, 2
    ret
invalvalue:
    pop cx
    pop bx
    stc
    ret

gethexvalue endp


;--- DX != 0: print prompt DX
;--- DX == 0: cursor pos in CX
;--- DI : start buffer
;--- BX = sizeof buffer
;--- AX = check routine or NULL
;--- out: si = buffer

gethexdi proc

    call darkclr
    push bp
    and dx, dx
    jz @F
    call printbottom
    xor cx, cx
@@:
    mov dl, MAXCOL
    sub dl, [scrn_xy.col]
    mov dh, 0
    mov bp, dx
    push ax
tryagain:
    invoke getstring, di, bx, cx, bp, offset @ret
    mov si, di
    mov cx, ax                 ; ax=chars, dx=cursor
    stc
    jcxz exit
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
    pop ax
    push ax
    cmp ax, 0
    jz @F
    call ax
    jc beepandcont
@@:
exit:
    pop ax
    pop bp
    ret
invalchar:
    add sp,2+2      ; skip saved si and cx
beepandcont:
    mov cx, dx      ; get saved cursor within string
    push bx
    mov bh, [vidpg]
    mov ax, 0E07h   ; beep!
    int 10h
    pop bx
    jmp tryagain

gethexdi endp

;-------------------------------------------------------
; OUT:  si -> offset to current wSectOfs buffer

bufferinsi:
    mov si, offset sectbuffer
    add si, [wSectOfs]
    ret

;-----------------------------------------------------------------
; OUT:  BX = current offset within buffer

spot2bufofs:
    mov bx, [wSectOfs]
    add bx, [spot]
    ret

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
