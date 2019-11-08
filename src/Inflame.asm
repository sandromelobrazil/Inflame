format PE console 6.0
entry main

include 'INCLUDE/win32ax.inc'

struct PROCESSENTRY32
       dwSize                  dd ?
       cntUsage                dd ?
       th32ProcessID           dd ?
       th32DefaultHeapID       dd ?
       th32ModuleID            dd ?
       cntThreads              dd ?
       th32ParentProcessID     dd ?
       pcPriClassBase          dd ?
       dwFlags                 dd ?
       szExeFile               dw MAX_PATH dup (?)
ends

struct LARGE_INTEGER
       LowPart                 dd ?
       HighPart                dd ?
ends

struct IMAGE_DOS_HEADER
       e_magic                 dw ?
       e_cblp                  dw ?
       e_cp                    dw ?
       e_crlc                  dw ?
       e_cparhdr               dw ?
       e_minalloc              dw ?
       e_maxalloc              dw ?
       e_ss                    dw ?
       e_sp                    dw ?
       e_csum                  dw ?
       e_ip                    dw ?
       e_cs                    dw ?
       e_lfarlc                dw ?
       e_ovno                  dw ?
       e_res                   rw 4
       e_oemid                 dw ?
       e_oeminfo               dw ?
       e_res2                  rw 10
       e_lfanew                dd ?
ends

struct IMAGE_FILE_HEADER
       Machine                 dw ?
       NumberOfSections        dw ?
       TimeDateStamp           dd ?
       PointerToSymbolTable    dd ?
       NumberOfSymbols         dd ?
       SizeOfOptionalHeader    dw ?
       Characteristics         dw ?
ends

struct IMAGE_DATA_DIRECTORY
       VirtualAddress          dd ?
       Size                    dd ?
ends

struct IMAGE_OPTIONAL_HEADER
       Magic                       dw ?
       MajorLinkerVersion          db ?
       MinorLinkerVersion          db ?
       SizeOfCode                  dd ?
       SizeOfInitializedData       dd ?
       SizeOfUninitializedData     dd ?
       AddressOfEntryPoint         dd ?
       BaseOfCode                  dd ?
       BaseOfData                  dd ?
       ImageBase                   dd ?
       SectionAlignment            dd ?
       FileAlignment               dd ?
       MajorOperatingSystemVersion dw ?
       MinorOperatingSystemVersion dw ?
       MajorImageVersion           dw ?
       MinorImageVersion           dw ?
       MajorSubsystemVersion       dw ?
       MinorSubsystemVersion       dw ?
       Win32VersionValue           dd ?
       SizeOfImage                 dd ?
       SizeOfHeaders               dd ?
       CheckSum                    dd ?
       Subsystem                   dw ?
       DllCharacteristics          dw ?
       SizeOfStackReserve          dd ?
       SizeOfStackCommit           dd ?
       SizeOfHeapReserve           dd ?
       SizeOfHeapCommit            dd ?
       LoaderFlags                 dd ?
       NumberOfRvaAndSizes         dd ?
       DataDirectory               IMAGE_DATA_DIRECTORY
ends

struct IMAGE_NT_HEADERS
       Signature               dd ?
       FileHeader              IMAGE_FILE_HEADER
       OptionalHeader          IMAGE_OPTIONAL_HEADER
ends

section '.text' code executable

proc main
    local pid:DWORD, path:rb MAX_PATH

    cinvoke __getmainargs, argc, argv, env, 0
    cmp [argc], 4
    jne .wrongArgumentCount
    mov esi, [argv]
    lea eax, [path]
    invoke GetFullPathNameA, dword [esi + 8], MAX_PATH, eax, 0
    mov esi, [argv]
    stdcall findProcessId, dword [esi + 12]
    mov [pid], eax

    cinvoke strcmp, dword [esi + 4], <'-loadlibrary', 0>
    test eax, eax
    jnz .skip
    lea eax, [path]
    cinvoke strlen, eax
    inc eax
    lea ebx, [path]
    stdcall loadlibrary, ebx, eax, [pid]
    .skip:
        mov esi, [argv]
        cinvoke strcmp, dword [esi + 4], <'-manual-map', 0>
        test eax, eax
        jnz .wrongInjectionMethod
        lea eax, [path]
        stdcall manualmap, eax, [pid]
    .wrongInjectionMethod:
        stdcall criticalError, <'Wrong injection method!', 0>
    .wrongArgumentCount:
        stdcall criticalError, <'Wrong amount of command line arguments!', 0>

endp

proc findProcessId, name
    local snapshot:DWORD, processEntry:PROCESSENTRY32

    invoke CreateToolhelp32Snapshot, 0x2, 0
    mov [snapshot], eax
    mov [processEntry.dwSize], sizeof.PROCESSENTRY32
    lea eax, [processEntry]
    invoke Process32First, [snapshot], eax
    test eax, eax
    jz .error
    
    .loop1:
        lea eax, [processEntry.szExeFile]
        cinvoke strcmp, eax, [name]
        test eax, eax
        jz .return
        lea eax, [processEntry]
        invoke Process32Next, [snapshot], eax
        test eax, eax
        jnz .loop1

    .error:
        xor eax, eax
        ret

    .return:
        mov eax, [processEntry.th32ProcessID]
        ret
endp

