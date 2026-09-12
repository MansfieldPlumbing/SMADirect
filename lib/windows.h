/**
 * windows.h - SMADirect Windows ABI Header
 *
 * CRYPTOGRAPHIC PROVENANCE MANIFEST:
 * -------------------------------------------------------------------------
 * DONOR 1: Windows SDK 10.0.26100.0 (um/winnt.h)
 *   PATH:   Windows SDK 10.0.26100.0 / um/winnt.h
 *   SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF
 *
 * DONOR 2: Windows SDK 10.0.26100.0 (um/winuser.h)
 *   PATH:   Windows SDK 10.0.26100.0 / um/winuser.h
 *   SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C
 *
 * DONOR 3: Windows SDK 10.0.26100.0 (um/d2d1.h)
 *   PATH:   Windows SDK 10.0.26100.0 / um/d2d1.h
 *   SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5
 *
 * DONOR 4: Windows SDK 10.0.26100.0 (um/dwrite.h)
 *   PATH:   Windows SDK 10.0.26100.0 / um/dwrite.h
 *   SHA256: E991BB9037949BB1C03BDF34EEE04A8DD8C0578D2504D41913A711CE77C697DE
 *
 * DONOR 5: .NET Runtime CoreCLR (src/coreclr/inc/corjit.h)
 *   PATH:   dotnet/runtime / src/coreclr/inc/corjit.h
 *   SHA256: 81D3B8BA895A1D13AC251451BEA1BD76780B58259A4E43B2CC3332E7FE44DD3D
 *
 * DONOR 6: .NET Runtime CoreCLR (src/coreclr/inc/corinfo.h)
 *   PATH:   dotnet/runtime / src/coreclr/inc/corinfo.h
 *   SHA256: C6EC58DB730DE6DC1864481E9734384E3AB137EBAC2A6EDD04228A43B9DBE30E
 * -------------------------------------------------------------------------
 */

#ifndef NATIVESMA_WINDOWS_H
#define NATIVESMA_WINDOWS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* SECTION 1: BASE WIN32 TYPES                                               */
/* ========================================================================= */

/* DONOR: winnt.h:268 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
typedef void*           HANDLE;
typedef void*           HWND;
typedef void*           HDC;
typedef void*           HINSTANCE;
typedef void*           HICON;
typedef void*           HCURSOR;
typedef void*           HBRUSH;
typedef void*           HMENU;
typedef void*           LPARAM;
typedef void*           WPARAM;
typedef void*           LRESULT;
typedef uint32_t        DWORD;
typedef int32_t         BOOL;
typedef uint8_t         BYTE;
typedef uint16_t        WORD;
typedef float           FLOAT;
typedef wchar_t         WCHAR;
typedef const WCHAR*    LPCWSTR;

/* DONOR: winuser.h:1777 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
typedef LRESULT (*WNDPROC)(HWND hwnd, uint32_t msg, WPARAM wparam, LPARAM lparam);

/* ========================================================================= */
/* SECTION 2: PE/COFF BINARY SPECIFICATION                                   */
/* ========================================================================= */

/* DONOR: winnt.h:19641 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DOS_SIGNATURE                     0x5A4D      /* MZ */

/* DONOR: winnt.h:19645 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_NT_SIGNATURE                      0x00004550  /* PE00 */

