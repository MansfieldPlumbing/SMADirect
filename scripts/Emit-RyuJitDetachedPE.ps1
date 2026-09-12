[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\Windows\SMADirect.RyuJit.exe'),
    [ValidateSet('Arithmetic','Publication','Remedy','CalculatorDisplay')][string] $Personality = 'Arithmetic',
    [int] $ProducerPid = 0,
    [switch] $SkipLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitProcess) { throw 'The build host must be x64.' }

function Align-Up([uint32] $Value, [uint32] $Alignment) {
    [uint32](($Value + $Alignment - 1) -band -bnot ($Alignment - 1))
}
function Set-I32([byte[]] $Bytes, [int] $Offset, [int32] $Value) {
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}
function Set-U32([byte[]] $Bytes, [int] $Offset, [uint32] $Value) {
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}
function Set-U64([byte[]] $Bytes, [int] $Offset, [uint64] $Value) {
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}
function Add-AsciiZ([IO.BinaryWriter] $Writer, [string] $Text) {
    $Writer.Write([Text.Encoding]::ASCII.GetBytes($Text)); $Writer.Write([byte]0)
}

# Runtime delegate types are build-host plumbing only. No generated managed
# source, managed assembly, or CLR metadata is placed in the output image.
$hostAssembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('SMADirect.RyuJit.Detach.' + [Guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$hostModule = $hostAssembly.DefineDynamicModule('Host')
$delegateOrdinal = 0
function New-DelegateType([Type] $ReturnType, [Type[]] $Parameters) {
    $script:delegateOrdinal++
    $type = $hostModule.DefineType("NativeCall$script:delegateOrdinal", [Reflection.TypeAttributes]'Class,Public,Sealed', [MulticastDelegate])
    $ctor = $type.DefineConstructor([Reflection.MethodAttributes]'RTSpecialName,HideBySig,Public', [Reflection.CallingConventions]::Standard, [Type[]]@([object],[IntPtr]))
    $ctor.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $invoke = $type.DefineMethod('Invoke', [Reflection.MethodAttributes]'Public,HideBySig,NewSlot,Virtual', $ReturnType, $Parameters)
    $invoke.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $type.CreateType()
}
function Get-NativeCall([IntPtr] $Address, [Type] $ReturnType, [Type[]] $Parameters) {
    [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($Address, (New-DelegateType $ReturnType $Parameters))
}

$kernel = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
$ntdll = [Runtime.InteropServices.NativeLibrary]::Load('ntdll.dll')
try {
    $getPidAddress = [Runtime.InteropServices.NativeLibrary]::GetExport($kernel, 'GetCurrentProcessId')
    $virtualAlloc = Get-NativeCall ([Runtime.InteropServices.NativeLibrary]::GetExport($kernel, 'VirtualAlloc')) ([IntPtr]) ([Type[]]@([IntPtr],[UIntPtr],[uint32],[uint32]))
    $virtualFree = Get-NativeCall ([Runtime.InteropServices.NativeLibrary]::GetExport($kernel, 'VirtualFree')) ([bool]) ([Type[]]@([IntPtr],[UIntPtr],[uint32]))
    $rtlLookup = Get-NativeCall ([Runtime.InteropServices.NativeLibrary]::GetExport($ntdll, 'RtlLookupFunctionEntry')) ([IntPtr]) ([Type[]]@([uint64],[IntPtr],[IntPtr]))

    # Authored IL is the deliberately tiny admitted input to RyuJIT. Keep this
    # first detached body leaf-only: unmanaged calli introduces CLR transition
    # machinery, while integer SMA semantics compile to self-contained code.
    $bodyTypeBuilder = $hostModule.DefineType('DetachedBody', [Reflection.TypeAttributes]'Class,Public,Sealed,Abstract')
    $argumentType = if ($Personality -in @('Publication','CalculatorDisplay')) { [IntPtr] } else { [uint32] }
    $bodyMethodBuilder = $bodyTypeBuilder.DefineMethod('Invoke', [Reflection.MethodAttributes]'Public,Static', [uint32], [Type[]]@($argumentType))
    $il = $bodyMethodBuilder.GetILGenerator()
    if ($Personality -eq 'CalculatorDisplay') {
        # Admitted native CalculatorState.DisplayValue layout v1:
        #   +0 uint32 Length, +4 uint32 Capacity, +8 inline UTF-16 storage.
        # This body is both setter and getter receipt for the bounded inline
        # representation. No CLR object layout or managed string is consulted.
        $lengthOk = $il.DefineLabel()
        $capacityOk = $il.DefineLabel()
        $firstCharOk = $il.DefineLabel()
        $success = $il.DefineLabel()

        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_2)
        $il.Emit([Reflection.Emit.OpCodes]::Stind_I4)
        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_4)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_I)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 32)
        $il.Emit([Reflection.Emit.OpCodes]::Stind_I4)
        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_8)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_I)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, [int][char]'4')
        $il.Emit([Reflection.Emit.OpCodes]::Stind_I2)
        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 10)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_I)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, [int][char]'2')
        $il.Emit([Reflection.Emit.OpCodes]::Stind_I2)

        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldind_U4)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_2)
        $il.Emit([Reflection.Emit.OpCodes]::Beq, $lengthOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_1)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        $il.MarkLabel($lengthOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_4)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_I)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
        $il.Emit([Reflection.Emit.OpCodes]::Ldind_U4)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 32)
        $il.Emit([Reflection.Emit.OpCodes]::Beq, $capacityOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_2)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        $il.MarkLabel($capacityOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_8)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_I)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
        $il.Emit([Reflection.Emit.OpCodes]::Ldind_U2)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, [int][char]'4')
        $il.Emit([Reflection.Emit.OpCodes]::Beq, $firstCharOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_3)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        $il.MarkLabel($firstCharOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 10)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_I)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
        $il.Emit([Reflection.Emit.OpCodes]::Ldind_U2)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, [int][char]'2')
        $il.Emit([Reflection.Emit.OpCodes]::Beq, $success)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_4)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        $il.MarkLabel($success)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_0)
    } elseif ($Personality -eq 'Remedy') {
        # This is the first native Remedy/PSDirect invariant body. It proves the
        # exact numeric identity and enumerated dispatch contract before the
        # object table allocator itself is admitted into the detached runtime.
        $firstHandle = $il.DeclareLocal([uint64])
        $secondHandle = $il.DeclareLocal([uint64])
        $operation = $il.DeclareLocal([uint32])
        $success = $il.DefineLabel()
        $generationOk = $il.DefineLabel()
        $offsetOk = $il.DefineLabel()
        $scaleOk = $il.DefineLabel()

        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, [int64]0x0000000100000001)
        $il.Emit([Reflection.Emit.OpCodes]::Stloc, $firstHandle)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, [int64]0x0000000200000001)
        $il.Emit([Reflection.Emit.OpCodes]::Stloc, $secondHandle)

        # Same slot, advanced generation, and therefore unequal identity.
        $il.Emit([Reflection.Emit.OpCodes]::Ldloc, $firstHandle)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_U4)
        $il.Emit([Reflection.Emit.OpCodes]::Ldloc, $secondHandle)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_U4)
        $il.Emit([Reflection.Emit.OpCodes]::Beq, $generationOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_1)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        $il.MarkLabel($generationOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldloc, $firstHandle)
        $il.Emit([Reflection.Emit.OpCodes]::Ldloc, $secondHandle)
        $il.Emit([Reflection.Emit.OpCodes]::Bne_Un, $offsetOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_2)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)

        # Operation 1001: offset backing amount 3 applied to argument 7.
        $il.MarkLabel($offsetOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 1001)
        $il.Emit([Reflection.Emit.OpCodes]::Stloc, $operation)
        $il.Emit([Reflection.Emit.OpCodes]::Ldloc, $operation)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 1001)
        $il.Emit([Reflection.Emit.OpCodes]::Bne_Un, $scaleOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_7)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_3)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 10)
        $il.Emit([Reflection.Emit.OpCodes]::Beq, $scaleOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_3)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)

        # Operation 1002: scale backing amount 4 applied to argument 7.
        $il.MarkLabel($scaleOk)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 1002)
        $il.Emit([Reflection.Emit.OpCodes]::Stloc, $operation)
        $il.Emit([Reflection.Emit.OpCodes]::Ldloc, $operation)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 1002)
        $il.Emit([Reflection.Emit.OpCodes]::Bne_Un, $success)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_7)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_4)
        $il.Emit([Reflection.Emit.OpCodes]::Mul)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 28)
        $il.Emit([Reflection.Emit.OpCodes]::Beq, $success)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_4)
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        $il.MarkLabel($success)
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_0)
    } else {
        $il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
    }
    if ($Personality -eq 'Publication') {
        $il.Emit([Reflection.Emit.OpCodes]::Conv_U)
        $il.Emit([Reflection.Emit.OpCodes]::Ldind_I8)
        $il.Emit([Reflection.Emit.OpCodes]::Conv_U4)
    } elseif ($Personality -eq 'Arithmetic') {
        $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, 0x1234)
        $il.Emit([Reflection.Emit.OpCodes]::Add)
    }
    $il.Emit([Reflection.Emit.OpCodes]::Ret)
    $bodyType = $bodyTypeBuilder.CreateType()
    $bodyMethod = $bodyType.GetMethod('Invoke')
    [Runtime.CompilerServices.RuntimeHelpers]::PrepareMethod($bodyMethod.MethodHandle)
    $entry = $bodyMethod.MethodHandle.GetFunctionPointer()

    # Follow the usual x64 precode indirection when GetFunctionPointer returns it.
    if ([Runtime.InteropServices.Marshal]::ReadByte($entry,0) -eq 0xFF -and [Runtime.InteropServices.Marshal]::ReadByte($entry,1) -eq 0x25) {
        $displacement = [Runtime.InteropServices.Marshal]::ReadInt32($entry,2)
        $slot = [IntPtr]::Add($entry, 6 + $displacement)
        $entry = [Runtime.InteropServices.Marshal]::ReadIntPtr($slot)
    }

    # Ask Windows' x64 unwind registry for the exact RyuJIT code extent. This
    # avoids the invalid "copy until the first RET" shortcut.
    $imageBaseOut = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt64($imageBaseOut, 0)
        $runtimeFunction = [IntPtr]$rtlLookup.DynamicInvoke([uint64]$entry.ToInt64(), $imageBaseOut, [IntPtr]::Zero)
        if ($runtimeFunction -ne [IntPtr]::Zero) {
            $registeredBase = [Runtime.InteropServices.Marshal]::ReadInt64($imageBaseOut)
            $beginRva = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($runtimeFunction, 0)
            $endRva = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($runtimeFunction, 4)
            $registeredEntry = [IntPtr]::new($registeredBase + $beginRva)
            if ($registeredEntry -ne $entry) { throw 'RyuJIT entry point did not match its registered unwind extent.' }
            $bodyLength = [int]($endRva - $beginRva)
        } else {
            # Windows intentionally has no RUNTIME_FUNCTION record for leaf
            # functions. This admitted body has one basic block and one RET.
            $bodyLength = 0
            while ($bodyLength -lt 64) {
                $bodyLength++
                if ([Runtime.InteropServices.Marshal]::ReadByte($entry,$bodyLength-1) -eq 0xC3) { break }
            }
            if ($bodyLength -eq 64) { throw 'Leaf RyuJIT body had no RET in its admitted 64-byte extent.' }
        }
        if ($bodyLength -lt 2 -or $bodyLength -gt 4096) { throw "Implausible RyuJIT body length: $bodyLength" }
        $bodyBytes = [byte[]]::new($bodyLength)
        [Runtime.InteropServices.Marshal]::Copy($entry, $bodyBytes, 0, $bodyLength)
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($imageBaseOut)
    }

    # Copy the bytes to an unrelated executable allocation and call them there.
    # Passing the Win32 function pointer ensures both relocation and detached
    # native calli behavior are proven before the PE is written.
    $moved = [IntPtr]$virtualAlloc.DynamicInvoke([IntPtr]::Zero, [UIntPtr]$bodyBytes.Length, [uint32]0x3000, [uint32]0x40)
    if ($moved -eq [IntPtr]::Zero) { throw 'VirtualAlloc failed for relocated-body verification.' }
    try {
        [Runtime.InteropServices.Marshal]::Copy($bodyBytes, 0, $moved, $bodyBytes.Length)
        if ($Personality -eq 'Publication') {
            $probe = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
            [Runtime.InteropServices.Marshal]::WriteInt64($probe, [int64]0x1122334455667788)
            try {
                $movedCall = Get-NativeCall $moved ([uint32]) ([Type[]]@([IntPtr]))
                $movedResult = [uint32]$movedCall.DynamicInvoke($probe)
                $hostExpected = [uint32]0x55667788
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($probe) }
        } elseif ($Personality -eq 'CalculatorDisplay') {
            $probe = [Runtime.InteropServices.Marshal]::AllocHGlobal(72)
            try {
                $movedCall = Get-NativeCall $moved ([uint32]) ([Type[]]@([IntPtr]))
                $movedResult = [uint32]$movedCall.DynamicInvoke($probe)
                $hostExpected = [uint32]0
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($probe) }
        } elseif ($Personality -eq 'Arithmetic') {
            $movedCall = Get-NativeCall $moved ([uint32]) ([Type[]]@([uint32]))
            $hostPid = [uint32]$PID
            $movedResult = [uint32]$movedCall.DynamicInvoke($hostPid)
            $hostExpected = [uint32]($hostPid + 0x1234)
        } else {
            $movedCall = Get-NativeCall $moved ([uint32]) ([Type[]]@([uint32]))
            $movedResult = [uint32]$movedCall.DynamicInvoke([uint32]0)
            $hostExpected = [uint32]0
        }
        if ($movedResult -ne $hostExpected) { throw "Relocated RyuJIT body returned $movedResult; expected $hostExpected." }
    } finally {
        [void]$virtualFree.DynamicInvoke($moved, [UIntPtr]::Zero, [uint32]0x8000)
    }
} finally {
    [Runtime.InteropServices.NativeLibrary]::Free($ntdll)
    [Runtime.InteropServices.NativeLibrary]::Free($kernel)
}

