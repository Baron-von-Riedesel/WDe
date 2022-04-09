
DLL_PROCESS_ATTACH      equ 1
DLL_THREAD_ATTACH       equ 2
DLL_THREAD_DETACH       equ 3
DLL_PROCESS_DETACH      equ 0

PAGE_NOACCESS           equ     1h
PAGE_READONLY           equ     2h
PAGE_READWRITE          equ     4h
PAGE_WRITECOPY          equ     8h
PAGE_EXECUTE            equ    10h
PAGE_EXECUTE_READ       equ    20h
PAGE_EXECUTE_READWRITE  equ    40h
PAGE_EXECUTE_WRITECOPY  equ    80h
PAGE_GUARD              equ   100h
PAGE_NOCACHE            equ   200h
MEM_COMMIT              equ  1000h
MEM_RESERVE             equ  2000h
MEM_DECOMMIT            equ  4000h
MEM_RELEASE             equ  8000h
MEM_FREE                equ 10000h
MEM_PRIVATE             equ 20000h
MEM_MAPPED              equ 40000h
MEM_RESET               equ 80000h

MEMORY_BASIC_INFORMATION STRUCT
  BaseAddress       DWORD      ?
  AllocationBase    DWORD      ?
  AllocationProtect DWORD      ?
  RegionSize        DWORD      ?
  State             DWORD      ?
  Protect           DWORD      ?
  Type_             DWORD      ?
MEMORY_BASIC_INFORMATION ENDS

FILE_ATTRIBUTE_READONLY				EQU	00000001h
FILE_ATTRIBUTE_HIDDEN				EQU	00000002h
FILE_ATTRIBUTE_SYSTEM				EQU	00000004h
FILE_ATTRIBUTE_DIRECTORY			EQU	00000010h
FILE_ATTRIBUTE_ARCHIVE				EQU	00000020h
FILE_ATTRIBUTE_ENCRYPTED			EQU	00000040h
FILE_ATTRIBUTE_NORMAL				EQU	00000080h
FILE_ATTRIBUTE_TEMPORARY			EQU	00000100h

GENERIC_READ	  equ 80000000h
GENERIC_WRITE	  equ 40000000h

CREATE_NEW		  equ 1  ; fails if file already exists
CREATE_ALWAYS	  equ 2  ; if file exists, it will be overwritten
OPEN_EXISTING	  equ 3  ; fails if file doesn't exist
OPEN_ALWAYS 	  equ 4  ; creates file if it doesn't exist
TRUNCATE_EXISTING equ 5  ; fails if file doesn't exist. will be truncated

FILE_SHARE_READ		EQU	00000001h
FILE_SHARE_WRITE	EQU	00000002h
FILE_SHARE_DELETE	EQU	00000004h

IMAGE_FILE_RELOCS_STRIPPED  EQU 0001h
IMAGE_FILE_DLL              EQU 2000h

INVALID_SET_FILE_POINTER equ -1

DRIVE_CDROM equ 5

NO_ERROR equ 0

CTL_CODE macro DeviceType,Function,Method,Access
	exitm <( DeviceType  shl  16 )  or  ( Access  shl  14 )  or  ( Function  shl  2 )  or  Method>
	endm

FILE_DEVICE_CD_ROM EQU 00000002h
FILE_DEVICE_DISK   EQU 00000007h

METHOD_BUFFERED   EQU 0
METHOD_OUT_DIRECT EQU 2

FILE_ANY_ACCESS EQU 0
FILE_READ_ACCESS EQU 1

;--- CD Track Mode
YELLOWMODE2 EQU 0
XAFORM2     EQU 1
CDDA        EQU 2

IOCTL_DISK_BASE EQU FILE_DEVICE_DISK
IOCTL_CDROM_BASE EQU FILE_DEVICE_CD_ROM