/* DONOR: winnt.h:19832 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_FILE_MACHINE_AMD64                0x8664

/* DONOR: winnt.h:19789 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_FILE_EXECUTABLE_IMAGE             0x0002

/* DONOR: winnt.h:19793 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_FILE_LARGE_ADDRESS_AWARE          0x0020

/* DONOR: winnt.h:19946 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_NT_OPTIONAL_HDR64_MAGIC           0x020B

/* DONOR: winnt.h:19996 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_SUBSYSTEM_WINDOWS_GUI             2

/* DONOR: winnt.h:19997 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_SUBSYSTEM_WINDOWS_CUI             3

/* DONOR: winnt.h:20017 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE   0x0040

/* DONOR: winnt.h:20019 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DLLCHARACTERISTICS_NX_COMPAT      0x0100

/* DONOR: winnt.h:20026 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE 0x8000

/* DONOR: winnt.h:20030 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DIRECTORY_ENTRY_EXPORT            0

/* DONOR: winnt.h:20031 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DIRECTORY_ENTRY_IMPORT            1

/* DONOR: winnt.h:20032 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DIRECTORY_ENTRY_RESOURCE          2

/* DONOR: winnt.h:20033 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DIRECTORY_ENTRY_EXCEPTION         3

/* DONOR: winnt.h:20035 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DIRECTORY_ENTRY_BASERELOC         5

/* DONOR: winnt.h:20043 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_DIRECTORY_ENTRY_IAT               12

/* DONOR: winnt.h:20127 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_SCN_CNT_CODE                      0x00000020

/* DONOR: winnt.h:20128 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_SCN_CNT_INITIALIZED_DATA          0x00000040

/* DONOR: winnt.h:20169 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_SCN_MEM_EXECUTE                   0x20000000

/* DONOR: winnt.h:20170 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_SCN_MEM_READ                      0x40000000

/* DONOR: winnt.h:20171 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#define IMAGE_SCN_MEM_WRITE                     0x80000000

/* PE layout defaults (from PE/COFF specification, Microsoft PE Format rev 11) */
#define PE_DEFAULT_IMAGE_BASE_AMD64             0x140000000
#define PE_DEFAULT_SECTION_ALIGNMENT            0x1000
#define PE_DEFAULT_FILE_ALIGNMENT               0x0200
#define PE_DEFAULT_STACK_RESERVE                0x100000
#define PE_DEFAULT_STACK_COMMIT                 0x1000
#define PE_DEFAULT_HEAP_RESERVE                 0x100000
#define PE_DEFAULT_HEAP_COMMIT                  0x1000
#define PE_DEFAULT_NUMBER_OF_RVA_AND_SIZES      16
#define PE_MAJOR_SUBSYSTEM_VERSION              6
#define PE_MINOR_SUBSYSTEM_VERSION              0

/* DONOR: sdk/d2d1.h:3341 | SHA256: 06152247-6f50-465a-9245-118bfd3b6007 */
#define IID_ID2D1Factory                        "06152247-6f50-465a-9245-118bfd3b6007"

/* DONOR: sdk/dwrite.h:4704 | SHA256: b859ee5a-d838-4b5b-a2e8-1adc7d93db48 */
#define IID_IDWriteFactory                      "b859ee5a-d838-4b5b-a2e8-1adc7d93db48"

/* DONOR: winnt.h:19659 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#pragma pack(push, 2)
typedef struct _IMAGE_DOS_HEADER {
    WORD   e_magic;                     /* 0x5A4D */
    WORD   e_cblp;
    WORD   e_cp;
    WORD   e_crlc;
    WORD   e_cparhdr;
    WORD   e_minalloc;
    WORD   e_maxalloc;
    WORD   e_ss;
    WORD   e_sp;
    WORD   e_csum;
    WORD   e_ip;
    WORD   e_cs;
    WORD   e_lfarlc;
    WORD   e_ovno;
    WORD   e_res[4];
    WORD   e_oemid;
    WORD   e_oeminfo;
    WORD   e_res2[10];
    int32_t e_lfanew;
} IMAGE_DOS_HEADER;
#pragma pack(pop)

/* DONOR: winnt.h:19776 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
#pragma pack(push, 4)
typedef struct _IMAGE_FILE_HEADER {
    WORD    Machine;                    /* 0x8664 */
    WORD    NumberOfSections;
    DWORD   TimeDateStamp;
    DWORD   PointerToSymbolTable;
    DWORD   NumberOfSymbols;
    WORD    SizeOfOptionalHeader;
    WORD    Characteristics;            /* 0x0022 */
} IMAGE_FILE_HEADER;