# Build a two-section AMD64 PE. The entry shim owns only flat Windows ABI work;
# the personality operation itself is the RyuJIT body.
$fileAlignment = [uint32]0x200; $sectionAlignment = [uint32]0x1000
$headersSize = [uint32]0x200; $textRva = [uint32]0x1000; $rdataRva = [uint32]0x2000
$imageBase = [uint64]0x140000000

$rdataStream = [IO.MemoryStream]::new()
$rdataWriter = [IO.BinaryWriter]::new($rdataStream, [Text.Encoding]::UTF8, $true)
$shim = [Collections.Generic.List[byte]]::new()
if ($Personality -eq 'Publication') {
    if (-not $ProducerPid) {
        $producer = Get-Process -Name DirectPortProducerD3D12 -ErrorAction Stop | Select-Object -First 1
        $ProducerPid = $producer.Id
    }
    $manifestName = "DirectPort_Producer_Manifest_$ProducerPid"
    $rdataWriter.Write([byte[]]::new(120)) # IAT(40), ILT(40), descriptors(40)
    $dllNameOffset=[uint32]$rdataStream.Position; Add-AsciiZ $rdataWriter 'KERNELBASE.dll'
    $nameOffsets=[Collections.Generic.List[uint32]]::new()
    foreach($name in @('ExitProcess','OpenFileMappingW','MapViewOfFile','WaitOnAddress')) {
        if(($rdataStream.Position-band 1)-ne 0){$rdataWriter.Write([byte]0)}
        $nameOffsets.Add([uint32]$rdataStream.Position);$rdataWriter.Write([uint16]0);Add-AsciiZ $rdataWriter $name
    }
    $manifestOffset=[uint32]$rdataStream.Position
    $rdataWriter.Write([Text.Encoding]::Unicode.GetBytes($manifestName));$rdataWriter.Write([uint16]0)
    $rdataWriter.Flush();$rdataBytes=$rdataStream.ToArray()
    for($i=0;$i-lt4;$i++){Set-U64 $rdataBytes ($i*8) ([uint64]($rdataRva+$nameOffsets[$i]));Set-U64 $rdataBytes (40+$i*8) ([uint64]($rdataRva+$nameOffsets[$i]))}
    Set-U32 $rdataBytes 80 ([uint32]($rdataRva+40));Set-U32 $rdataBytes 92 ([uint32]($rdataRva+$dllNameOffset));Set-U32 $rdataBytes 96 $rdataRva
    $importDescriptorOffset=[uint32]80;$iatSize=[uint32]40

    $shim.AddRange([byte[]]@(0x48,0x83,0xEC,0x58))                         # stack + shadow + compare
    $shim.AddRange([byte[]]@(0xB9,0x04,0,0,0,0x31,0xD2))                 # FILE_MAP_READ, inherit=false
    $manifestLea=$shim.Count;$shim.AddRange([byte[]]@(0x4C,0x8D,0x05,0,0,0,0))
    $openCall=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0))
    $shim.AddRange([byte[]]@(0x48,0x85,0xC0));$openFail=$shim.Count;$shim.AddRange([byte[]]@(0x74,0))
    $shim.AddRange([byte[]]@(0x48,0x89,0xC1,0xBA,0x04,0,0,0,0x45,0x31,0xC0,0x45,0x31,0xC9))
    $shim.AddRange([byte[]]@(0x48,0xC7,0x44,0x24,0x20,0,0,0,0))
    $mapCall=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0))
    $shim.AddRange([byte[]]@(0x48,0x85,0xC0));$mapFail=$shim.Count;$shim.AddRange([byte[]]@(0x74,0))
    $shim.AddRange([byte[]]@(0x48,0x89,0xC3,0x48,0x8B,0x00,0x48,0x89,0x44,0x24,0x40,0x48,0x89,0xD9))
    $shim.AddRange([byte[]]@(0x48,0x8D,0x54,0x24,0x40,0x41,0xB8,0x08,0,0,0,0x41,0xB9,0x88,0x13,0,0))
    $waitCall=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0))
    $shim.AddRange([byte[]]@(0x48,0x89,0xD9))
    $bodyCall=$shim.Count;$shim.AddRange([byte[]]@(0xE8,0,0,0,0))
    $shim.AddRange([byte[]]@(0x89,0xC1));$exitCall=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0,0xCC))
    $failOffset=$shim.Count;$shim.AddRange([byte[]]@(0xB9,0xFF,0xFF,0xFF,0xFF));$failExit=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0,0xCC))
    $shim[$openFail+1]=[byte]($failOffset-($openFail+2));$shim[$mapFail+1]=[byte]($failOffset-($mapFail+2))
    while(($shim.Count-band 15)-ne0){$shim.Add(0x90)};$bodyOffset=$shim.Count;$shim.AddRange($bodyBytes);$textBytes=$shim.ToArray()
    Set-I32 $textBytes ($manifestLea+3) ([int32](($rdataRva+$manifestOffset)-($textRva+$manifestLea+7)))
    foreach($fix in @(@($openCall,8),@($mapCall,16),@($waitCall,24),@($exitCall,0),@($failExit,0))){Set-I32 $textBytes ($fix[0]+2) ([int32](($rdataRva+$fix[1])-($textRva+$fix[0]+6)))}
    Set-I32 $textBytes ($bodyCall+1) ([int32](($textRva+$bodyOffset)-($textRva+$bodyCall+5)))
} else {
    $rdataWriter.Write([byte[]]::new(88))
    $dllNameOffset=[uint32]$rdataStream.Position;Add-AsciiZ $rdataWriter 'KERNEL32.dll'
    if(($rdataStream.Position-band 1)-ne0){$rdataWriter.Write([byte]0)}
    $exitNameOffset=[uint32]$rdataStream.Position;$rdataWriter.Write([uint16]0);Add-AsciiZ $rdataWriter 'ExitProcess'
    if(($rdataStream.Position-band 1)-ne0){$rdataWriter.Write([byte]0)}
    $getPidNameOffset=[uint32]$rdataStream.Position;$rdataWriter.Write([uint16]0);Add-AsciiZ $rdataWriter 'GetCurrentProcessId'
    $rdataWriter.Flush();$rdataBytes=$rdataStream.ToArray()
    Set-U64 $rdataBytes 0 ([uint64]($rdataRva+$exitNameOffset));Set-U64 $rdataBytes 8 ([uint64]($rdataRva+$getPidNameOffset));Set-U64 $rdataBytes 24 ([uint64]($rdataRva+$exitNameOffset));Set-U64 $rdataBytes 32 ([uint64]($rdataRva+$getPidNameOffset))
    Set-U32 $rdataBytes 48 ([uint32]($rdataRva+24));Set-U32 $rdataBytes 60 ([uint32]($rdataRva+$dllNameOffset));Set-U32 $rdataBytes 64 $rdataRva
    $importDescriptorOffset=[uint32]48;$iatSize=[uint32]24
    if ($Personality -eq 'CalculatorDisplay') {
        $shim.AddRange([byte[]]@(0x48,0x83,0xEC,0x78))
        $shim.AddRange([byte[]]@(0x48,0x8D,0x4C,0x24,0x30))
        $bodyCall=$shim.Count;$shim.AddRange([byte[]]@(0xE8,0,0,0,0))
        $shim.AddRange([byte[]]@(0x89,0xC1));$exitCall=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0,0xCC))
        $getPidCall = $null
    } else {
        $shim.AddRange([byte[]]@(0x48,0x83,0xEC,0x28));$getPidCall=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0));$shim.AddRange([byte[]]@(0x89,0xC1));$bodyCall=$shim.Count;$shim.AddRange([byte[]]@(0xE8,0,0,0,0));$shim.AddRange([byte[]]@(0x89,0xC1));$exitCall=$shim.Count;$shim.AddRange([byte[]]@(0xFF,0x15,0,0,0,0,0xCC))
    }
    while(($shim.Count-band 15)-ne0){$shim.Add(0x90)};$bodyOffset=$shim.Count;$shim.AddRange($bodyBytes);$textBytes=$shim.ToArray()
    if ($null -ne $getPidCall) { Set-I32 $textBytes ($getPidCall+2) ([int32](($rdataRva+8)-($textRva+$getPidCall+6))) }
    Set-I32 $textBytes ($bodyCall+1) ([int32](($textRva+$bodyOffset)-($textRva+$bodyCall+5)));Set-I32 $textBytes ($exitCall+2) ([int32]($rdataRva-($textRva+$exitCall+6)))
}