IOCTL_DISK_GET_DRIVE_GEOMETRY EQU <CTL_CODE ( IOCTL_DISK_BASE , 0000h , METHOD_BUFFERED , FILE_ANY_ACCESS )>
IOCTL_DISK_GET_DRIVE_GEOMETRY_EX EQU <CTL_CODE ( IOCTL_DISK_BASE , 0028h , METHOD_BUFFERED , FILE_ANY_ACCESS )>
IOCTL_CDROM_RAW_READ EQU <CTL_CODE ( IOCTL_CDROM_BASE, 000Fh, METHOD_OUT_DIRECT, FILE_READ_ACCESS )>

DISK_GEOMETRY struct
Cylinders	dq ?
MediaType	dd ?
TracksPerCylinder	DWORD ?
SectorsPerTrack	DWORD ?
BytesPerSector	DWORD ?
DISK_GEOMETRY ends

DISK_PARTITION_INFO struct
SizeOfPartitionInfo DWORD ?
PartitionStyle		DWORD ?
union 
struct Mbr
Signature			DWORD ?
CheckSum			DWORD ?
ends
struct Gpt
DiskId				db 16 dup (?)
ends
ends
DISK_PARTITION_INFO ends

DISK_INT13_INFO struct 4
DriveSelect		WORD ?
MaxCylinders 	DWORD ?
SectorsPerTrack WORD ?
MaxHeads 		WORD ?
NumberDrives 	WORD ?
DISK_INT13_INFO ends

DISK_EX_INT13_INFO struct 8
ExBufferSize	WORD ?		;+0
ExFlags			WORD ?		;+2
ExCylinders		DWORD ?		;+4
ExHeads			DWORD ?
ExSectorsPerTrack DWORD ?	;+12
ExSectorsPerDrive QWORD ?	;+16
ExSectorSize	WORD ?		;+24
ExReserved		WORD ?
DISK_EX_INT13_INFO ends

DISK_DETECTION_INFO struct
SizeOfDetectInfo	DWORD ?			;+0	
DetectionType		DWORD ?			;+4
union
struct
Int13		DISK_INT13_INFO <>		;+8, size 16
ExInt13		DISK_EX_INT13_INFO <>	;+24, size 32
ends
ends
DISK_DETECTION_INFO ends

DISK_GEOMETRY_EX struct 8
Geometry	DISK_GEOMETRY <>
DiskSize	dq ?
			DISK_PARTITION_INFO <>
			DISK_DETECTION_INFO <>
DISK_GEOMETRY_EX ends


ifdef __JWASM__
	option dllimport:<kernel32.dll>
endif