/* DONOR: winnt.h:19894 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
typedef struct _IMAGE_DATA_DIRECTORY {
    DWORD   VirtualAddress;
    DWORD   Size;
} IMAGE_DATA_DIRECTORY;

/* DONOR: winnt.h:19912 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
typedef struct _IMAGE_OPTIONAL_HEADER64 {
    WORD        Magic;                  /* 0x020B */
    BYTE        MajorLinkerVersion;
    BYTE        MinorLinkerVersion;
    DWORD       SizeOfCode;
    DWORD       SizeOfInitializedData;
    DWORD       SizeOfUninitializedData;
    DWORD       AddressOfEntryPoint;
    DWORD       BaseOfCode;
    uint64_t    ImageBase;              /* Default: 0x140000000 */
    DWORD       SectionAlignment;       /* 4096 (0x1000) */
    DWORD       FileAlignment;          /* 512  (0x0200) */
    WORD        MajorOperatingSystemVersion;
    WORD        MinorOperatingSystemVersion;
    WORD        MajorImageVersion;
    WORD        MinorImageVersion;
    WORD        MajorSubsystemVersion;
    WORD        MinorSubsystemVersion;
    DWORD       Win32VersionValue;
    DWORD       SizeOfImage;
    DWORD       SizeOfHeaders;
    DWORD       CheckSum;
    WORD        Subsystem;              /* 2: GUI, 3: CUI */
    WORD        DllCharacteristics;     /* 0x8120 */
    uint64_t    SizeOfStackReserve;
    uint64_t    SizeOfStackCommit;
    uint64_t    SizeOfHeapReserve;
    uint64_t    SizeOfHeapCommit;
    DWORD       LoaderFlags;
    DWORD       NumberOfRvaAndSizes;
    IMAGE_DATA_DIRECTORY DataDirectory[16];
} IMAGE_OPTIONAL_HEADER64;

/* DONOR: winnt.h:20099 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
typedef struct _IMAGE_SECTION_HEADER {
    BYTE    Name[8];
    union {
        DWORD PhysicalAddress;
        DWORD VirtualSize;
    } Misc;
    DWORD   VirtualAddress;
    DWORD   SizeOfRawData;
    DWORD   PointerToRawData;
    DWORD   PointerToRelocations;
    DWORD   PointerToLinenumbers;
    WORD    NumberOfRelocations;
    WORD    NumberOfLinenumbers;
    DWORD   Characteristics;
} IMAGE_SECTION_HEADER;

/* DONOR: winnt.h:21083 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
typedef struct _IMAGE_IMPORT_DESCRIPTOR {
    union {
        DWORD   Characteristics;
        DWORD   OriginalFirstThunk;     /* RVA to ILT */
    } DUMMYUNIONNAME;
    DWORD   TimeDateStamp;
    DWORD   ForwarderChain;
    DWORD   Name;                       /* RVA to DLL Name */
    DWORD   FirstThunk;                 /* RVA to IAT */
} IMAGE_IMPORT_DESCRIPTOR;

/* DONOR: winnt.h:20986 | SHA256: 8693F0AD4ADA355C912D40CA41CE929B480E92291BDA2F9227ACF56736BFFBFF */
typedef struct _IMAGE_THUNK_DATA64 {
    union {
        uint64_t ForwarderString;
        uint64_t Function;
        uint64_t Ordinal;
        uint64_t AddressOfData;         /* RVA to IMAGE_IMPORT_BY_NAME */
    } u1;
} IMAGE_THUNK_DATA64;
#pragma pack(pop)

/* ========================================================================= */
/* SECTION 3: WIN32 WINDOW MANAGEMENT & GDI                                  */
/* ========================================================================= */

/* DONOR: winuser.h:2904 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define CS_VREDRAW                              0x0001

/* DONOR: winuser.h:2905 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define CS_HREDRAW                              0x0002

/* DONOR: winuser.h:2796 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WS_OVERLAPPED                           0x00000000L

/* DONOR: winuser.h:2800 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WS_VISIBLE                              0x10000000L

/* DONOR: winuser.h:2805 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WS_CAPTION                              0x00C00000L

/* DONOR: winuser.h:2810 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WS_SYSMENU                              0x00080000L

/* DONOR: winuser.h:2815 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WS_MINIMIZEBOX                          0x00020000L

/* DONOR: winuser.h:2816 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WS_MAXIMIZEBOX                          0x00010000L

/* DONOR: winuser.h:2827 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WS_OVERLAPPEDWINDOW                     (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | 0x00040000L | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)

/* DONOR: winuser.h:4410 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define CW_USEDEFAULT                           ((int)0x80000000)

/* DONOR: winuser.h:401 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define SW_SHOW                                 5

/* DONOR: winuser.h:9641 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define COLOR_WINDOW                            5

/* DONOR: winuser.h:1986 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_DESTROY                              0x0002

/* DONOR: winuser.h:1988 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_SIZE                                 0x0005

/* DONOR: winuser.h:2005 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_PAINT                                0x000F

/* DONOR: winuser.h:2006 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_CLOSE                                0x0010

/* DONOR: winuser.h:2013 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_ERASEBKGND                           0x0014

/* DONOR: winuser.h:2260 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_MOUSEMOVE                            0x0200

/* DONOR: winuser.h:2263 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_LBUTTONDOWN                          0x0201

/* DONOR: winuser.h:2264 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
#define WM_LBUTTONUP                            0x0202

/* DONOR: winuser.h:1780 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
typedef struct tagWNDCLASSEXW {
    uint32_t    cbSize;                 /* 80 bytes */
    uint32_t    style;
    WNDPROC     lpfnWndProc;
    int32_t     cbClsExtra;
    int32_t     cbWndExtra;
    HINSTANCE   hInstance;
    HICON       hIcon;
    HCURSOR     hCursor;
    HBRUSH      hbrBackground;
    LPCWSTR     lpszMenuName;
    LPCWSTR     lpszClassName;
    HICON       hIconSm;
} WNDCLASSEXW;