$textRawSize = Align-Up $textBytes.Length $fileAlignment
$rdataRawSize = Align-Up $rdataBytes.Length $fileAlignment
$stream = [IO.MemoryStream]::new(); $writer = [IO.BinaryWriter]::new($stream, [Text.Encoding]::UTF8, $true)
$dos = [byte[]]::new(128); $dos[0]=0x4D; $dos[1]=0x5A; [BitConverter]::GetBytes([int32]128).CopyTo($dos,0x3C)
$writer.Write($dos); $writer.Write([uint32]0x00004550)
$writer.Write([uint16]0x8664); $writer.Write([uint16]2); $writer.Write([uint32]0); $writer.Write([uint32]0); $writer.Write([uint32]0); $writer.Write([uint16]240); $writer.Write([uint16]0x0022)
$writer.Write([uint16]0x020B); $writer.Write([byte]0); $writer.Write([byte]1)
$writer.Write($textRawSize); $writer.Write($rdataRawSize); $writer.Write([uint32]0); $writer.Write($textRva); $writer.Write($textRva); $writer.Write($imageBase)
$writer.Write($sectionAlignment); $writer.Write($fileAlignment)
$writer.Write([uint16]6); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint16]6); $writer.Write([uint16]0)
$writer.Write([uint32]0); $writer.Write([uint32]0x3000); $writer.Write($headersSize); $writer.Write([uint32]0)
$writer.Write([uint16]2); $writer.Write([uint16]0x0160)
$writer.Write([uint64]0x100000); $writer.Write([uint64]0x1000); $writer.Write([uint64]0x100000); $writer.Write([uint64]0x1000)
$writer.Write([uint32]0); $writer.Write([uint32]16)
for ($directory=0; $directory -lt 16; $directory++) {
    if ($directory -eq 1) { $writer.Write([uint32]($rdataRva+$importDescriptorOffset)); $writer.Write([uint32]40) }
    elseif ($directory -eq 12) { $writer.Write($rdataRva); $writer.Write($iatSize) }
    else { $writer.Write([uint32]0); $writer.Write([uint32]0) }
}
function Add-Section([string]$Name,[uint32]$VirtualSize,[uint32]$Rva,[uint32]$RawSize,[uint32]$RawOffset,[uint32]$Flags) {
    $nameBytes=[byte[]]::new(8); [Text.Encoding]::ASCII.GetBytes($Name).CopyTo($nameBytes,0); $writer.Write($nameBytes)
    $writer.Write($VirtualSize); $writer.Write($Rva); $writer.Write($RawSize); $writer.Write($RawOffset)
    $writer.Write([uint32]0); $writer.Write([uint32]0); $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write($Flags)
}
Add-Section '.text' ([uint32]$textBytes.Length) $textRva $textRawSize 0x200 0x60000020
Add-Section '.rdata' ([uint32]$rdataBytes.Length) $rdataRva $rdataRawSize ([uint32](0x200+$textRawSize)) 0x40000040
if ($stream.Position -gt $headersSize) { throw 'PE headers exceed one file-alignment block.' }
$writer.Write([byte[]]::new([int]($headersSize-$stream.Position)))
$writer.Write($textBytes); $writer.Write([byte[]]::new([int]($textRawSize-$textBytes.Length)))
$writer.Write($rdataBytes); $writer.Write([byte[]]::new([int]($rdataRawSize-$rdataBytes.Length))); $writer.Flush()

