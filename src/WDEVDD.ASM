
;--- WDEVDD is a NTVDM VDD which
;--- supplies low-level access to block devices for WDE.
;--- Copyright japheth 2010-2022.
;--- Released under GNU GPL 2 license.

;--- emulated are:
;--- int 13h, ah=02h/03h/08h/41h/42h/43h/48h
;--- int 21h, ax=7305h ( add 7302h? )
;--- int 25h
;--- int 26h
;--- int 2fh, ax=1510h

	.386
	.MODEL FLAT, stdcall
	option casemap:none

	include winbase.inc
ifdef _DEBUG
	include winuser.inc
endif
	include vddsvc.inc

ifdef __JWASM__
@pe_file_flags = @pe_file_flags and not IMAGE_FILE_RELOCS_STRIPPED
@pe_file_flags = @pe_file_flags or      IMAGE_FILE_DLL
endif

?RAWMODE     equ 1	; 1=support CDROM raw read mode
?CDSECADJUST equ 1	; 1=adjust sector number for CD access

;--- CStr() define a string in .CONST

CStr macro string:req
local sym
	.const
sym db string,0
	 .code
	exitm <offset sym>
	endm

@DbgOutC macro xx
ifdef _DEBUG
	pushad
	invoke OutputDebugStringA, CStr(<xx>)
	popad
endif
	endm

@DbgOut macro xx:REQ, parms:VARARG
ifdef _DEBUG
	pushad
	invoke wsprintfA, addr szText, CStr(<xx>), parms
	invoke OutputDebugStringA, addr szText
	popad
endif
	endm

	.data

queried  dd 0
cddrvs   dd 0
hDisk    dd -1
bOldDisk dd -1
bOldAccess db -1
bOldMode db -1

	.data?

ifdef _DEBUG
szText	db 128 dup (?)
endif

	.code

;--- Init

Init proc stdcall export

	@DbgOutC <"WDEVDD.Init enter",13,10>
	@DbgOutC <"WDEVDD.Init exit",13,10>
	ret
	align 4

Init endp

;--- helper: 64bit multiplication

_mul64 proc public uses esi parm1:qword, parm2:dword

	mov esi,parm2
	xor esi,dword ptr parm1+4
	test dword ptr parm1+4,80000000h
	jz @F
	neg dword ptr parm1+4
	neg dword ptr parm1+0
	sbb dword ptr parm1+4,+0
@@:
	test parm2,80000000h
	jz @F
	neg parm2
@@:
	mov eax,parm2
	mul dword ptr parm1+0
	push edx
	mov ecx,eax
	mov eax,parm2
	mul dword ptr parm1+4
	add eax,[esp]
	test esi,80000000h
	jz @F
	neg eax
	neg ecx
	sbb eax,+0
@@:
	add esp,+4
	mov edx,eax
	mov eax,ecx
	ret
	align 4

_mul64 endp

;--- for INT 13, AH=48

I13DPARAM  struct   ;version 1
wSize     dw ?
wFlags    dw ?		;
dwCyls    dd ?		;num cylinders
dwHeads   dd ?		;tracks per cylinder
dwSecs    dd ?		;sectors per track
qwNumSecs dq ?
wBytSec   dw ?		;bytes per sector
I13DPARAM ends

GetDiskParameters proc public uses ebx pszDisk:ptr BYTE, pBuffer:ptr I13DPARAM, bUseEx:byte

