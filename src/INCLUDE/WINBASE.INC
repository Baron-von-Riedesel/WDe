
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

		.DATA

func@0  typedef proto stdcall
func@4  typedef proto stdcall a1:dword
func@8  typedef proto stdcall a1:dword,a2:dword
func@12 typedef proto stdcall a1:dword,a2:dword,a3:dword
func@16 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword
func@20 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword
func@24 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:dword
func@28 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:dword,a7:dword
func@32 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:dword,a7:dword,a8:dword
func@36 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:dword,a7:dword,a8:dword,a9:dword
func@40 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:dword,a7:dword,a8:dword,a9:dword,a10:dword
func@44 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:dword,a7:dword,a8:dword,a9:dword,a10:dword,a11:dword
func@48 typedef proto stdcall a1:dword,a2:dword,a3:dword,a4:dword,a5:dword,a6:dword,a7:dword,a8:dword,a9:dword,a10:dword,a11:dword,a12:dword
cfunc@8v typedef proto c a1:dword,a2:dword,a3:vararg

pfunc@0  typedef ptr func@0
pfunc@4  typedef ptr func@4
pfunc@8  typedef ptr func@8
pfunc@12 typedef ptr func@12
pfunc@16 typedef ptr func@16
pfunc@20 typedef ptr func@20
pfunc@24 typedef ptr func@24
pfunc@28 typedef ptr func@28
pfunc@32 typedef ptr func@32
pfunc@36 typedef ptr func@36
pfunc@40 typedef ptr func@40
pfunc@44 typedef ptr func@44
pfunc@48 typedef ptr func@48
cpfunc@8v typedef ptr cfunc@8v

 @Kernel macro name_, parms
 externdef stdcall _imp__&name_&@&parms :pfunc@&parms
 name_ equ <_imp__&name_&@&parms>
 endm


