package winex
import win32 "core:sys/windows"

foreign import one_core "system:OneCore.lib"

MEM_REPLACE_PLACEHOLDER  :: 0x00004000
MEM_RESERVE_PLACEHOLDER  :: 0x00040000
MEM_PRESERVE_PLACEHOLDER :: 0x00000002

MEM_EXTENDED_PARAMETER_TYPE_BITS :: 8

MEM_EXTENDED_PARAMETER :: struct {
    using DUMMYSTRUCTNAME: bit_field win32.DWORD64 {
			Type:        win32.DWORD64 |  MEM_EXTENDED_PARAMETER_TYPE_BITS,
			Reserved:    win32.DWORD64 |  64 - MEM_EXTENDED_PARAMETER_TYPE_BITS,
	},
	using DUMMYUNIONNAME: struct #raw_union {
		ULong64: win32.DWORD64,
		Pointe:  win32.PVOID,
		Size :   win32.SIZE_T,
        Handle:  win32.HANDLE,
        ULong:   win32.DWORD,
	},
}

PMEM_EXTENDED_PARAMETER :: ^MEM_EXTENDED_PARAMETER

@(default_calling_convention="system")
foreign one_core {
    VirtualAlloc2 :: proc(
        Process:            win32.HANDLE,
		BaseAddress:        win32.LPVOID,
		Size:               win32.SIZE_T,
		AllocationType:     win32.ULONG,
		PageProtection:     win32.ULONG,
        ExtendedParameters: ^MEM_EXTENDED_PARAMETER,
        ParameterCount:     win32.ULONG,
    ) -> win32.LPVOID ---

    MapViewOfFile3 :: proc(
		FileMappingHandle:  win32.HANDLE,
		ProcessHandle:      win32.HANDLE,
		BaseAddress:        win32.PVOID,
		Offset:             win32.ULONG64,
		ViewSize:           win32.SIZE_T,
		AllocationType:     win32.ULONG,
		PageProtection:     win32.ULONG,
		ExtendedParameters: ^MEM_EXTENDED_PARAMETER,
        ParameterCount:     win32.ULONG,
	) -> win32.PVOID ---
}