local   handle:dword
local   cb:dword
local   dg:DISK_GEOMETRY
local   dgX:DISK_GEOMETRY_EX

	invoke CreateFileA, pszDisk,\
			GENERIC_READ,\
			FILE_SHARE_READ or FILE_SHARE_WRITE,\
			0, OPEN_EXISTING,\
			FILE_ATTRIBUTE_NORMAL, 0
	cmp eax,-1
	jz openerror
	mov handle, eax

	.if ( bUseEx )
		invoke DeviceIoControl, handle, IOCTL_DISK_GET_DRIVE_GEOMETRY_EX,\
				0,0, addr dgX, sizeof DISK_GEOMETRY_EX, addr cb, 0
		and eax, eax
		jz ioerror
		mov ebx, pBuffer
		mov eax,dword ptr dgX.Geometry.Cylinders
		mov ecx,dgX.Geometry.TracksPerCylinder
		mov edx,dgX.Geometry.SectorsPerTrack
		mov [ebx].I13DPARAM.wSize, sizeof I13DPARAM
		mov [ebx].I13DPARAM.dwCyls, eax
		mov [ebx].I13DPARAM.dwHeads, ecx
		mov [ebx].I13DPARAM.dwSecs, edx
		mov eax,dword ptr dgX.DiskSize+0
		mov edx,dword ptr dgX.DiskSize+4
		mov dword ptr [ebx].I13DPARAM.qwNumSecs+0, eax
		mov dword ptr [ebx].I13DPARAM.qwNumSecs+4, edx
		mov eax,dgX.Geometry.BytesPerSector
		mov [ebx].I13DPARAM.wBytSec, ax
	.else
		invoke DeviceIoControl, handle, IOCTL_DISK_GET_DRIVE_GEOMETRY,\
				0,0, addr dg, sizeof DISK_GEOMETRY, addr cb, 0
		and eax, eax
		jz ioerror
		mov ebx, pBuffer
		mov eax,dword ptr dg.Cylinders
		mov ecx,dg.TracksPerCylinder
		mov edx,dg.SectorsPerTrack
		mov [ebx].I13DPARAM.dwCyls, eax
		mov [ebx].I13DPARAM.dwHeads, ecx
		mov [ebx].I13DPARAM.dwSecs, edx
		mov eax,dg.BytesPerSector
		mov [ebx].I13DPARAM.wBytSec, ax
	.endif
	invoke CloseHandle, handle
	mov eax,1
	ret
openerror:
ifdef _DEBUG
	invoke GetLastError
	@DbgOut <"WDEVDD.GetDiskParameters open error [%X]",13,10>, eax
endif
	xor eax,eax
	ret
ioerror:
ifdef _DEBUG
	invoke GetLastError
	@DbgOut <"WDEVDD.GetDiskParameters io error [%X]",13,10>, eax
endif
	invoke CloseHandle, handle
	xor eax,eax
	ret

	align 4

GetDiskParameters endp

;--- test if drive is CDROM

IsCDROM proc drive:dword

local	szDrv[8]:byte

	mov eax, drive
	cmp eax,32
	jae no
	bts [queried], eax
	jc @F
	add al,'A'
	mov ah,':'
	mov dword ptr szDrv,eax
	mov szDrv+2,'\'
	invoke GetDriveTypeA, addr szDrv
	cmp eax, DRIVE_CDROM
	jnz @F
	mov eax,[drive]
	bts [cddrvs],eax
@@:
	mov eax,[drive]
	bt [cddrvs], eax
	jc yes
no:
	xor eax, eax
	ret
yes:
	mov eax,1
	ret
	align 4

IsCDROM endp

;--- int 21h, ax=7305:
;--- DL=drive (01=A:, ...)
;--- SI=read/write mode flags (0=read,1=write)
;--- DS:BX=disk packet

;--- int 25h/26h
;--- AL=drive (00=A:, ...)
;--- CX=sector numbers or FFFFh
;--- if CX != FFFF
;---   DX=start sector number
;---   DS:BX=read/write buffer
;--- if CX == FFFF
;---   DX=start sector number
;---   DS:BX=disk packet

;--- int 2Fh, ax=1510: (read/write long)
;--- CX=drive letter (0=A,...)
;--- ES:BX=device driver request

DPACKET struct
secsta	dd ?
seccnt	dw ?
bufofs	dw ?
bufseg	dw ?
DPACKET ends

if ?RAWMODE
RAW_READ_INFO struct
DiskOffset dq ?
SectorCount dd ?
TrackMode dd ?
RAW_READ_INFO ends
endif

;--- drive access emulation
;--- bType:
;---   0=Int 21h, ax=7305h
;---   1=Int 25h/26h
;---   2=Int 2Fh, ax=1510h
;--- bWrite: 0=read, 1=write (for bType=1 only)
;--- wAX:    value of register AX in VDM
;--- this proc modifies EBX and EDI

drive_access proc bType:byte, bWrite:byte, wAX:word

