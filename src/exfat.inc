
;--- exFAT data structures as documented by MS

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

EFET_EOD equ 0     ; end of directory

;--- entry type bits
;--- 0-4: type code
;---   5: importance, 0=critical, 1=benign
;---   6: category, 0=primary, 1=secondary
;---   7: InUse, 0=entry is free, 1=in use

;--- critical primary:
;--- typecode 1: allocation bitmap: 81h
;--- typecode 2: upcase table       82h
;--- typecode 3: volume label       83h
;--- typecode 5: file               85h

EXFTC_GUID     equ 0  ; no cluster/size fields, no secondary
EXFTC_ALLOCBM  equ 1
EXFTC_UPCASET  equ 2
EXFTC_VOLLABEL equ 3  ; no cluster/size fields, just count and 11 wide characters
EXFTC_FILE     equ 5

;--- primary flags
;--- bit 0: 0=cluster and size are undefined, 1=are defined
;--- bit 1: 0=has FAT chain, 1=no FAT chain, is contiguous series of cluster
;--- bit 2-15: custom defined

EXFPF_CLSDEFINED equ 1
EXFPF_NOCHAIN    equ 2

;--- generic primary entry

EXFATDIR struct
etype      db ?    ; entry type
seccnt     db ?    ; secondary count - no of secondary entries that follow
chksum     dw ?    ;
;primflgs   dw ?    ; see above ( primary flags ) - this field is NOT very generic
           dw ?
           db 14 dup (?) ; custom defined
dwFirstCl  dd ?    ; first cluster
dqSize     dq ?    ; data length
EXFATDIR ends

;--- primary file entry

EXFATDIRF struct
etype      db ?            ;+0
seccnt     db ?            ;+1 secondary count
chksum     dw ?            ;+2
attributes dw ?
           dw ?
dwCreated  dd ?            ;+8
dwModified dd ?            ;+12 last modified
dwAccessed dd ?            ;+16 last accessed
bCreInc    db ?            ;+20 create 10ms inc
bModInc    db ?            ;+21 last modifed 10ms inc
bCreUtcOfs db ?            ;+22 create utc offset
bModUtcOfs db ?            ;+23 last modifed utc offset
bAccUtcOfs db ?            ;+24 last accessed utc offset
           db 7 dup (?)
EXFATDIRF ends

;--- attributes:
;--- bit 0-5: readonly, hidden, system, reserved, directory, archive
;--- bit 6-15: reserved 

;--- generic secondary entry

;--- secondary flags
;--- bit 0: 1=cluster & size defined
;--- bit 1: 1=no fat chain
;--- bit 2-15: custom defined

EXFATDIRS struct
etype      db ?     ; entry type
secflgs    db ?
           db 18 dup (?) ; custom defined
dwFirstCl  dd ?     ; first cluster
dqSize     dq ?     ; data length
EXFATDIRS ends

;--- stream extension, critical secondary entry in a file directory entry set,
;--- must immediately follow the primary entry, just 1 in a set.
;--- typecode is 0.

EXFATDIRSS struct
etype      db ?
secflgs    db ?
           db ?
namelength db ?
namehash   dw ?
           dw ?
dqValiddatalength dq ?
           dd ?
dwFirstCl  dd ?
dqSize     dq ?
EXFATDIRSS ends                              

;--- critical secondary file name direntry
;--- typecode is 1.

EXFATDIRSN struct
etype      db ?
secflgs    db ?
name_      dw 15 dup (?)
EXFATDIRSN ends