@Kernel AddAtomA, 4
@Kernel Beep, 8
@Kernel CancelWaitableTimer, 4
@Kernel CloseHandle, 4
@Kernel CopyFileA, 12
@Kernel CompareStringA, 24
@Kernel CompareStringW, 24
@Kernel CreateDirectoryA, 8
@Kernel CreateEventA, 16
@Kernel CreateFileA, 28
@Kernel CreateFileMappingA, 24
@Kernel CreateMutexA, 12
@Kernel CreateMutexW, 12
@Kernel CreateProcessA, 40
@Kernel CreateSemaphoreA, 16
@Kernel CreateThread, 24
@Kernel CreateWaitableTimerA, 12
@Kernel DebugBreak, 0
@Kernel DeleteAtom, 4
@Kernel DeleteCriticalSection, 4
@Kernel DeleteFileA, 4
@Kernel DeviceIoControl, 32
@Kernel DisableThreadLibraryCalls, 4
@Kernel DosDateTimeToFileTime, 12
@Kernel DuplicateHandle, 28
@Kernel EnterCriticalSection, 4
@Kernel EnumResourceLanguagesA, 20
@Kernel EnumResourceNamesA, 16
@Kernel EnumResourceTypesA, 12
@Kernel ExitProcess, 4
@Kernel ExitThread, 4
@Kernel ExpandEnvironmentStringsA, 12
@Kernel FatalAppExitA, 8
@Kernel FileTimeToDosDateTime, 12
@Kernel FileTimeToSystemTime, 8
@Kernel FindAtomA, 4
@Kernel FindClose, 4
@Kernel FindFirstFileA, 8
@Kernel FindNextFileA, 8
@Kernel FindResourceA, 12
@Kernel FindResourceExA, 16
@Kernel FindResourceW, 12
@Kernel FlushFileBuffers, 4
@Kernel FlushViewOfFile, 8
@Kernel FreeEnvironmentStringsA, 4
@Kernel FreeEnvironmentStringsW, 4
@Kernel FreeLibrary, 4
@Kernel GetACP, 0
@Kernel GetAtomNameA, 12
@Kernel GetCommandLineA, 0
@Kernel GetComputerNameA, 8
@Kernel GetCurrentDirectoryA, 8
@Kernel GetCurrentProcess, 0
@Kernel GetCurrentProcessId, 0
@Kernel GetCurrentThread, 0
@Kernel GetCurrentThreadId, 0
@Kernel GetDateFormatA, 20
@Kernel GetDiskFreeSpaceA, 20
@Kernel GetDriveTypeA, 4
@Kernel GetEnvironmentStrings, 0
@Kernel GetEnvironmentStringsA, 0
@Kernel GetEnvironmentStringsW, 0
@Kernel GetEnvironmentVariableA, 12
@Kernel GetExitCodeThread, 8
@Kernel GetFileAttributesA, 4
@Kernel GetFileAttributesExA, 12
@Kernel GetFileSize, 8
@Kernel GetFileTime, 16
@Kernel GetFileType, 4
@Kernel GetFullPathNameA, 16
@Kernel GetLastError, 0
@Kernel GetLocalTime, 4
@Kernel GetLongPathNameA, 12
@Kernel GetModuleFileNameA, 12
@Kernel GetModuleHandleA, 4
@Kernel GetNumberOfConsoleMouseButtons, 4
@Kernel GetOEMCP, 0
@Kernel GetPrivateProfileStringA, 24
@Kernel GetProcAddress, 8
@Kernel GetProcessHeap, 0
@Kernel GetShortPathNameA, 12
@Kernel GetStdHandle, 4
@Kernel GetSystemTime, 4
@Kernel GetSystemTimeAsFileTime, 4
@Kernel GetTempFileNameA, 16
@Kernel GetTempPathA, 8
@Kernel GetThreadPriority, 4
@Kernel GetTickCount, 0
@Kernel GetUserDefaultLCID, 0
@Kernel GetVersion, 0
@Kernel GetVersionExA, 4
@Kernel GlobalAlloc, 8
@Kernel GlobalFree, 4
@Kernel GlobalMemoryStatus, 4
@Kernel GlobalReAlloc, 12
@Kernel HeapAlloc, 12
@Kernel HeapCreate, 12
@Kernel HeapDestroy, 4
@Kernel HeapFree, 12
@Kernel HeapReAlloc, 16
@Kernel HeapSize, 12
@Kernel HeapValidate, 12
@Kernel HeapWalk, 8
@Kernel InitializeCriticalSection, 4
@Kernel InterlockedDecrement, 4
@Kernel InterlockedIncrement, 4
@Kernel IsDebuggerPresent, 0
@Kernel LeaveCriticalSection, 4
@Kernel LoadLibraryA, 4
@Kernel LoadResource, 8
@Kernel LocalAlloc, 8
@Kernel LocalFileTimeToFileTime, 8
@Kernel LocalFree, 4
@Kernel LocalHandle, 4
@Kernel LocalReAlloc, 12
@Kernel LocalSize, 4
@Kernel MapViewOfFile, 20
@Kernel MapViewOfFileEx, 24
@Kernel MoveFileA, 8
@Kernel MultiByteToWideChar, 24
@Kernel OpenFile, 12
@Kernel OpenFileMappingA, 12
@Kernel OpenMutexA, 12
@Kernel OpenProcess, 12
@Kernel OpenSemaphoreA, 12
@Kernel OutputDebugStringA, 4
@Kernel PulseEvent, 4
@Kernel QueryPerformanceCounter, 4
@Kernel QueryPerformanceFrequency, 4
@Kernel QueueUserAPC, 12
@Kernel RaiseException, 16
@Kernel ReadFile, 20
@Kernel ReleaseMutex, 4
@Kernel ReleaseSemaphore, 12
@Kernel RemoveDirectoryA, 4
@Kernel ResetEvent, 4
@Kernel ResumeThread, 4
@Kernel RtlFillMemory, 12
@Kernel RtlMoveMemory, 12
@Kernel RtlUnwind, 16
@Kernel RtlZeroMemory, 8
@Kernel SearchPathA, 24
@Kernel SetCurrentDirectoryA, 4
@Kernel SetEnvironmentVariableA, 8
@Kernel SetErrorMode, 4
@Kernel SetEvent, 4
@Kernel SetFilePointer, 16
@Kernel SetFileTime, 16
@Kernel SetHandleCount, 4
@Kernel SetLastError, 4
@Kernel SetPriorityClass, 8
@Kernel SetStdHandle, 8
@Kernel SetThreadPriority, 8
@Kernel SetUnhandledExceptionFilter, 4
@Kernel SetWaitableTimer, 24
@Kernel SizeofResource, 8
@Kernel Sleep, 4
@Kernel SuspendThread, 4
@Kernel SwitchToThread, 0
@Kernel SystemTimeToFileTime, 8
@Kernel TerminateProcess, 8
@Kernel TerminateThread, 8
@Kernel TlsAlloc, 0
@Kernel TlsFree, 4
@Kernel TlsGetValue, 4
@Kernel TlsSetValue, 8
@Kernel UnmapViewOfFile, 4
@Kernel VirtualAlloc, 16
@Kernel VirtualFree, 12
@Kernel VirtualLock, 8
@Kernel VirtualProtect, 16
@Kernel VirtualQuery, 12
@Kernel WaitForSingleObject, 8
@Kernel WaitForMultipleObjects, 16
@Kernel WideCharToMultiByte, 32
@Kernel WinExec, 8
@Kernel WriteFile, 20
@Kernel WritePrivateProfileStringA, 16
@Kernel _lcreat, 8
@Kernel _llseek, 12
@Kernel _lopen, 8
@Kernel _lclose, 4
@Kernel _lread, 12
@Kernel _lwrite, 12
@Kernel lstrcat, 8
@Kernel lstrcatA, 8
@Kernel lstrcmp, 8
@Kernel lstrcmpA, 8
@Kernel lstrcmpi, 8
@Kernel lstrcmpiA, 8
@Kernel lstrcpy, 8
@Kernel lstrcpyA, 8
@Kernel lstrcpyn, 12
@Kernel lstrcpynA, 12
@Kernel lstrcpynW, 12
@Kernel lstrlen, 4
@Kernel lstrlenA, 4
@Kernel lstrlenW, 4


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