local	drive:dword
;local	hDisk:dword
local	dwRead:dword
local	dwBuffer:dword
local	secsize:dword
local	cdmode:byte
local	szDrv[8]:byte
local	tmppkt:DPACKET
local	bMode:dword
if ?RAWMODE
local	rri:RAW_READ_INFO
endif

	invoke getMSW
	and eax, 1
	mov bMode, eax
	invoke getEBX
	movzx edi, ax	; 16bit offset!
	invoke getDS
	invoke VdmMapFlat, eax, edi, bMode
	mov ebx, eax
	.if ( bType == 1 )
		movzx eax, byte ptr wAX
		mov drive, eax
		invoke getECX
		.if ( ax != 0FFFFh )
			lea ebx, tmppkt
			mov [ebx].DPACKET.seccnt, ax
			invoke getEDX
			movzx eax,ax
			mov [ebx].DPACKET.secsta, eax
			invoke getEBX
			mov [ebx].DPACKET.bufofs, ax
			invoke getDS
			mov [ebx].DPACKET.bufseg, ax
		.endif
	.elseif ( bType == 2 )
		invoke getCX
		mov drive, eax
		invoke getEBX
		movzx edi,ax
		invoke getES
		invoke VdmMapFlat, eax, edi, bMode
		mov edi, eax
		cmp byte ptr [edi+2],134	;134=write long
		jnz @F
		mov bWrite,1
@@:
		lea ebx, tmppkt
		mov ax, [edi+18]
		mov [ebx].DPACKET.seccnt, ax
		mov eax, [edi+20]
		mov [ebx].DPACKET.secsta, eax
		mov ax, [edi+14]
		mov [ebx].DPACKET.bufofs, ax
		mov ax, [edi+16]
		mov [ebx].DPACKET.bufseg, ax
		mov al, [edi+24]
		mov cdmode,al	; 0=cooked, 1=raw
	.else
		invoke getEDX
		movzx eax, al
		dec al
		mov drive, eax
		invoke getESI
		and al,1
		mov bWrite, al	; 0=read, 1=write
	.endif

	movzx ecx,[ebx].DPACKET.bufofs
	movzx eax,[ebx].DPACKET.bufseg
	invoke VdmMapFlat, eax, ecx, bMode
	mov dwBuffer, eax

	cmp bType, 2
	jz @F
	invoke IsCDROM, drive
	and eax, eax
	jnz typeerror
@@:
	@DbgOut <"WDEVDD.drive_access, drv=%s, packet=%X [cnt=%u, start=%X, buf=%X:%X], buffer=%X",13,10>,\
		addr szDrv, ebx, [ebx].DPACKET.seccnt, [ebx].DPACKET.secsta, [ebx].DPACKET.bufseg, [ebx].DPACKET.bufofs

	mov eax,[drive]
	add al,'A'
	mov ah,':'
	movzx eax,ax
	mov cl, bWrite
	.if eax != [bOldDisk] || cl != [bOldAccess] || bOldMode != 0
		mov [bOldDisk], eax
		mov [bOldAccess], cl
		mov bOldMode, 0
		mov dword ptr szDrv+0,"\.\\"
		mov dword ptr szDrv+4,eax
		.if hDisk != -1
			invoke CloseHandle, hDisk
			mov hDisk, -1
		.endif

		mov ecx, GENERIC_READ
			.if (bWrite)
			or ecx, GENERIC_WRITE
		.endif
		invoke CreateFileA, addr szDrv, ecx, FILE_SHARE_READ or FILE_SHARE_WRITE,\
			0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0
		cmp eax,-1
		jz openerror
		mov hDisk, eax
	.endif
	mov eax, [ebx].DPACKET.secsta
	mov edx,512
	cmp bType, 2
	jnz @F
	mov edx,2048	;or 2352
	cmp cdmode,1
	jnz @F
	mov edx,2352
if ?RAWMODE
	call rawreadcd
	jmp io_done
endif
@@:
	mov secsize, edx
	mul edx
	push edx
	mov edx, esp
	invoke SetFilePointer, hDisk, eax, edx, 0
	pop edx
	cmp eax, INVALID_SET_FILE_POINTER
	jnz @F
	invoke GetLastError
	cmp eax, NO_ERROR
	jnz poserror
@@:
	movzx ecx,[ebx].DPACKET.seccnt
	imul ecx, secsize
	.if (bWrite)
		invoke WriteFile, hDisk, dwBuffer, ecx, addr dwRead, 0
	.else
		invoke ReadFile, hDisk, dwBuffer, ecx, addr dwRead, 0
	.endif