/* DONOR: winuser.h:1878 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
typedef struct tagPOINT {
    int32_t x;
    int32_t y;
} POINT;

typedef struct tagMSG {
    HWND        hwnd;
    uint32_t    message;
    WPARAM      wParam;
    LPARAM      lParam;
    DWORD       time;
    POINT       pt;
} MSG;

/* DONOR: winuser.h:3189 | SHA256: 014E26F0041535EBCC53C7B46F1D280F66283EC5EB4612B4E82F5B0F6C0D428C */
typedef struct tagRECT {
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
} RECT;

typedef struct tagPAINTSTRUCT {
    HDC         hdc;
    BOOL        fErase;
    RECT        rcPaint;
    BOOL        fRestore;
    BOOL        fIncUpdate;
    BYTE        rgbReserved[32];
} PAINTSTRUCT;

/* ========================================================================= */
/* SECTION 4: DIRECT2D 1.1 HARDWARE PRESENTATION                             */
/* ========================================================================= */

/* DONOR: d2d1.h:288 | SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5 */
typedef struct D2D_COLOR_F {
    FLOAT r;
    FLOAT g;
    FLOAT b;
    FLOAT a;
} D2D_COLOR_F, D2D1_COLOR_F;

/* DONOR: d2d1.h:284 | SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5 */
typedef struct D2D_RECT_F {
    FLOAT left;
    FLOAT top;
    FLOAT right;
    FLOAT bottom;
} D2D_RECT_F, D2D1_RECT_F;

/* DONOR: d2d1.h:283 | SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5 */
typedef struct D2D_POINT_2F {
    FLOAT x;
    FLOAT y;
} D2D_POINT_2F, D2D1_POINT_2F;

/* DONOR: d2d1.h:287 | SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5 */
typedef struct D2D1_SIZE_U {
    uint32_t width;
    uint32_t height;
} D2D1_SIZE_U;

/* DONOR: d2d1.h:665 | SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5 */
typedef struct D2D1_ROUNDED_RECT {
    D2D1_RECT_F rect;
    FLOAT radiusX;
    FLOAT radiusY;
} D2D1_ROUNDED_RECT;

/* DONOR: d2d1.h:886 | SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5 */
typedef struct D2D1_RENDER_TARGET_PROPERTIES {
    uint32_t type;                      /* D2D1_RENDER_TARGET_TYPE_DEFAULT = 0 */
    uint32_t pixelFormat_format;        /* DXGI_FORMAT_UNKNOWN = 0 */
    uint32_t pixelFormat_alphaMode;     /* D2D1_ALPHA_MODE_UNKNOWN = 0 */
    FLOAT    dpiX;                      /* 0.0f (default 96 DPI) */
    FLOAT    dpiY;                      /* 0.0f */
    uint32_t usage;                     /* D2D1_RENDER_TARGET_USAGE_NONE = 0 */
    uint32_t minLevel;                  /* D2D1_FEATURE_LEVEL_DEFAULT = 0 */
} D2D1_RENDER_TARGET_PROPERTIES;

/* DONOR: d2d1.h:902 | SHA256: FCF7F870ACF11E1509B4CEC31D433602502B77D0A236E417304948A1CE7486A5 */
typedef struct D2D1_HWND_RENDER_TARGET_PROPERTIES {
    HWND hwnd;
    D2D1_SIZE_U pixelSize;
    uint32_t presentOptions;            /* D2D1_PRESENT_OPTIONS_NONE = 0 */
} D2D1_HWND_RENDER_TARGET_PROPERTIES;

