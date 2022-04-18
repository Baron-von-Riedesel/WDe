
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

FILE_ATTRIBUTE_READONLY             EQU 00000001h
FILE_ATTRIBUTE_HIDDEN               EQU 00000002h
FILE_ATTRIBUTE_SYSTEM               EQU 00000004h
FILE_ATTRIBUTE_DIRECTORY            EQU 00000010h
FILE_ATTRIBUTE_ARCHIVE              EQU 00000020h
FILE_ATTRIBUTE_ENCRYPTED            EQU 00000040h
FILE_ATTRIBUTE_NORMAL               EQU 00000080h
FILE_ATTRIBUTE_TEMPORARY            EQU 00000100h

GENERIC_READ      equ 80000000h
GENERIC_WRITE     equ 40000000h

CREATE_NEW        equ 1  ; fails if file already exists
CREATE_ALWAYS     equ 2  ; if file exists, it will be overwritten
OPEN_EXISTING     equ 3  ; fails if file doesn't exist
OPEN_ALWAYS       equ 4  ; creates file if it doesn't exist
TRUNCATE_EXISTING equ 5  ; fails if file doesn't exist. will be truncated

FILE_SHARE_READ     EQU 00000001h
FILE_SHARE_WRITE    EQU 00000002h
FILE_SHARE_DELETE   EQU 00000004h

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
Cylinders   dq ?
MediaType   dd ?
TracksPerCylinder   DWORD ?
SectorsPerTrack DWORD ?
BytesPerSector  DWORD ?
DISK_GEOMETRY ends

DISK_PARTITION_INFO struct
SizeOfPartitionInfo DWORD ?
PartitionStyle      DWORD ?
union 
struct Mbr
Signature           DWORD ?
CheckSum            DWORD ?
ends
struct Gpt
DiskId              db 16 dup (?)
ends
ends
DISK_PARTITION_INFO ends

DISK_INT13_INFO struct 4
DriveSelect     WORD ?
MaxCylinders    DWORD ?
SectorsPerTrack WORD ?
MaxHeads        WORD ?
NumberDrives    WORD ?
DISK_INT13_INFO ends

DISK_EX_INT13_INFO struct 8
ExBufferSize    WORD ?      ;+0
ExFlags         WORD ?      ;+2
ExCylinders     DWORD ?     ;+4
ExHeads         DWORD ?
ExSectorsPerTrack DWORD ?   ;+12
ExSectorsPerDrive QWORD ?   ;+16
ExSectorSize    WORD ?      ;+24
ExReserved      WORD ?
DISK_EX_INT13_INFO ends

DISK_DETECTION_INFO struct
SizeOfDetectInfo    DWORD ?         ;+0 
DetectionType       DWORD ?         ;+4
union
struct
Int13       DISK_INT13_INFO <>      ;+8, size 16
ExInt13     DISK_EX_INT13_INFO <>   ;+24, size 32
ends
ends
DISK_DETECTION_INFO ends

DISK_GEOMETRY_EX struct 8
Geometry    DISK_GEOMETRY <>
DiskSize    dq ?
            DISK_PARTITION_INFO <>
            DISK_DETECTION_INFO <>
DISK_GEOMETRY_EX ends


ifdef __JWASM__
    option dllimport:<kernel32.dll>
endif