io_done:
if 0
	push eax
	invoke CloseHandle, hDisk
	pop eax
endif
	and eax, eax
	jz accerror
	invoke setCF, 0
	ret
accerror:
ifdef _DEBUG
	invoke GetLastError
	@DbgOut <"WDEVDD.drive_access access error [%X]",13,10>, eax
	jmp generror
endif
poserror:
ifdef _DEBUG
	@DbgOut <"WDEVDD.drive_access pos error [%X]",13,10>, eax
	jmp generror
endif
openerror:
ifdef _DEBUG
	invoke GetLastError
	@DbgOut <"WDEVDD.drive_access open error [%X]",13,10>, eax
	jmp generror
endif
typeerror:
ifdef _DEBUG
	@DbgOutC <"WDEVDD.drive_access type error",13,10>
	jmp generror
endif
generror:
	invoke setAX, 0Ch	;general failure
	invoke setCF, 1
	ret
if ?RAWMODE
rawreadcd:
	mov secsize, edx
	movzx ecx, [ebx].DPACKET.seccnt
	mov eax, [ebx].DPACKET.secsta
	mov rri.SectorCount, ecx
if ?CDSECADJUST
	add eax, 32		;to match what WDE returns without WDEVDD
endif
	@DbgOut <"WDEVDD.drive_access CD-ROM raw read, true start sector=%u, cnt=%u",13,10>, eax, ecx
	mov edx, 2048	;!?
	mul edx
	mov dword ptr rri.DiskOffset+0, eax
	mov dword ptr rri.DiskOffset+4, edx
	mov rri.TrackMode, CDDA
	movzx ecx,[ebx].DPACKET.seccnt
	imul ecx, secsize
	invoke DeviceIoControl, hDisk, IOCTL_CDROM_RAW_READ, addr rri,
		sizeof RAW_READ_INFO, dwBuffer, ecx, addr dwRead, 0
	retn
endif

	align 4
drive_access endp

;--- CH=low bits cylinder number
;--- CL=sector + high bits cylinder number

I13DPARAM  struct   ;version 1
wSize     dw ?
wFlags    dw ?
dwCyls    dd ?		;num cylinders
dwHeads   dd ?		;tracks per cylinder
dwSecs    dd ?		;sectors per track
qwNumSecs dq ?
wBytSec   dw ?		;bytes per sector
I13DPARAM ends

set1308 proc params:ptr I13DPARAM
	mov edx, params
	mov al,byte ptr [edx].I13DPARAM.dwSecs
	.if ( [edx].I13DPARAM.dwCyls > 1024 )
		mov ah,0FFh
		or al,11000000b
	.else
		mov ecx,[edx].I13DPARAM.dwCyls
		dec ecx
		mov ah,cl
		shl ch,6
		or al,ch
	.endif
	invoke setCX, eax
	mov ah,byte ptr [edx].I13DPARAM.dwHeads
	dec ah
	mov al,1
	invoke setDX, eax
	ret
	align 4
set1308 endp

;--- disk access emulation ( int 13h )
;--- wAX: value of register AX in VDM
;--- this proc modifies EDI.
;--- supported is AH=02/03/08/42h/43h/48h

I13PACKET struct
wSize    dw ?
wBlocks  dw ?
dwBuffer dd ?
qwStart  dq ?       ;start block
I13PACKET ends

disk_access proc wAX:word