/* Direct2D Vtable Offsets (Slots) */
#define D2D_FACTORY_VTABLE_CREATE_HWND_RENDER_TARGET    14
#define D2D_TARGET_VTABLE_CREATE_SOLID_COLOR_BRUSH      8
#define D2D_TARGET_VTABLE_DRAW_RECTANGLE                16
#define D2D_TARGET_VTABLE_FILL_RECTANGLE                17
#define D2D_TARGET_VTABLE_DRAW_ROUNDED_RECTANGLE        18
#define D2D_TARGET_VTABLE_FILL_ROUNDED_RECTANGLE        19
#define D2D_TARGET_VTABLE_DRAW_TEXT                     27
#define D2D_TARGET_VTABLE_CLEAR                         47
#define D2D_TARGET_VTABLE_BEGIN_DRAW                    48
#define D2D_TARGET_VTABLE_END_DRAW                      49

/* ========================================================================= */
/* SECTION 5: DIRECTWRITE HARDWARE TYPOGRAPHY                                */
/* ========================================================================= */

/* DONOR: dwrite.h:171 | SHA256: E991BB9037949BB1C03BDF34EEE04A8DD8C0578D2504D41913A711CE77C697DE */
typedef enum DWRITE_FONT_WEIGHT {
    DWRITE_FONT_WEIGHT_NORMAL = 400,
    DWRITE_FONT_WEIGHT_BOLD   = 700
} DWRITE_FONT_WEIGHT;

/* DONOR: dwrite.h:326 | SHA256: E991BB9037949BB1C03BDF34EEE04A8DD8C0578D2504D41913A711CE77C697DE */
typedef enum DWRITE_FONT_STYLE {
    DWRITE_FONT_STYLE_NORMAL = 0
} DWRITE_FONT_STYLE;

/* DONOR: dwrite.h:264 | SHA256: E991BB9037949BB1C03BDF34EEE04A8DD8C0578D2504D41913A711CE77C697DE */
typedef enum DWRITE_FONT_STRETCH {
    DWRITE_FONT_STRETCH_NORMAL = 5
} DWRITE_FONT_STRETCH;

/* DONOR: dwrite.h:1753 | SHA256: E991BB9037949BB1C03BDF34EEE04A8DD8C0578D2504D41913A711CE77C697DE */
typedef enum DWRITE_TEXT_ALIGNMENT {
    DWRITE_TEXT_ALIGNMENT_LEADING  = 0,
    DWRITE_TEXT_ALIGNMENT_TRAILING = 1,
    DWRITE_TEXT_ALIGNMENT_CENTER   = 2
} DWRITE_TEXT_ALIGNMENT;

/* DirectWrite Vtable Offsets (Slots) */
#define DWRITE_FACTORY_VTABLE_CREATE_TEXT_FORMAT        15

/* ========================================================================= */
/* SECTION 6: RYUJIT COMPILER ABI                                            */
/* ========================================================================= */

/* DONOR: corinfo.h:1717 | SHA256: C6EC58DB730DE6DC1864481E9734384E3AB137EBAC2A6EDD04228A43B9DBE30E */
enum CORINFO_OS {
    CORINFO_WINNT           = 0,
    CORINFO_UNIX            = 1,
    CORINFO_APPLE           = 2,
};

enum CORINFO_RUNTIME_ABI {
    CORINFO_CORECLR_ABI     = 0x200,
    CORINFO_NATIVEAOT_ABI   = 0x300,
};

/* DONOR: corjit.h:33 | SHA256: 81D3B8BA895A1D13AC251451BEA1BD76780B58259A4E43B2CC3332E7FE44DD3D */
enum CorJitResult {
    CORJIT_OK               = 0,
    CORJIT_BADCODE          = 0x80000001,
    CORJIT_OUTOFMEM         = 0x80000002,
    CORJIT_INTERNALERROR    = 0x80000003,
};

/* DONOR: corjit.h:48 | SHA256: 81D3B8BA895A1D13AC251451BEA1BD76780B58259A4E43B2CC3332E7FE44DD3D */
enum CorJitAllocMemFlag {
    CORJIT_ALLOCMEM_HOT_CODE                = 1,
    CORJIT_ALLOCMEM_COLD_CODE               = 2,
    CORJIT_ALLOCMEM_READONLY_DATA           = 4,
    CORJIT_ALLOCMEM_HAS_POINTERS_TO_CODE    = 8,
};