AddAtomA				proto near stdcall :ptr byte
Beep					proto near stdcall x1:dword,x2:dword
CancelWaitableTimer 	proto near stdcall :dword
CloseHandle 			proto near stdcall x1:dword
CompareStringA 			proto near stdcall :DWORD, :DWORD, :ptr BYTE, :DWORD, :ptr BYTE, :DWORD
CompareStringW 			proto near stdcall :DWORD, :DWORD, :ptr WORD, :DWORD, :ptr WORD, :DWORD
CopyFileA 				proto near stdcall :ptr BYTE, :ptr BYTE, :DWORD
CreateDirectoryA		proto near stdcall :ptr BYTE, :dword
CreateDirectoryExA		proto near stdcall :ptr BYTE, :ptr BYTE, :ptr
CreateDirectoryW		proto near stdcall :ptr WORD, :dword
CreateEventA			proto near stdcall :dword, :dword, :dword, :ptr BYTE
CreateFileA 			proto near stdcall x1:dword,x2:dword,x3:dword,x4:dword,x5:dword,x6:dword,x7:dword
CreateFileMappingA		proto near stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:ptr BYTE
CreateMutexA			proto near stdcall :dword, :dword, :ptr BYTE
CreateMutexW			proto near stdcall :dword, :dword, :ptr WORD
CreateProcessA			proto near stdcall :ptr BYTE, :ptr BYTE, :dword, :dword, :dword, :dword, :ptr , :ptr BYTE, :ptr STARTUPINFOA, :ptr PROCESS_INFORMATION
CreateSemaphoreA		proto near stdcall a1:dword,a2:dword,a3:dword,a4:dword
CreateThread			proto near stdcall x1:dword,x2:dword,x3:dword,x4:dword,x5:dword,x6:dword
CreateWaitableTimerA	proto near stdcall :dword, :dword, :ptr BYTE
DebugBreak				proto near stdcall
DeleteAtom				proto near stdcall :dword
DeleteCriticalSection   proto near stdcall :ptr CRITICAL_SECTION
DeleteFileA 			proto near stdcall x1:dword
DeviceIoControl 		proto near stdcall :dword, :dword, :ptr, :dword, :ptr, :dword, :ptr dword, :dword
DisableThreadLibraryCalls proto near stdcall :dword
DosDateTimeToFileTime	proto near stdcall :DWORD, :DWORD, :ptr FILETIME
DuplicateHandle 		proto near stdcall :dword, :dword, :dword, :dword, :dword, :dword, :dword
EnterCriticalSection    proto near stdcall :ptr CRITICAL_SECTION
EnumResourceLanguagesA 	proto near stdcall :dword, :ptr BYTE, :ptr BYTE, :dword, :dword
EnumResourceNamesA  	proto near stdcall :dword, :ptr BYTE, :dword, :dword
EnumResourceTypesA  	proto near stdcall :dword, :dword, :dword
ExitProcess 			proto near stdcall :dword
ExitThread				proto near stdcall :dword
ExpandEnvironmentStringsA proto near stdcall :ptr BYTE, :ptr BYTE, :dword
FatalAppExitA			proto near stdcall :dword, :ptr BYTE
FileTimeToDosDateTime	proto near stdcall :ptr FILETIME, :ptr WORD, :ptr WORD
FileTimeToSystemTime    proto near stdcall :ptr FILETIME, :ptr SYSTEMTIME
FindAtomA				proto near stdcall :ptr byte
FindClose				proto near stdcall :dword
FindFirstFileA			proto near stdcall :ptr BYTE, :ptr WIN32_FIND_DATAA
FindFirstFileW			proto near stdcall :ptr WORD, :ptr WIN32_FIND_DATAW
FindNextFileA			proto near stdcall :dword, :ptr WIN32_FIND_DATAA
FindNextFileW			proto near stdcall :dword, :ptr WIN32_FIND_DATAW
FindResourceA			proto near stdcall a1:dword,a2:dword,a3:dword
FindResourceExA			proto near stdcall a1:dword,a2:dword,a3:dword,a4:dword
FindResourceW			proto near stdcall :dword, :ptr WORD, :ptr word
FlushFileBuffers		proto near stdcall x1:dword
FlushViewOfFile			proto near stdcall :ptr, :dword
FormatMessageA			proto near stdcall :dword, :ptr, :DWORD, :DWORD, :ptr BYTE, :DWORD, :ptr
FreeEnvironmentStringsA proto near stdcall x1:dword
FreeEnvironmentStringsW proto near stdcall x1:dword
FreeLibrary 			proto near stdcall :dword
GetACP			 		proto near stdcall
GetAtomNameA 			proto near stdcall :dword, :ptr byte, :dword
GetCommandLineA 		proto near stdcall
GetComputerNameA 		proto near stdcall :ptr BYTE, :ptr DWORD
GetCurrentDirectoryA	proto near stdcall a1:dword,a2:ptr byte
GetCurrentProcess		proto near stdcall
GetCurrentProcessId		proto near stdcall
GetCurrentThread		proto near stdcall
GetCurrentThreadId		proto near stdcall
GetDateFormatA			proto near stdcall lcid:DWORD, dwFlags:DWORD, pDate:ptr SYSTEMTIME,lpFormat:ptr BYTE, lpDateStr:ptr BYTE, cchDate:DWORD
GetDiskFreeSpaceA		proto near stdcall :ptr BYTE, :ptr dword, :ptr dword, :ptr dword, :ptr dword
GetDiskFreeSpaceW		proto near stdcall :ptr WORD, :ptr dword, :ptr dword, :ptr dword, :ptr dword
GetDriveTypeA			proto near stdcall a1:ptr BYTE
GetDriveTypeW			proto near stdcall a1:ptr WORD
GetEnvironmentStrings	proto near stdcall
GetEnvironmentStringsA	proto near stdcall
GetEnvironmentStringsW	proto near stdcall
GetEnvironmentVariableA proto near stdcall :ptr BYTE, :ptr BYTE, :dword
GetExitCodeThread		proto near stdcall :dword, :ptr dword
GetFileAttributesA		proto near stdcall :ptr byte
GetFileAttributesExA	proto near stdcall :ptr BYTE, :DWORD, :ptr WIN32_FILE_ATTRIBUTE_DATA
GetFileSize 			proto near stdcall :dword, :ptr dword
GetFileTime 			proto near stdcall :dword, :ptr FILETIME, :ptr FILETIME, :ptr FILETIME
GetFileType 			proto near stdcall x1:dword
GetFullPathNameA		proto near stdcall :ptr BYTE, :DWORD, :ptr BYTE, :ptr ptr BYTE
GetFullPathNameW		proto near stdcall :ptr WORD, :DWORD, :ptr WORD, :ptr ptr WORD
GetLastError			proto near stdcall
GetLocaleInfoA			proto near stdcall :dword, :dword, :ptr BYTE, :dword
GetLocalTime			proto near stdcall x1:ptr SYSTEMTIME
GetLongPathNameA		proto near stdcall :ptr byte, :ptr byte, :DWORD
GetModuleFileNameA		proto near stdcall :dword, :ptr byte, :dword
GetModuleHandleA		proto near stdcall :ptr BYTE
GetNumberOfConsoleMouseButtons proto near stdcall :ptr DWORD
GetOEMCP			 	proto near stdcall
GetPrivateProfileStringA proto near stdcall :ptr BYTE, :ptr BYTE, :ptr BYTE, :ptr BYTE, :DWORD, :ptr BYTE
GetProcAddress			proto near stdcall :DWORD, :DWORD
GetProcessHeap			proto near stdcall
GetShortPathNameA		proto near stdcall :ptr byte, :ptr byte, :DWORD
GetStartupInfoA 		proto near stdcall :ptr STARTUPINFOA
GetStdHandle			proto near stdcall a1:dword
GetSystemDirectoryA 	proto near stdcall :ptr byte, :DWORD
GetSystemTime			proto near stdcall :ptr SYSTEMTIME
GetSystemTimeAsFileTime proto near stdcall a1:ptr FILETIME
GetTempFileNameA		proto near stdcall :ptr BYTE, :ptr BYTE, :DWORD, :ptr BYTE
GetTempPathA			proto near stdcall :DWORD, :ptr BYTE
GetTickCount			proto near stdcall
GetUserDefaultLCID      proto near stdcall
GetVersion				proto near stdcall
GetVersionExA			proto near stdcall :ptr OSVERSIONINFO
GlobalAddAtomA			proto near stdcall :ptr BYTE
GlobalAlloc 			proto near stdcall :dword, :dword
GlobalFree	 			proto near stdcall :dword
GlobalGetAtomNameA		proto near stdcall :dword, :ptr BYTE, :dword
GlobalMemoryStatus		proto near stdcall :ptr MEMORYSTATUS
GlobalSize	 			proto near stdcall :dword
HeapAlloc				proto near stdcall :dword, :dword, :dword
HeapCreate				proto near stdcall :dword, :dword, :dword
HeapDestroy 			proto near stdcall :dword
HeapFree				proto near stdcall :dword, :dword, :dword
HeapReAlloc				proto near stdcall :dword, :dword, :dword, :dword
HeapSize				proto near stdcall :dword, :dword, :dword
HeapValidate			proto near stdcall :dword, :dword, :dword
HeapWalk				proto near stdcall :dword, :ptr PROCESS_HEAP_ENTRY
InitializeCriticalSection proto near stdcall :ptr CRITICAL_SECTION
InterlockedDecrement	proto near stdcall :dword
InterlockedExchange		proto near stdcall :ptr DWORD, :DWORD
InterlockedIncrement	proto near stdcall :dword
IsBadCodePtr			proto near stdcall :DWORD
IsBadReadPtr			proto near stdcall :DWORD, :DWORD
IsBadWritePtr			proto near stdcall :DWORD, :DWORD
IsDebuggerPresent		proto near stdcall
IsProcessorFeaturePresent proto near stdcall :dword
LeaveCriticalSection    proto near stdcall :ptr CRITICAL_SECTION
LoadLibraryA			proto near stdcall :ptr BYTE
LoadLibraryExA			proto near stdcall :ptr BYTE, :DWORD, :DWORD
LoadResource			proto near stdcall :dword, :dword
LocalAlloc				proto near stdcall :dword, :dword
LocalFileTimeToFileTime proto near stdcall :ptr FILETIME, :ptr FILETIME
LocalFree				proto near stdcall :dword
MapViewOfFile	 		proto near stdcall :dword, :dword, :dword, :dword, :dword
MapViewOfFileEx	 		proto near stdcall :dword, :dword, :dword, :dword, :dword, :ptr
MoveFileA 				proto near stdcall :ptr BYTE, :ptr BYTE
MoveFileExA 			proto near stdcall :ptr BYTE, :ptr BYTE, :dword
MultiByteToWideChar		proto near stdcall :DWORD, :DWORD, :ptr BYTE, :DWORD, :ptr WORD, :DWORD
OpenEventA				proto near stdcall :dword, :dword, :ptr BYTE
OpenFile		 		proto near stdcall :ptr byte, :ptr OFSTRUCT, :dword
OpenFileMappingA 		proto near stdcall :dword, :dword, :ptr BYTE
OpenMutexA 				proto near stdcall :dword, :dword, :dword
OpenProcess 			proto near stdcall :dword, :dword, :dword
OpenSemaphoreA  		proto near stdcall :dword, :dword, :dword
OutputDebugStringA		proto near stdcall :ptr BYTE
PulseEvent				proto near stdcall :dword
QueueUserAPC			proto near stdcall :dword, :dword, :dword
RaiseException			proto near stdcall :DWORD, :DWORD, :DWORD, :ptr
ReadFile				proto near stdcall :dword, :dword, :dword, :ptr dword, :ptr OVERLAPPED
ReleaseMutex			proto near stdcall a1:dword
ReleaseSemaphore		proto near stdcall a1:dword,a2:dword,a3:dword
RemoveDirectoryA		proto near stdcall :ptr BYTE
RemoveDirectoryW		proto near stdcall :ptr WORD
ResetEvent  			proto near stdcall :dword
ResumeThread			proto near stdcall x1:dword
RtlFillMemory			proto near stdcall :ptr BYTE, :DWORD, :dword
RtlMoveMemory			proto near stdcall :ptr BYTE, :ptr BYTE, :dword
RtlUnwind				proto near stdcall :ptr EXCEPTION_REGISTRATION, :dword, :ptr EXCEPTION_RECORD, :dword
RtlZeroMemory			proto near stdcall :ptr BYTE, :dword
SearchPathA				proto near stdcall :ptr BYTE, :ptr BYTE, :ptr BYTE, :DWORD, :ptr BYTE, :ptr ptr BYTE
SetCurrentDirectoryA	proto near stdcall :ptr BYTE
SetCurrentDirectoryW	proto near stdcall :ptr WORD
SetEndOfFile  			proto near stdcall :dword
SetEnvironmentVariableA proto near stdcall x1:ptr BYTE,x2:ptr BYTE
SetErrorMode			proto near stdcall x1:dword
SetEvent				proto near stdcall :dword
SetFileAttributesA		proto near stdcall :ptr byte, :dword
SetFilePointer			proto near stdcall :dword, :dword, :dword, :dword
SetFilePointerEx		proto near stdcall :dword, :qword, :ptr QWORD, :dword
SetFileTime 			proto near stdcall :dword, :ptr FILETIME, :ptr FILETIME, :ptr FILETIME
SetHandleCount			proto near stdcall :dword
SetLastError			proto near stdcall :dword
SetPriorityClass		proto near stdcall :dword, :dword
SetStdHandle			proto near stdcall :dword, :dword
SetThreadPriority		proto near stdcall :dword, :dword
SetUnhandledExceptionFilter proto near stdcall :ptr
SetWaitableTimer		proto near stdcall :dword, :ptr QWORD, :dword, :dword, :dword, :dword
SizeofResource			proto near stdcall :dword, :dword
Sleep					proto near stdcall x1:dword
SuspendThread			proto near stdcall x1:dword
SwitchToThread			proto near stdcall
SystemTimeToFileTime	proto near stdcall :ptr SYSTEMTIME, :ptr FILETIME
TerminateProcess		proto near stdcall x1:dword,x2:dword
TerminateThread 		proto near stdcall x1:dword,x2:dword
TlsAlloc				proto near stdcall
TlsFree 				proto near stdcall :dword
TlsGetValue 			proto near stdcall x1:dword
TlsSetValue 			proto near stdcall x1:dword,x2:dword
UnmapViewOfFile			proto near stdcall x1:ptr
VirtualAlloc			proto near stdcall x1:dword,x2:dword,x3:dword,x4:dword
VirtualFree 			proto near stdcall x1:dword,x2:dword,x3:dword
VirtualLock 			proto near stdcall x1:dword,x2:dword
VirtualProtect			proto near stdcall x1:dword,x2:dword,x3:dword,x4:dword
VirtualQuery			proto near stdcall :dword, :ptr MEMORY_BASIC_INFORMATION, :dword
WaitForSingleObject 	proto near stdcall x1:dword,x2:dword
WaitForMultipleObjects 	proto near stdcall :dword, :ptr dword, :dword, :dword
WideCharToMultiByte		proto near stdcall :DWORD, :DWORD, :ptr WORD, :DWORD, :ptr BYTE, :DWORD, :DWORD, :DWORD
WinExec 				proto near stdcall :ptr BYTE, :DWORD
WriteFile				proto near stdcall :dword, :dword, :dword, :ptr dword, :ptr OVERLAPPED
WritePrivateProfileStringA	proto near stdcall lpAppName:ptr BYTE, lpKeyName:ptr BYTE, lpString:ptr BYTE, lpFileName:ptr BYTE
_lcreat 				proto near stdcall :dword, :dword
_llseek 				proto near stdcall :dword, :dword, :dword
_lopen					proto near stdcall :dword, :dword
_lclose 				proto near stdcall :dword
_lread					proto near stdcall :dword, :dword, :dword
_lwrite 				proto near stdcall :dword, :dword, :dword
lstrcat 				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcatA				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcatW				proto near stdcall :ptr WORD, :ptr WORD
lstrcmp 				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcmpA				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcmpi				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcmpiA				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcpy 				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcpyA				proto near stdcall :ptr BYTE, :ptr BYTE
lstrcpyn				proto near stdcall :ptr BYTE, :ptr BYTE, :DWORD
lstrcpynA				proto near stdcall :ptr BYTE, :ptr BYTE, :DWORD
lstrcpynW				proto near stdcall :ptr WORD, :ptr WORD, :DWORD
lstrlen 				proto near stdcall :ptr BYTE
lstrlenA				proto near stdcall :ptr BYTE
lstrlenW				proto near stdcall :ptr WORD

ifdef __JWASM__
	option dllimport:none
endif

ZeroMemory	textequ <RtlZeroMemory>
FillMemory	textequ <RtlFillMemory>
CopyMemory	textequ <RtlMoveMemory>