local	bIsFD:byte
local	bWrite:byte
local	drive:dword
;local	hDisk:dword
local	dwRead:dword
local	dwBuffer:dword
local	bMode:dword
local	szDrv[24]:byte
local	tmppkt:I13PACKET
local	drvparam:I13DPARAM

	invoke getMSW
	and eax,1
	mov bMode, eax
	mov bWrite, 0
	invoke getEDX
	movzx eax, al
	.if ( al & 80h )
		mov bIsFD, 0
	.else
		mov bIsFD, 1
	.endif
	and eax, 7Fh
	mov drive, eax
	invoke lstrcpyA, addr szDrv, CStr("\\.\PhysicalDrive")
	mov eax, drive
	add al,'0'
	mov word ptr szDrv+17,ax

	movzx eax, wAX
	.if ( ah == 2 || ah == 3 )
		.if ( ah == 3 )
			mov bWrite, 1
		.endif
		lea edi, tmppkt
		movzx ax, al
		mov [edi].I13PACKET.wBlocks, ax

		invoke GetDiskParameters, addr szDrv, addr drvparam, 0
		and eax, eax
		jz diskerror

		invoke getEBX
		movzx ecx,ax	;16bit offset!
		push ecx
		invoke getES
		pop ecx
		invoke VdmMapFlat, eax, ecx, bMode
		mov dwBuffer, eax
	.elseif ( ah == 8 )
		invoke GetDiskParameters, addr szDrv, addr drvparam, 0
		and eax, eax
		jz diskerror
		invoke set1308, addr drvparam
		jmp exit
	.elseif ( ah == 41h )
		invoke getEBX
		.if ax == 55AAh
			xchg ah, al
			invoke setEBX, eax
		.endif
		invoke getECX
		or al, 101b            ; set bits 0 (ah=42h/43h supported) and 2 (?)
		invoke setECX, eax
		jmp exit
	.elseif ( ah == 42h || ah == 43h )
		.if ( ah == 43h )
			mov bWrite, 1
		.endif
		invoke getESI
		movzx edi,ax	;16bit offset!
		invoke getDS
		invoke VdmMapFlat, eax, edi, bMode
		mov edi, eax	;EDI -> I13PACKET
		movzx eax, word ptr [edi].I13PACKET.dwBuffer+0
		movzx edx, word ptr [edi].I13PACKET.dwBuffer+2
		invoke VdmMapFlat, edx, eax, bMode
		mov dwBuffer, eax
	.elseif ( ah == 48h )
		invoke getESI
		movzx eax,ax	;16bit offset!
		push eax
		invoke getDS
		pop ecx
		invoke VdmMapFlat, eax, ecx, bMode
		invoke GetDiskParameters, addr szDrv, eax, 1
		and eax, eax
		jz diskerror
		jmp exit
	.else
		@DbgOut <"WDEVDD.disk_access, ax=%X not supported",13,10>, eax
		jmp generror	;unsupported
	.endif

	@DbgOut <"WDEVDD.disk_access, drv=%u, packet=%X [secs=%u, buf=%X, start=%X], buffer=%X",13,10>,\
		drive, edi, [edi].I13PACKET.wBlocks, [edi].I13PACKET.dwBuffer, dword ptr [edi].I13PACKET.qwStart, dwBuffer

	.if (bIsFD )
		jmp accerror	;FD access not supported, use disk access
	.endif

	mov eax, drive
	mov cl, bWrite
	.if eax != [bOldDisk] || [bOldAccess] != cl || bOldMode != 1
		mov [bOldDisk], eax
		mov cl, bWrite
		mov [bOldAccess], cl
		mov bOldMode, 1
		.if hDisk != -1
			invoke CloseHandle, hDisk
			mov hDisk, -1
		.endif
		mov ecx, GENERIC_READ
		.if (bWrite)
			or ecx, GENERIC_WRITE
		.endif
		invoke CreateFileA, addr szDrv, ecx, FILE_SHARE_READ or FILE_SHARE_WRITE,\
			0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0
		cmp eax,-1
		jz openerror
		mov hDisk, eax
	.endif
	
	invoke _mul64, [edi].I13PACKET.qwStart, 512
	push edx
	mov edx, esp
	invoke SetFilePointer, hDisk, eax, edx, 0
	pop edx
	cmp eax, INVALID_SET_FILE_POINTER
	jnz @F
	invoke GetLastError
	cmp eax, NO_ERROR
	jnz poserror
@@:
	movzx ecx,[edi].I13PACKET.wBlocks
	shl ecx,9
	.if (bWrite)
		invoke WriteFile, hDisk, dwBuffer, ecx, addr dwRead, 0
	.else
		invoke ReadFile, hDisk, dwBuffer, ecx, addr dwRead, 0
	.endif
if 0
	push eax
	invoke CloseHandle, hDisk
	pop eax
endif
	and eax, eax
	jz accerror
exit:
	invoke setCF, 0
	ret