/* DONOR: corjit.h:79 | SHA256: 81D3B8BA895A1D13AC251451BEA1BD76780B58259A4E43B2CC3332E7FE44DD3D */
typedef struct AllocMemChunk {
    uint32_t alignment;
    uint32_t size;
    uint32_t flags;
    uint8_t* block;
    uint8_t* blockRW;
} AllocMemChunk;

/* DONOR: corjit.h:94 | SHA256: 81D3B8BA895A1D13AC251451BEA1BD76780B58259A4E43B2CC3332E7FE44DD3D */
typedef struct AllocMemArgs {
    AllocMemChunk* chunks;
    unsigned       chunksCount;
    uint32_t       xcptnsCount;
} AllocMemArgs;

/* DONOR: corinfo.h:594 | SHA256: C6EC58DB730DE6DC1864481E9734384E3AB137EBAC2A6EDD04228A43B9DBE30E */
enum CorInfoType {
    CORINFO_TYPE_UNDEF      = 0x0,
    CORINFO_TYPE_VOID       = 0x1,
    CORINFO_TYPE_BOOL       = 0x2,
    CORINFO_TYPE_CHAR       = 0x3,
    CORINFO_TYPE_BYTE       = 0x4,
    CORINFO_TYPE_UBYTE      = 0x5,
    CORINFO_TYPE_SHORT      = 0x6,
    CORINFO_TYPE_USHORT     = 0x7,
    CORINFO_TYPE_INT        = 0x8,
    CORINFO_TYPE_UINT       = 0x9,
    CORINFO_TYPE_LONG       = 0xa,
    CORINFO_TYPE_ULONG      = 0xb,
    CORINFO_TYPE_NATIVEINT  = 0xc,
    CORINFO_TYPE_NATIVEUINT = 0xd,
    CORINFO_TYPE_FLOAT      = 0xe,
    CORINFO_TYPE_DOUBLE     = 0xf,
    CORINFO_TYPE_PTR        = 0x10,
    CORINFO_TYPE_BYREF      = 0x11,
    CORINFO_TYPE_VALUECLASS = 0x12,
    CORINFO_TYPE_CLASS      = 0x13,
};

/* DONOR: corinfo.h:1049 | SHA256: C6EC58DB730DE6DC1864481E9734384E3AB137EBAC2A6EDD04228A43B9DBE30E */
typedef struct CORINFO_SIG_INFO {
    uint32_t            callConv;
    void*               retTypeClass;
    void*               retTypeSigClass;
    uint8_t             retType;
    uint8_t             flags;
    uint16_t            numArgs;
    uint16_t            sigInst_classInstCount;
    uint16_t            sigInst_methInstCount;
    void*               sigInst_classInst;
    void*               sigInst_methInst;
    void*               args;
    void*               pSig;
    uint32_t            cbSig;
    void*               scope;
    uint32_t            token;
} CORINFO_SIG_INFO;

/* DONOR: corinfo.h:1075 | SHA256: C6EC58DB730DE6DC1864481E9734384E3AB137EBAC2A6EDD04228A43B9DBE30E */
typedef struct CORINFO_METHOD_INFO {
    void*               ftn;
    void*               scope;
    uint8_t*            ILCode;
    uint32_t            ILCodeSize;
    uint16_t            maxStack;
    uint16_t            EHcount;
    uint32_t            options;
    void*               regionKind;
    CORINFO_SIG_INFO    args;
    CORINFO_SIG_INFO    locals;
} CORINFO_METHOD_INFO;

/* ========================================================================= */
/* SECTION 7: REMEDY 64-BIT GENERATIONAL HANDLE                              */
/* ========================================================================= */

typedef uint64_t remedy_handle_t;

#define REMEDY_INVALID_HANDLE 0ULL

static inline uint32_t remedy_handle_slot(remedy_handle_t handle) {
    return (uint32_t)(handle & 0xFFFFFFFFULL);
}

static inline uint32_t remedy_handle_generation(remedy_handle_t handle) {
    return (uint32_t)(handle >> 32);
}

static inline remedy_handle_t remedy_handle_make(uint32_t generation, uint32_t slot) {
    return (((uint64_t)generation) << 32) | ((uint64_t)slot);
}

#ifdef __cplusplus
}
#endif

#endif /* NATIVESMA_WINDOWS_H */
