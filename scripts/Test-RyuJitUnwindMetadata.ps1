[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'Tests\Test-SmaRyuJitSpine.ps1'
$results = & $scriptPath -PassThru -SpecimenName 'TypedIntegerAddProbe'

foreach ($result in $results) {
    Write-Host "Analyzing method: $($result.Name)"
    $method = $result.Method
    $entry = $result.EntryPoint
    
    # Follow the usual x64 precode indirection when GetFunctionPointer returns it.
    if ([Runtime.InteropServices.Marshal]::ReadByte($entry,0) -eq 0xFF -and [Runtime.InteropServices.Marshal]::ReadByte($entry,1) -eq 0x25) {
        $displacement = [Runtime.InteropServices.Marshal]::ReadInt32($entry,2)
        $slot = [IntPtr]::Add($entry, 6 + $displacement)
        $entry = [Runtime.InteropServices.Marshal]::ReadIntPtr($slot)
    }

    $kernel = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
    $ntdll = [Runtime.InteropServices.NativeLibrary]::Load('ntdll.dll')
    
    # We need RtlLookupFunctionEntry
    $asm = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly([Reflection.AssemblyName]::new('Dbg'), 1)
    $mod = $asm.DefineDynamicModule('M')
    $type = $mod.DefineType("T", [Reflection.TypeAttributes]'Class,Public,Sealed', [MulticastDelegate])
    $ctor = $type.DefineConstructor([Reflection.MethodAttributes]'RTSpecialName,HideBySig,Public', [Reflection.CallingConventions]::Standard, [Type[]]@([object],[IntPtr]))
    $ctor.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $invoke = $type.DefineMethod('Invoke', [Reflection.MethodAttributes]'Public,HideBySig,NewSlot,Virtual', [IntPtr], [Type[]]@([uint64],[IntPtr],[IntPtr]))
    $invoke.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $dlgType = $type.CreateType()
    $rtlLookup = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer([Runtime.InteropServices.NativeLibrary]::GetExport($ntdll, 'RtlLookupFunctionEntry'), $dlgType)

    $imageBaseOut = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    [Runtime.InteropServices.Marshal]::WriteInt64($imageBaseOut, 0)
    
    $runtimeFunction = [IntPtr]$rtlLookup.DynamicInvoke([uint64]$entry.ToInt64(), $imageBaseOut, [IntPtr]::Zero)
    if ($runtimeFunction -eq [IntPtr]::Zero) {
        Write-Host "  No RUNTIME_FUNCTION found."
    } else {
        $imageBase = [Runtime.InteropServices.Marshal]::ReadInt64($imageBaseOut)
        $beginRva = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($runtimeFunction, 0)
        $endRva = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($runtimeFunction, 4)
        $unwindRva = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($runtimeFunction, 8)
        
        Write-Host "  RUNTIME_FUNCTION: BeginRva=0x$($beginRva.ToString('X')), EndRva=0x$($endRva.ToString('X')), UnwindRva=0x$($unwindRva.ToString('X'))"
        Write-Host "  Method Extent: $($endRva - $beginRva) bytes"
        
        $unwindInfoAddress = [IntPtr]($imageBase + $unwindRva)
        $versionAndFlags = [Runtime.InteropServices.Marshal]::ReadByte($unwindInfoAddress, 0)
        $version = $versionAndFlags -band 0x07
        $flags = ($versionAndFlags -shr 3) -band 0x1F
        
        $sizeOfProlog = [Runtime.InteropServices.Marshal]::ReadByte($unwindInfoAddress, 1)
        $countOfCodes = [Runtime.InteropServices.Marshal]::ReadByte($unwindInfoAddress, 2)
        $frameRegisterAndOffset = [Runtime.InteropServices.Marshal]::ReadByte($unwindInfoAddress, 3)
        
        Write-Host "  UNWIND_INFO: Version=$version, Flags=0x$($flags.ToString('X'))"
        Write-Host "    SizeOfProlog=$sizeOfProlog, CountOfCodes=$countOfCodes"
        
        if (($flags -band 0x04) -eq 0x04) {
            Write-Host "    [!] UNW_FLAG_CHAININFO is SET. There are chained unwinds (e.g. cold blocks)." -ForegroundColor Red
        } else {
            Write-Host "    [+] UNW_FLAG_CHAININFO is NOT set. Single hot allocation." -ForegroundColor Green
        }
    }
    [Runtime.InteropServices.Marshal]::FreeHGlobal($imageBaseOut)
    [Runtime.InteropServices.NativeLibrary]::Free($ntdll)
    [Runtime.InteropServices.NativeLibrary]::Free($kernel)
}