diskerror:
ifdef _DEBUG
	invoke GetLastError
	@DbgOut <"WDEVDD.disk_access disk error",13,10>, eax
	jmp generror
endif
accerror:
ifdef _DEBUG
	invoke GetLastError
	@DbgOut <"WDEVDD.disk_access access error [%X]",13,10>, eax
	jmp generror
endif
poserror:
ifdef _DEBUG
	@DbgOut <"WDEVDD.disk_access pos error [%X]",13,10>, eax
	jmp generror
endif
openerror:
ifdef _DEBUG
	invoke GetLastError
	@DbgOut <"WDEVDD.disk_access open error, file=%s [%X]",13,10>, addr szDrv, eax
	jmp generror
endif
generror:
	invoke setAX, 0Ch	;general failure
	invoke setCF, 1
	ret

;--- translate CHS to LBA
;--- cl=maxcyl[8-9]+sectors/track in lowest 6 bits
;--- ch=maxcyl[0-7]
;--- dh=maxhead

Chs2Lba:
	mov ah,cl
	shr ah,6
	mov al,ch
	movzx eax,ax
	inc eax 		;cylinder in eax
	mov dl,dh
	movzx edx,dl
	inc edx 		;heads in edx
	and cl,3Fh
	movzx ecx,cl
	retn

	align 4

disk_access endp

;--- Dispatch
;--- int number is found in real-mode SS:[SP+0]
;--- value of register AX is found in real-mode SS:[SP+2]

Dispatch proc stdcall export uses ebx esi edi

local bMode:dword

	@DbgOutC <"WDEVDD.Dispatch enter",13,10>
	invoke getMSW
	and eax,1
	mov bMode, eax
	invoke getESP
	movzx ebx, ax
	invoke getSS
	movzx eax, ax
	invoke VdmMapFlat, eax, ebx, bMode
	movzx edi,word ptr [eax+0]	;int number
	movzx esi,word ptr [eax+2]	;VDM value of AX
	@DbgOut <"WDEVDD.Dispatch: emulate INT %02Xh, ax=%04X, sp=%04X",13,10>, edi, esi, ebx
	add bx, 4
	invoke setESP, ebx
	invoke setAX, si	;restore AX value

	.if di == 13h
		invoke disk_access, si
	.elseif di == 21h
		.if si == 7305h
			invoke drive_access, 0, 0, si
		.else
			@DbgOutC <"WDEVDD.Dispatch: can't handle this call",13,10>
			jmp error
		.endif
	.elseif di == 25h
		invoke drive_access, 1, 0, si
	.elseif di == 26h
		invoke drive_access, 1, 1, si
	.elseif di == 2Fh
		.if si == 1510h
			invoke drive_access, 2, 0, si
		.else
			@DbgOutC <"WDEVDD.Dispatch: can't handle this call",13,10>
			jmp error
		.endif
ifdef _DEBUG
	.elseif di == 41h
		invoke getSP
		movzx ebx,ax
		invoke getSS
		movzx eax, ax
		shl eax, 4
		add ebx, eax
		invoke getCS
		movzx eax, ax
		shl eax, 4
		movzx ecx, word ptr [ebx]
		add ecx, 2
		add eax, ecx
		invoke OutputDebugStringA, eax
endif
	.else
		@DbgOutC <"WDEVDD.Dispatch: can't handle this call",13,10>
		jmp error
	.endif
exit:
	@DbgOutC <"WDEVDD.Dispatch exit",13,10>
	ret
error:
	invoke setCF,1
	jmp exit
	align 4
Dispatch endp

;*** main proc ***

DllMain proc stdcall hInstance:dword, reason:dword, lpReserved:dword

	mov eax, reason
	.if (eax == DLL_PROCESS_ATTACH)
		@DbgOutC <"wdevdd process attach",13,10>
		mov eax,1
	.elseif (eax == DLL_PROCESS_DETACH)
		.if hDisk != -1
			invoke CloseHandle, hDisk
		.endif
		@DbgOutC <"wdevdd process detach",13,10>
	.elseif (eax == DLL_THREAD_ATTACH)
		@DbgOutC <"wdevdd thread attach",13,10>
	.elseif (eax == DLL_THREAD_DETACH)
		@DbgOutC <"wdevdd thread detach",13,10>
	.endif
	ret
DllMain endp

	END DllMain