AddAtomA                    proto stdcall :ptr byte
Beep                        proto stdcall :dword, :dword
CancelWaitableTimer         proto stdcall :dword
CloseHandle                 proto stdcall :dword
CompareStringA              proto stdcall :DWORD, :DWORD, :ptr BYTE, :DWORD, :ptr BYTE, :DWORD
CompareStringW              proto stdcall :DWORD, :DWORD, :ptr WORD, :DWORD, :ptr WORD, :DWORD
CopyFileA                   proto stdcall :ptr BYTE, :ptr BYTE, :DWORD
CreateDirectoryA            proto stdcall :ptr BYTE, :dword
CreateDirectoryExA          proto stdcall :ptr BYTE, :ptr BYTE, :ptr
CreateDirectoryW            proto stdcall :ptr WORD, :dword
CreateEventA                proto stdcall :dword, :dword, :dword, :ptr BYTE
CreateFileA                 proto stdcall :dword, :dword, :dword, :dword, :dword, :dword, :dword
CreateFileMappingA          proto stdcall :dword, :dword, :dword, :dword, :dword, :ptr BYTE
CreateMutexA                proto stdcall :dword, :dword, :ptr BYTE
CreateMutexW                proto stdcall :dword, :dword, :ptr WORD
CreateProcessA              proto stdcall :ptr BYTE, :ptr BYTE, :dword, :dword, :dword, :dword, :ptr , :ptr BYTE, :ptr STARTUPINFOA, :ptr PROCESS_INFORMATION
CreateSemaphoreA            proto stdcall :dword, :dword, :dword, :dword
CreateThread                proto stdcall :dword, :dword, :dword, :dword, :dword, :dword
CreateWaitableTimerA        proto stdcall :dword, :dword, :ptr BYTE
DebugBreak                  proto stdcall
DeleteAtom                  proto stdcall :dword
DeleteCriticalSection       proto stdcall :ptr CRITICAL_SECTION
DeleteFileA                 proto stdcall :dword
DeviceIoControl             proto stdcall :dword, :dword, :ptr, :dword, :ptr, :dword, :ptr dword, :dword
DisableThreadLibraryCalls   proto stdcall :dword
DosDateTimeToFileTime       proto stdcall :DWORD, :DWORD, :ptr FILETIME
DuplicateHandle             proto stdcall :dword, :dword, :dword, :dword, :dword, :dword, :dword
EnterCriticalSection        proto stdcall :ptr CRITICAL_SECTION
EnumResourceLanguagesA      proto stdcall :dword, :ptr BYTE, :ptr BYTE, :dword, :dword
EnumResourceNamesA          proto stdcall :dword, :ptr BYTE, :dword, :dword
EnumResourceTypesA          proto stdcall :dword, :dword, :dword
ExitProcess                 proto stdcall :dword
ExitThread                  proto stdcall :dword
ExpandEnvironmentStringsA   proto stdcall :ptr BYTE, :ptr BYTE, :dword
FatalAppExitA               proto stdcall :dword, :ptr BYTE
FileTimeToDosDateTime       proto stdcall :ptr FILETIME, :ptr WORD, :ptr WORD
FileTimeToSystemTime        proto stdcall :ptr FILETIME, :ptr SYSTEMTIME
FindAtomA                   proto stdcall :ptr byte
FindClose                   proto stdcall :dword
FindFirstFileA              proto stdcall :ptr BYTE, :ptr WIN32_FIND_DATAA
FindFirstFileW              proto stdcall :ptr WORD, :ptr WIN32_FIND_DATAW
FindNextFileA               proto stdcall :dword, :ptr WIN32_FIND_DATAA
FindNextFileW               proto stdcall :dword, :ptr WIN32_FIND_DATAW
FindResourceA               proto stdcall :dword, :dword, :dword
FindResourceExA             proto stdcall :dword, :dword, :dword, :dword
FindResourceW               proto stdcall :dword, :ptr WORD, :ptr word
FlushFileBuffers            proto stdcall :dword
FlushViewOfFile             proto stdcall :ptr, :dword
FormatMessageA              proto stdcall :dword, :ptr, :DWORD, :DWORD, :ptr BYTE, :DWORD, :ptr
FreeEnvironmentStringsA     proto stdcall :dword
FreeEnvironmentStringsW     proto stdcall :dword
FreeLibrary                 proto stdcall :dword
GetACP                      proto stdcall
GetAtomNameA                proto stdcall :dword, :ptr byte, :dword
GetCommandLineA             proto stdcall
GetComputerNameA            proto stdcall :ptr BYTE, :ptr DWORD
GetCurrentDirectoryA        proto stdcall :dword, :ptr byte
GetCurrentProcess           proto stdcall
GetCurrentProcessId         proto stdcall
GetCurrentThread            proto stdcall
GetCurrentThreadId          proto stdcall
GetDateFormatA              proto stdcall lcid:DWORD, dwFlags:DWORD, pDate:ptr SYSTEMTIME,lpFormat:ptr BYTE, lpDateStr:ptr BYTE, cchDate:DWORD
GetDiskFreeSpaceA           proto stdcall :ptr BYTE, :ptr dword, :ptr dword, :ptr dword, :ptr dword
GetDiskFreeSpaceW           proto stdcall :ptr WORD, :ptr dword, :ptr dword, :ptr dword, :ptr dword
GetDriveTypeA               proto stdcall :ptr BYTE
GetDriveTypeW               proto stdcall :ptr WORD
GetEnvironmentStrings       proto stdcall
GetEnvironmentStringsA      proto stdcall
GetEnvironmentStringsW      proto stdcall
GetEnvironmentVariableA     proto stdcall :ptr BYTE, :ptr BYTE, :dword
GetExitCodeThread           proto stdcall :dword, :ptr dword
GetFileAttributesA          proto stdcall :ptr byte
GetFileAttributesExA        proto stdcall :ptr BYTE, :DWORD, :ptr WIN32_FILE_ATTRIBUTE_DATA
GetFileSize                 proto stdcall :dword, :ptr dword
GetFileTime                 proto stdcall :dword, :ptr FILETIME, :ptr FILETIME, :ptr FILETIME
GetFileType                 proto stdcall :dword
GetFullPathNameA            proto stdcall :ptr BYTE, :DWORD, :ptr BYTE, :ptr ptr BYTE
GetFullPathNameW            proto stdcall :ptr WORD, :DWORD, :ptr WORD, :ptr ptr WORD
GetLastError                proto stdcall
GetLocaleInfoA              proto stdcall :dword, :dword, :ptr BYTE, :dword
GetLocalTime                proto stdcall :ptr SYSTEMTIME
GetLongPathNameA            proto stdcall :ptr byte, :ptr byte, :DWORD
GetModuleFileNameA          proto stdcall :dword, :ptr byte, :dword
GetModuleHandleA            proto stdcall :ptr BYTE
GetOEMCP                    proto stdcall
GetPrivateProfileStringA    proto stdcall :ptr BYTE, :ptr BYTE, :ptr BYTE, :ptr BYTE, :DWORD, :ptr BYTE
GetProcAddress              proto stdcall :DWORD, :DWORD
GetProcessHeap              proto stdcall
GetShortPathNameA           proto stdcall :ptr byte, :ptr byte, :DWORD
GetStartupInfoA             proto stdcall :ptr STARTUPINFOA
GetStdHandle                proto stdcall :dword
GetSystemDirectoryA         proto stdcall :ptr byte, :DWORD
GetSystemTime               proto stdcall :ptr SYSTEMTIME
GetSystemTimeAsFileTime     proto stdcall :ptr FILETIME
GetTempFileNameA            proto stdcall :ptr BYTE, :ptr BYTE, :DWORD, :ptr BYTE
GetTempPathA                proto stdcall :DWORD, :ptr BYTE
GetTickCount                proto stdcall
GetUserDefaultLCID          proto stdcall
GetVersion                  proto stdcall
GetVersionExA               proto stdcall :ptr OSVERSIONINFO
GlobalAddAtomA              proto stdcall :ptr BYTE
GlobalAlloc                 proto stdcall :dword, :dword
GlobalFree                  proto stdcall :dword
GlobalGetAtomNameA          proto stdcall :dword, :ptr BYTE, :dword
GlobalMemoryStatus          proto stdcall :ptr MEMORYSTATUS
GlobalSize                  proto stdcall :dword
HeapAlloc                   proto stdcall :dword, :dword, :dword
HeapCreate                  proto stdcall :dword, :dword, :dword
HeapDestroy                 proto stdcall :dword
HeapFree                    proto stdcall :dword, :dword, :dword
HeapReAlloc                 proto stdcall :dword, :dword, :dword, :dword
HeapSize                    proto stdcall :dword, :dword, :dword
HeapValidate                proto stdcall :dword, :dword, :dword
HeapWalk                    proto stdcall :dword, :ptr PROCESS_HEAP_ENTRY
InitializeCriticalSection   proto stdcall :ptr CRITICAL_SECTION
InterlockedDecrement        proto stdcall :dword
InterlockedExchange         proto stdcall :ptr DWORD, :DWORD
InterlockedIncrement        proto stdcall :dword
IsBadCodePtr                proto stdcall :DWORD
IsBadReadPtr                proto stdcall :DWORD, :DWORD
IsBadWritePtr               proto stdcall :DWORD, :DWORD
IsDebuggerPresent           proto stdcall
IsProcessorFeaturePresent   proto stdcall :dword
LeaveCriticalSection        proto stdcall :ptr CRITICAL_SECTION
LoadLibraryA                proto stdcall :ptr BYTE
LoadLibraryExA              proto stdcall :ptr BYTE, :DWORD, :DWORD
LoadResource                proto stdcall :dword, :dword
LocalAlloc                  proto stdcall :dword, :dword
LocalFileTimeToFileTime     proto stdcall :ptr FILETIME, :ptr FILETIME
LocalFree                   proto stdcall :dword
MapViewOfFile               proto stdcall :dword, :dword, :dword, :dword, :dword
MapViewOfFileEx             proto stdcall :dword, :dword, :dword, :dword, :dword, :ptr
MoveFileA                   proto stdcall :ptr BYTE, :ptr BYTE
MoveFileExA                 proto stdcall :ptr BYTE, :ptr BYTE, :dword
MultiByteToWideChar         proto stdcall :DWORD, :DWORD, :ptr BYTE, :DWORD, :ptr WORD, :DWORD
OpenEventA                  proto stdcall :dword, :dword, :ptr BYTE
OpenFile                    proto stdcall :ptr byte, :ptr OFSTRUCT, :dword
OpenFileMappingA            proto stdcall :dword, :dword, :ptr BYTE
OpenMutexA                  proto stdcall :dword, :dword, :dword
OpenProcess                 proto stdcall :dword, :dword, :dword
OpenSemaphoreA              proto stdcall :dword, :dword, :dword
OutputDebugStringA          proto stdcall :ptr BYTE
PulseEvent                  proto stdcall :dword
QueueUserAPC                proto stdcall :dword, :dword, :dword
RaiseException              proto stdcall :DWORD, :DWORD, :DWORD, :ptr
ReadFile                    proto stdcall :dword, :dword, :dword, :ptr dword, :ptr OVERLAPPED
ReleaseMutex                proto stdcall :dword
ReleaseSemaphore            proto stdcall :dword, :dword, :dword
RemoveDirectoryA            proto stdcall :ptr BYTE
RemoveDirectoryW            proto stdcall :ptr WORD
ResetEvent                  proto stdcall :dword
ResumeThread                proto stdcall :dword
RtlFillMemory               proto stdcall :ptr BYTE, :DWORD, :dword
RtlMoveMemory               proto stdcall :ptr BYTE, :ptr BYTE, :dword
RtlUnwind                   proto stdcall :ptr EXCEPTION_REGISTRATION, :dword, :ptr EXCEPTION_RECORD, :dword
RtlZeroMemory               proto stdcall :ptr BYTE, :dword
SearchPathA                 proto stdcall :ptr BYTE, :ptr BYTE, :ptr BYTE, :DWORD, :ptr BYTE, :ptr ptr BYTE
SetCurrentDirectoryA        proto stdcall :ptr BYTE
SetCurrentDirectoryW        proto stdcall :ptr WORD
SetEndOfFile                proto stdcall :dword
SetEnvironmentVariableA     proto stdcall :ptr BYTE, :ptr BYTE
SetErrorMode                proto stdcall :dword
SetEvent                    proto stdcall :dword
SetFileAttributesA          proto stdcall :ptr byte, :dword
SetFilePointer              proto stdcall :dword, :dword, :dword, :dword
SetFilePointerEx            proto stdcall :dword, :qword, :ptr QWORD, :dword
SetFileTime                 proto stdcall :dword, :ptr FILETIME, :ptr FILETIME, :ptr FILETIME
SetHandleCount              proto stdcall :dword
SetLastError                proto stdcall :dword
SetPriorityClass            proto stdcall :dword, :dword
SetStdHandle                proto stdcall :dword, :dword
SetThreadPriority           proto stdcall :dword, :dword
SetUnhandledExceptionFilter proto stdcall :ptr
SetWaitableTimer            proto stdcall :dword, :ptr QWORD, :dword, :dword, :dword, :dword
SizeofResource              proto stdcall :dword, :dword
Sleep                       proto stdcall :dword
SuspendThread               proto stdcall :dword
SwitchToThread              proto stdcall
SystemTimeToFileTime        proto stdcall :ptr SYSTEMTIME, :ptr FILETIME
TerminateProcess            proto stdcall :dword, :dword
TerminateThread             proto stdcall :dword, :dword
TlsAlloc                    proto stdcall
TlsFree                     proto stdcall :dword
TlsGetValue                 proto stdcall :dword
TlsSetValue                 proto stdcall :dword, :dword
UnmapViewOfFile             proto stdcall :ptr
VirtualAlloc                proto stdcall :dword, :dword, :dword, :dword
VirtualFree                 proto stdcall :dword, :dword, :dword
VirtualLock                 proto stdcall :dword, :dword
VirtualProtect              proto stdcall :dword, :dword, :dword, :dword
VirtualQuery                proto stdcall :dword, :ptr MEMORY_BASIC_INFORMATION, :dword
WaitForMultipleObjects      proto stdcall :dword, :ptr dword, :dword, :dword
WaitForSingleObject         proto stdcall :dword, :dword
WideCharToMultiByte         proto stdcall :DWORD, :DWORD, :ptr WORD, :DWORD, :ptr BYTE, :DWORD, :DWORD, :DWORD
WinExec                     proto stdcall :ptr BYTE, :DWORD
WriteFile                   proto stdcall :dword, :dword, :dword, :ptr dword, :ptr OVERLAPPED
WritePrivateProfileStringA  proto stdcall lpAppName:ptr BYTE, lpKeyName:ptr BYTE, lpString:ptr BYTE, lpFileName:ptr BYTE
_lclose                     proto stdcall :dword
_lcreat                     proto stdcall :dword, :dword
_llseek                     proto stdcall :dword, :dword, :dword
_lopen                      proto stdcall :dword, :dword
_lread                      proto stdcall :dword, :dword, :dword
_lwrite                     proto stdcall :dword, :dword, :dword
lstrcat                     proto stdcall :ptr BYTE, :ptr BYTE
lstrcatA                    proto stdcall :ptr BYTE, :ptr BYTE
lstrcatW                    proto stdcall :ptr WORD, :ptr WORD
lstrcmp                     proto stdcall :ptr BYTE, :ptr BYTE
lstrcmpA                    proto stdcall :ptr BYTE, :ptr BYTE
lstrcmpi                    proto stdcall :ptr BYTE, :ptr BYTE
lstrcmpiA                   proto stdcall :ptr BYTE, :ptr BYTE
lstrcpy                     proto stdcall :ptr BYTE, :ptr BYTE
lstrcpyA                    proto stdcall :ptr BYTE, :ptr BYTE
lstrcpyn                    proto stdcall :ptr BYTE, :ptr BYTE, :DWORD
lstrcpynA                   proto stdcall :ptr BYTE, :ptr BYTE, :DWORD
lstrcpynW                   proto stdcall :ptr WORD, :ptr WORD, :DWORD
lstrlen                     proto stdcall :ptr BYTE
lstrlenA                    proto stdcall :ptr BYTE
lstrlenW                    proto stdcall :ptr WORD

GetNumberOfConsoleMouseButtons proto stdcall :ptr DWORD

ifdef __JWASM__
    option dllimport:none
endif

ZeroMemory  textequ <RtlZeroMemory>
FillMemory  textequ <RtlFillMemory>
CopyMemory  textequ <RtlMoveMemory>

