
EXFAT struct
    db 64 dup (?)
dqHidden dq ?     ; +64 sector offset to start of partition
dqSize   dq ?     ; +72 size of volume in sectors
dwFatOfs dd ?     ; +80 offset in sectors to start of first FAT
dwFatSiz dd ?     ; +84 size of a FAT in sectors
dwClHpOfs dd ?    ; +88 offset in sectors to start of clusters
dwClCnt   dd ?    ; +92 no of clusters in cluster "heap"
dwRootCl  dd ?    ; +96 starting cluster of root dir
dwVolId   dd ?    ; volume serial no
wFSRev    dw ?   
wVolFlgs  dw ?
bBpSShift db ?    ; bytes per sector shift
bSpCShift db ?    ; sectors per cluster shift
bNumFats  db ?    ; number of FATs
bDrive    db ?    ; drive no (80h=phys disk 0)
EXFAT ends

;--- entry type bits
;--- 0-4: type code
;---   5: importance, 0=critical, 1=benign
;---   6: category, 0=primary, 1=secondary
;---   7: InUse, 0=entry is free, 1=in use

;--- primary flags
;--- bit 0: 0=cluster and size are undefined, 1=are defined
;--- bit 1: 0=has FAT chain, 1=no FAT chain, is contiguous series of cluster
;--- bit 2-15: custom defined

;--- critical primary:
;--- typecode 1: allocation bitmap: 81h = bitmap
;--- typecode 2: upcase table       82h = upcase table
;--- typecode 3: volume label
;--- typecode 5: file               85h = file/directory

EXFTC_GUID     equ 0  ; no cluster/size fields, no secondary
EXFTC_ALLOCBM  equ 1
EXFTC_UPCASET  equ 2
EXFTC_VOLLABEL equ 3  ; no cluster/size fields, just count and 11 wide characters
EXFTC_FILE     equ 5

EFET_EOD equ 0     ; end of directory

;--- generic primary entry

EXFATDIR struct
etype     db ?     ; entry type
seccnt     db ?    ; secondary count - no of secondary entries that follow
chksum     dw ?    ;
primflgs   dw ?    ; see above ( primary flags )
          db 14 dup (?) ; custom defined
dwFirstCl  dd ?    ; first cluster
dqSize     dq ?    ; data length
EXFATDIR ends

;--- secondary flags
;--- bit 0: allocation possible
;--- bit 1: no fat chain
;--- bit 2-15: custom defined

;--- generic secondary entry

EXFATDIRS struct
etype     db ?     ; entry type
secflgs   db ?
          db 18 dup (?) ; custom defined
dwFirstCl  dd ?    ; first cluster
dqSize     dq ?    ; data length
EXFATDIRS ends

;--- file direntry:
;--- db type
;--- db secondary count
;--- dw checksum
;--- dw attributes
;--- dw reserved
;--- dd created
;--- dd last modified
;--- dd last accessed
;--- db create 10ms inc
;--- db last modifed 10ms inc
;--- db create utc offset
;--- db last modifed utc offset
;--- db last accessed utc offset
;--- db 7 dup (?) reserved

EXFATDIRF struct
etype      db ?            ;+0
seccnt     db ?
chksum     dw ?            ;+2
attributes dw ?
           dw ?
dwCreated  dd ?            ;+8
dwModified dd ?
dwAccessed dd ?
bCreInc    db ?            ;+20
bModInc    db ?
bCreUtcOfs db ?
bModUtcOfs db ?
bAccUtcOfs db ?
           db 7 dup (?)
EXFATDIRF ends

;--- attributes:
;--- bit 0-5: readonly, hidden, system, reserved, directory, archive
;--- bit 6-15: reserved 

;--- stream extension, critical secondary entry in a file directory entry set,
;--- must immediately follow the primary entry, just 1 in a set.
;--- typecode is 0.

EXFATDIRFS struct
etype     db ?
secflgs   db ?
          db ?
namelength db ?
namehash  dw ?
          dw ?
dqValiddatalength dq ?
          dd ?
firstcl   dd ?
dqSize    dq ?
EXFATDIRFS ends                              

;--- structure of generic secondary entries
;--- 0: type
;--- 1: general secondary flags (byte); bits 0-1 like primary flags
;---20: cluster
;---24: size

;--- critical secondary file name direntry
;--- db type ( typecode is 1 )
;--- db secondary flags
;--- db 30 dup ? name

