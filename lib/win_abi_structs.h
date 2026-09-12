#pragma once
#include <stdint.h>
#include <stddef.h>

typedef void* HANDLE;
typedef uint32_t DWORD;
typedef int32_t NTSTATUS;
typedef int32_t LSTATUS;

struct NT_TIB {
    void* ExceptionList; void* StackBase; void* StackLimit;
    void* SubSystemTib; void* FiberData; void* ArbitraryUserPointer;
    struct NT_TIB* Self;
};
