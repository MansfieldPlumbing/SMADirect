# Extracts an exact AMD64 function extent emitted by RyuJIT.
param(
    [Parameter(Mandatory)][string]$LoweredDllPath,
    [Parameter(Mandatory)][string]$TypeName,
    [Parameter(Mandatory)][string]$MethodName,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Win32.NativeCall.ps1')

Write-Host "=== EXTRACTING AUTHENTIC RYUJIT X64 MACHINE CODE ===" -ForegroundColor Cyan
Write-Host "Lowered Assembly: $LoweredDllPath"

$asm = [Reflection.Assembly]::LoadFrom((Resolve-Path $LoweredDllPath))
$type = $asm.GetType($TypeName, $true)
$method = $type.GetMethod($MethodName)

# Trigger RyuJIT compilation
[System.Runtime.CompilerServices.RuntimeHelpers]::PrepareMethod($method.MethodHandle)
$fnPtr = $method.MethodHandle.GetFunctionPointer()

# Inspect precode stub
$precodeBytes = [byte[]]::new(16)
[System.Runtime.InteropServices.Marshal]::Copy($fnPtr, $precodeBytes, 0, 16)

$targetCodePtr = $fnPtr
# Check for AMD64 precode jump: FF 25 <rel32>
if ($precodeBytes[0] -eq 0xFF -and $precodeBytes[1] -eq 0x25) {
    $offset = [System.BitConverter]::ToInt32($precodeBytes, 2)
    $rip = [int64]$fnPtr + 6
    $targetCell = [IntPtr]($rip + $offset)
    $targetCodePtr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($targetCell)
    Write-Host "Followed AMD64 precode stub (0x$($fnPtr.ToString('X'))) -> target cell 0x$($targetCell.ToString('X'))" -ForegroundColor Green
}

Write-Host "Authentic RyuJIT Machine Code Address: 0x$($targetCodePtr.ToString('X'))" -ForegroundColor Green

$ntdll = [Runtime.InteropServices.NativeLibrary]::Load('ntdll.dll')
$imageBaseOut = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
try {
    [Runtime.InteropServices.Marshal]::WriteInt64($imageBaseOut, 0)
    $rtlLookup = Get-NativeCall `
        ([Runtime.InteropServices.NativeLibrary]::GetExport($ntdll, 'RtlLookupFunctionEntry')) `
        ([IntPtr]) `
        ([Type[]]@([uint64], [IntPtr], [IntPtr]))
    $runtimeFunction = [IntPtr]$rtlLookup.DynamicInvoke([uint64]$targetCodePtr.ToInt64(), $imageBaseOut, [IntPtr]::Zero)
    if ($runtimeFunction -eq [IntPtr]::Zero) {

        $stub = [byte[]]::new(24)
        [Runtime.InteropServices.Marshal]::Copy(
            $targetCodePtr,
            $stub,
            0,
            24
        )

        $isCallCountingStub =
            $stub[0]  -eq 0x48 -and
            $stub[1]  -eq 0x8B -and
            $stub[2]  -eq 0x05 -and
            $stub[7]  -eq 0x66 -and
            $stub[8]  -eq 0xFF -and
            $stub[9]  -eq 0x08 -and
            $stub[10] -eq 0x74 -and
            $stub[11] -eq 0x06 -and
            $stub[12] -eq 0xFF -and
            $stub[13] -eq 0x25

        if ($isCallCountingStub) {
            $disp = [BitConverter]::ToInt32($stub,14)

            $methodTargetCell = [IntPtr](
                $targetCodePtr.ToInt64() +
                18 +
                $disp
            )

            $targetCodePtr =
                [Runtime.InteropServices.Marshal]::ReadIntPtr(
                    $methodTargetCell
                )

            Write-Host (
                "Followed CoreCLR CallCountingStub -> method target 0x{0:X}" -f
                $targetCodePtr.ToInt64()
            ) -ForegroundColor Green

            [Runtime.InteropServices.Marshal]::WriteInt64(
                $imageBaseOut,
                0
            )

            $runtimeFunction = [IntPtr]$rtlLookup.DynamicInvoke(
                [uint64]$targetCodePtr.ToInt64(),
                $imageBaseOut,
                [IntPtr]::Zero
            )
        }
    }

    if ($runtimeFunction -eq [IntPtr]::Zero) {
        throw "Unable to resolve exact RyuJIT runtime-function extent for $TypeName.$MethodName."
    }
    $imageBase = [Runtime.InteropServices.Marshal]::ReadInt64($imageBaseOut)
    $beginRva = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($runtimeFunction, 0)
    $endRva = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($runtimeFunction, 4)
    if ($endRva -le $beginRva) {
        throw "Invalid RyuJIT runtime-function range for $TypeName.$MethodName."
    }
    $bodyStart = [IntPtr]($imageBase + $beginRva)
    $bodyEnd = [IntPtr]($imageBase + $endRva)
    if ($targetCodePtr.ToInt64() -lt $bodyStart.ToInt64() -or $targetCodePtr.ToInt64() -ge $bodyEnd.ToInt64()) {
        throw "RyuJIT entry for $TypeName.$MethodName is outside its runtime-function range."
    }
    $codeLength = [int]($endRva - $beginRva)
    $realMachineCode = [byte[]]::new($codeLength)
    [Runtime.InteropServices.Marshal]::Copy($bodyStart, $realMachineCode, 0, $codeLength)
} finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($imageBaseOut)
    [Runtime.InteropServices.NativeLibrary]::Free($ntdll)
}

$outPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.File]::WriteAllBytes($outPath, $realMachineCode)

Write-Host "Authentic RyuJIT x64 Machine Code written to disk: $outPath ($codeLength bytes)" -ForegroundColor Green
Write-Host "Prologue: $(($realMachineCode[0..15] | ForEach-Object { $_.ToString('X2') }) -join ' ')" -ForegroundColor Yellow
Write-Host "Epilogue: $(($realMachineCode[($codeLength-8)..($codeLength-1)] | ForEach-Object { $_.ToString('X2') }) -join ' ')" -ForegroundColor Yellow
Write-Host "RECEIPT_REAL_RYUJIT_CODEGEN=PASS" -ForegroundColor Green