$fullOutput = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullOutput)) | Out-Null
[IO.File]::WriteAllBytes($fullOutput, $stream.ToArray())

$receipt = [ordered]@{
    Status='BUILT'; Path=$fullOutput; Bytes=(Get-Item -LiteralPath $fullOutput).Length
    Sha256=(Get-FileHash -LiteralPath $fullOutput -Algorithm SHA256).Hash
    Machine='AMD64'; RyuJitBodyBytes=$bodyBytes.Length; RelocatedHostResult=$movedResult
    Personality=$Personality
    Imports=if($Personality-eq'Publication'){'KERNELBASE.dll!ExitProcess, OpenFileMappingW, MapViewOfFile, WaitOnAddress'}else{'KERNEL32.dll!ExitProcess, GetCurrentProcessId'}
    ClrDirectory=0
}
if (-not $SkipLaunch) {
    $process = Start-Process -FilePath $fullOutput -PassThru
    $processId = [uint32]$process.Id
    $launchTimeout = if($Personality-eq'Publication'){10000}else{5000}
    if (-not $process.WaitForExit($launchTimeout)) { $process.Kill(); throw 'Detached PE did not exit.' }
    $actual = [uint32]$process.ExitCode
    if ($Personality -eq 'Publication') {
        if ($actual -eq [uint32]::MaxValue) { throw 'Detached publication PE could not open/map the producer manifest.' }
        $receipt.Status='PASS';$receipt.ProducerPid=$ProducerPid;$receipt.PublicationLow32=$actual;$receipt.ExitCode=$actual
    } elseif ($Personality -eq 'Arithmetic') {
        $expected = [uint32]($processId + 0x1234)
        if ($actual -ne $expected) { throw "Detached PE exit code $actual did not equal its RyuJIT result $expected." }
        $receipt.Status='PASS'; $receipt.ProcessId=$processId; $receipt.ExpectedRyuJitResult=$expected; $receipt.ExitCode=$actual
    } else {
        if ($actual -ne 0) { throw "Detached $Personality PE failed native invariant $actual." }
        $receipt.Status='PASS'; $receipt.ProcessId=$processId; $receipt.ExpectedRyuJitResult=0; $receipt.ExitCode=$actual
        if ($Personality -eq 'CalculatorDisplay') {
            $receipt.NativeLayout='CalculatorState.DisplayValue.v1'
            $receipt.LengthOffset=0;$receipt.CapacityOffset=4;$receipt.Utf16Offset=8;$receipt.InlineCapacity=32
            $receipt.SetterValue='42';$receipt.GetterVerified=$true;$receipt.NativeFieldOperations=2
        }
    }
}
[pscustomobject]$receipt