proc loadlibrary, path, pathLength, pid
    local handle:DWORD, allocatedMemory:DWORD

    invoke OpenProcess, PROCESS_VM_WRITE + PROCESS_VM_OPERATION + PROCESS_CREATE_THREAD, FALSE, [pid]
    mov [handle], eax
    invoke VirtualAllocEx, [handle], NULL, [pathLength], MEM_COMMIT + MEM_RESERVE, PAGE_READWRITE
    mov [allocatedMemory], eax
    invoke WriteProcessMemory, [handle], [allocatedMemory], [path], [pathLength], NULL
    invoke CreateRemoteThread, [handle], NULL, 0, [LoadLibraryA], [allocatedMemory], 0, NULL
    invoke WaitForSingleObject, eax, 0xFFFFFFFF
    invoke VirtualFreeEx, [handle], [allocatedMemory], [pathLength], MEM_RELEASE
    invoke CloseHandle, [handle]
    invoke ExitProcess, 0
endp

proc manualmap, path, pid
    cinvoke manualMap, [path], [pid]
    invoke ExitProcess, 0
endp

proc criticalError, message
    cinvoke printf, <'Critical Error: %s', 0>, [message]
    invoke ExitProcess, 0
endp

proc manualmap_2, path
    invoke CreateFileA, [path], GENERIC_READ, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
    mov [fileHandle], eax
    invoke GetFileSizeEx, eax, fileSize
    cinvoke printf, <'File size: %d', 10, 0>, [fileSize.LowPart]

    invoke GetProcessHeap
    test eax, eax
    jz heapFail
    mov [heapHandle], eax
    cinvoke printf, <'Heap handle: %p', 10, 0>, [heapHandle]

    invoke HeapAlloc, [heapHandle], 0, [fileSize.LowPart]
    test eax, eax
    jz heapAllocFail
    mov [heapMemory], eax
    cinvoke printf, <'Heap memory: %p', 10, 0>, eax

    invoke ReadFile, [fileHandle], [heapMemory], [fileSize.LowPart], NULL, NULL
    test eax, eax
    jz readFileFail
    cinvoke printf, <'ReadFile: %d', 10, 0>, eax

    mov eax, [heapMemory]
    xor ebx, ebx
    mov bx, [eax + IMAGE_DOS_HEADER.e_magic]
    cinvoke printf, <'DOS SIGNATURE: 0x%X', 10, 0>, ebx

    mov eax, [heapMemory]
    add eax, [eax + IMAGE_DOS_HEADER.e_lfanew] 
    cinvoke printf, <'Size of Image: %d', 10, 0>, [eax + IMAGE_NT_HEADERS.OptionalHeader.SizeOfImage]

    mov esi, [argv]
    invoke OpenProcess, PROCESS_VM_WRITE + PROCESS_VM_OPERATION + PROCESS_CREATE_THREAD, FALSE, <stdcall findProcessId, dword [esi + 12]>
    test eax, eax
    jz openProcessFail
    mov [processHandle], eax

    invoke HeapFree, [heapHandle], 0, [heapMemory]
    invoke ExitProcess, 0

    heapFail:
        stdcall criticalError, <'Failed to get process heap handle!', 0>
    heapAllocFail:
        stdcall criticalError, <'Failed to allocate heap memory!', 0>
    readFileFail:
        stdcall criticalError, <'Failed to read dll file!', 0>
    openProcessFail:
        stdcall criticalError, <'Failed to open process!', 0>

endp

section '.bss' data readable writable

argc    dd ?
argv    dd ?
env     dd ?
;dllPath rb MAX_PATH
;dllPathLength dd ?
processHandle dd ?
fileSize LARGE_INTEGER ?
heapHandle dd ?
heapMemory dd ?
fileHandle dd ?

section '.idata' data readable import

library kernel32, 'kernel32.dll', \
        msvcrt, 'msvcrt.dll', \
        Inflame, 'Inflame.dll'

import kernel32, \
       CloseHandle, 'CloseHandle', \
       CreateFileA, 'CreateFileA', \
       CreateRemoteThread, 'CreateRemoteThread', \
       CreateToolhelp32Snapshot, 'CreateToolhelp32Snapshot', \
       ExitProcess, 'ExitProcess', \
       GetFileSizeEx, 'GetFileSizeEx', \
       GetFullPathNameA, 'GetFullPathNameA', \
       GetProcAddress, 'GetProcAddress', \
       GetProcessHeap, 'GetProcessHeap', \
       HeapAlloc, 'HeapAlloc', \
       HeapFree, 'HeapFree', \
       LoadLibraryA, 'LoadLibraryA', \
       OpenProcess, 'OpenProcess', \
       Process32First, 'Process32First', \
       Process32Next, 'Process32Next', \
       ReadFile, 'ReadFile', \
       VirtualAllocEx, 'VirtualAllocEx', \
       VirtualFreeEx, 'VirtualFreeEx', \
       WaitForSingleObject, 'WaitForSingleObject', \   
       WriteProcessMemory, 'WriteProcessMemory'

import msvcrt, \
       atoi, 'atoi', \
       getchar, 'getchar', \
       __getmainargs, '__getmainargs', \
       printf, 'printf', \
       strcmp, 'strcmp', \
       strlen, 'strlen'

import Inflame, \
       manualMap, 'manualMap'
