[CmdletBinding()]
param(
    [ValidateRange(4096, 16777216)][int] $Bytes = 65536,
    [string] $PayloadPath,
    [string] $SharedResourceName,
    [string] $SharedFenceName,
    [string] $ReadyEventName,
    [string] $ReleaseEventName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$payloadBytes = $null
if ($PayloadPath) {
    $payloadBytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($PayloadPath))
    if ($payloadBytes.Length -gt 16777216) { throw 'Payload exceeds the 16 MiB receipt limit.' }
    $Bytes = [Math]::Max(4096, [int](($payloadBytes.Length + 4095) -band (-bnot 4095)))
}
$readyEvent = $null
$releaseEvent = $null
if ($ReadyEventName) { $readyEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, $ReadyEventName) }
if ($ReleaseEventName) { $releaseEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, $ReleaseEventName) }

$script:DelegateAssembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('SMADirect.NativeDelegates.' + [Guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$script:DelegateModule = $script:DelegateAssembly.DefineDynamicModule('SMADirect.NativeDelegates')
$script:DelegateOrdinal = 0

function New-NativeDelegateType {
    param([Type] $ReturnType, [Type[]] $ParameterTypes)
    $script:DelegateOrdinal++
    $type = $script:DelegateModule.DefineType(
        "NativeCall$($script:DelegateOrdinal)",
        [Reflection.TypeAttributes]'Class, Public, Sealed, AnsiClass, AutoClass',
        [MulticastDelegate])
    $constructor = $type.DefineConstructor(
        [Reflection.MethodAttributes]'RTSpecialName, HideBySig, Public',
        [Reflection.CallingConventions]::Standard,
        [Type[]]@([object], [IntPtr]))
    $constructor.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime, Managed')
    $invoke = $type.DefineMethod(
        'Invoke',
        [Reflection.MethodAttributes]'Public, HideBySig, NewSlot, Virtual',
        $ReturnType,
        $ParameterTypes)
    $invoke.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime, Managed')
    $type.CreateType()
}

function Get-NativeCall {
    param([IntPtr] $Address, [Type] $ReturnType, [Type[]] $ParameterTypes)
    $delegateType = New-NativeDelegateType $ReturnType $ParameterTypes
    [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($Address, $delegateType)
}

function Get-ComCall {
    param([IntPtr] $Instance, [int] $Index, [Type] $ReturnType, [Type[]] $ParameterTypes)
    $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($Instance)
    $address = [Runtime.InteropServices.Marshal]::ReadIntPtr($vtable, $Index * [IntPtr]::Size)
    Get-NativeCall $address $ReturnType $ParameterTypes
}

function New-NativeBlock([int] $Size) {
    $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($Size)
    for ($index = 0; $index -lt $Size; $index++) { [Runtime.InteropServices.Marshal]::WriteByte($pointer, $index, 0) }
    $pointer
}

function New-NativeGuid([Guid] $Guid) {
    $pointer = New-NativeBlock 16
    [Runtime.InteropServices.Marshal]::Copy($Guid.ToByteArray(), 0, $pointer, 16)
    $pointer
}

function Assert-HResult([int] $HResult, [string] $Operation) {
    if ($HResult -lt 0) { throw ('{0} failed with HRESULT 0x{1:X8}.' -f $Operation, [uint32]$HResult) }
}

$allocations = [Collections.Generic.List[IntPtr]]::new()
$device = [IntPtr]::Zero
$resource = [IntPtr]::Zero
$blitResource = [IntPtr]::Zero
$consumerResource = [IntPtr]::Zero
$queue = [IntPtr]::Zero
$allocator = [IntPtr]::Zero
$commandList = [IntPtr]::Zero
$fence = [IntPtr]::Zero
$sharedBlitHandle = [IntPtr]::Zero
$sharedFenceHandle = [IntPtr]::Zero
$d3d12 = [IntPtr]::Zero
try {
    $d3d12 = [Runtime.InteropServices.NativeLibrary]::Load('d3d12.dll')
    $createAddress = [Runtime.InteropServices.NativeLibrary]::GetExport($d3d12, 'D3D12CreateDevice')
    $createDevice = Get-NativeCall $createAddress ([int]) ([Type[]]@([IntPtr], [uint32], [IntPtr], [IntPtr]))

    $deviceIid = New-NativeGuid ([Guid]'189819F1-1DB6-4B57-BE54-1821339B85F7')
    $allocations.Add($deviceIid)
    $deviceOut = New-NativeBlock ([IntPtr]::Size)
    $allocations.Add($deviceOut)
    $hr = $createDevice.DynamicInvoke([IntPtr]::Zero, [uint32]0xB000, $deviceIid, $deviceOut)
    Assert-HResult $hr 'D3D12CreateDevice'
    $device = [Runtime.InteropServices.Marshal]::ReadIntPtr($deviceOut)
    if ($device -eq [IntPtr]::Zero) { throw 'D3D12CreateDevice returned a null device.' }

    $architecture = New-NativeBlock 16
    $allocations.Add($architecture)
    $checkFeature = Get-ComCall $device 13 ([int]) ([Type[]]@([IntPtr], [uint32], [IntPtr], [uint32]))
    $hr = $checkFeature.DynamicInvoke($device, [uint32]1, $architecture, [uint32]16)
    Assert-HResult $hr 'ID3D12Device::CheckFeatureSupport(D3D12_FEATURE_ARCHITECTURE)'
    $tileBased = [Runtime.InteropServices.Marshal]::ReadInt32($architecture, 4) -ne 0
    $uma = [Runtime.InteropServices.Marshal]::ReadInt32($architecture, 8) -ne 0
    $cacheCoherentUma = [Runtime.InteropServices.Marshal]::ReadInt32($architecture, 12) -ne 0

    # D3D12_HEAP_PROPERTIES: UPLOAD. This is discrete-GPU-safe producer scratch.
    $heap = New-NativeBlock 20
    $allocations.Add($heap)
    [Runtime.InteropServices.Marshal]::WriteInt32($heap, 0, 2)
    [Runtime.InteropServices.Marshal]::WriteInt32($heap, 12, 1)
    [Runtime.InteropServices.Marshal]::WriteInt32($heap, 16, 1)

    # D3D12_RESOURCE_DESC: row-major buffer of uint64 lanes.
    $description = New-NativeBlock 56
    $allocations.Add($description)
    [Runtime.InteropServices.Marshal]::WriteInt32($description, 0, 1)       # BUFFER
    [Runtime.InteropServices.Marshal]::WriteInt64($description, 8, 0)       # default alignment
    [Runtime.InteropServices.Marshal]::WriteInt64($description, 16, $Bytes)
    [Runtime.InteropServices.Marshal]::WriteInt32($description, 24, 1)
    [Runtime.InteropServices.Marshal]::WriteInt16($description, 28, 1)
    [Runtime.InteropServices.Marshal]::WriteInt16($description, 30, 1)
    [Runtime.InteropServices.Marshal]::WriteInt32($description, 32, 0)      # DXGI_FORMAT_UNKNOWN
    [Runtime.InteropServices.Marshal]::WriteInt32($description, 36, 1)      # sample count
    [Runtime.InteropServices.Marshal]::WriteInt32($description, 40, 0)
    [Runtime.InteropServices.Marshal]::WriteInt32($description, 44, 1)      # ROW_MAJOR
    [Runtime.InteropServices.Marshal]::WriteInt32($description, 48, 0)

    $resourceIid = New-NativeGuid ([Guid]'696442BE-A72E-4059-BC79-5B5C98040FAD')
    $allocations.Add($resourceIid)
    $resourceOut = New-NativeBlock ([IntPtr]::Size)
    $allocations.Add($resourceOut)
    $createResource = Get-ComCall $device 27 ([int]) ([Type[]]@(
        [IntPtr], [IntPtr], [uint32], [IntPtr], [uint32], [IntPtr], [IntPtr], [IntPtr]))
    $hr = $createResource.DynamicInvoke(
        $device, $heap, [uint32]0, $description, [uint32]0xAC3,
        [IntPtr]::Zero, $resourceIid, $resourceOut)
    Assert-HResult $hr 'ID3D12Device::CreateCommittedResource'
    $resource = [Runtime.InteropServices.Marshal]::ReadIntPtr($resourceOut)
    if ($resource -eq [IntPtr]::Zero) { throw 'CreateCommittedResource returned a null resource.' }

    $mappedOut = New-NativeBlock ([IntPtr]::Size)
    $allocations.Add($mappedOut)
    $emptyReadRange = New-NativeBlock 16
    $allocations.Add($emptyReadRange)
    $map = Get-ComCall $resource 8 ([int]) ([Type[]]@([IntPtr], [uint32], [IntPtr], [IntPtr]))
    $hr = $map.DynamicInvoke($resource, [uint32]0, $emptyReadRange, $mappedOut)
    Assert-HResult $hr 'ID3D12Resource::Map'
    $mapped = [Runtime.InteropServices.Marshal]::ReadIntPtr($mappedOut)
    if ($mapped -eq [IntPtr]::Zero) { throw 'Map returned a null CPU address.' }

    [uint64[]]$written = @()
    [uint64[]]$observed = @()
    if ($null -ne $payloadBytes) {
        if ($payloadBytes.Length -gt 0) {
            [Runtime.InteropServices.Marshal]::Copy($payloadBytes, 0, $mapped, $payloadBytes.Length)
        }
        $copyBytes = [uint64]$payloadBytes.Length
    } else {
        $written = @(
            [uint64]::Parse('534D414449524543', [Globalization.NumberStyles]::HexNumber),
            [uint64]0x54,
            [uint64]::Parse('FEDCBA9889ABCDEF', [Globalization.NumberStyles]::HexNumber))
        for ($index = 0; $index -lt $written.Count; $index++) {
            $signedBits = [BitConverter]::ToInt64([BitConverter]::GetBytes($written[$index]), 0)
            [Runtime.InteropServices.Marshal]::WriteInt64($mapped, $index * 8, $signedBits)
        }
        $observed = for ($index = 0; $index -lt $written.Count; $index++) {
            $signedBits = [Runtime.InteropServices.Marshal]::ReadInt64($mapped, $index * 8)
            [BitConverter]::ToUInt64([BitConverter]::GetBytes($signedBits), 0)
        }
        if (($observed -join ',') -cne ($written -join ',')) { throw 'Mapped uint64 lanes did not round-trip.' }
        $copyBytes = [uint64]($written.Count * 8)
    }

    $gpuAddressCall = Get-ComCall $resource 11 ([uint64]) ([Type[]]@([IntPtr]))
    $gpuAddress = [uint64]$gpuAddressCall.DynamicInvoke($resource)
    if (!$gpuAddress) { throw 'The CPU-visible resource has no GPU virtual address.' }

    # Producer-owned public middle ground: DEFAULT heap, COPY_DEST.
    $defaultHeap = New-NativeBlock 20
    $allocations.Add($defaultHeap)
    [Runtime.InteropServices.Marshal]::WriteInt32($defaultHeap, 0, 1)
    [Runtime.InteropServices.Marshal]::WriteInt32($defaultHeap, 12, 1)
    [Runtime.InteropServices.Marshal]::WriteInt32($defaultHeap, 16, 1)
    $blitOut = New-NativeBlock ([IntPtr]::Size)
    $allocations.Add($blitOut)
    $hr = $createResource.DynamicInvoke($device, $defaultHeap, [uint32]1, $description, [uint32]0x400, [IntPtr]::Zero, $resourceIid, $blitOut)
    Assert-HResult $hr 'Create producer blit resource'
    $blitResource = [Runtime.InteropServices.Marshal]::ReadIntPtr($blitOut)

    # Consumer scratch: READBACK heap, COPY_DEST. This is verification only;
    # another GPU consumer would copy into its own DEFAULT resource instead.
    $readbackHeap = New-NativeBlock 20
    $allocations.Add($readbackHeap)
    [Runtime.InteropServices.Marshal]::WriteInt32($readbackHeap, 0, 3)
    [Runtime.InteropServices.Marshal]::WriteInt32($readbackHeap, 12, 1)
    [Runtime.InteropServices.Marshal]::WriteInt32($readbackHeap, 16, 1)
    $consumerOut = New-NativeBlock ([IntPtr]::Size)
    $allocations.Add($consumerOut)
    $hr = $createResource.DynamicInvoke($device, $readbackHeap, [uint32]0, $description, [uint32]0x400, [IntPtr]::Zero, $resourceIid, $consumerOut)
    Assert-HResult $hr 'Create consumer scratch resource'
    $consumerResource = [Runtime.InteropServices.Marshal]::ReadIntPtr($consumerOut)

    $queueIid = New-NativeGuid ([Guid]'0ec870a6-5d7e-4c22-8cfc-5baae07616ed')
    $allocatorIid = New-NativeGuid ([Guid]'6102dee4-af59-4b09-b999-b44d73f09b24')
    $listIid = New-NativeGuid ([Guid]'5b160d0f-ac1b-4185-8ba8-b3ae42a5a455')
    $fenceIid = New-NativeGuid ([Guid]'0a753dcf-c4d8-4b91-adf6-be5a60d95a76')
    @($queueIid,$allocatorIid,$listIid,$fenceIid) | ForEach-Object { $allocations.Add($_) }

    $queueDescription = New-NativeBlock 16
    $allocations.Add($queueDescription)
    [Runtime.InteropServices.Marshal]::WriteInt32($queueDescription, 0, 3) # COPY queue
    [Runtime.InteropServices.Marshal]::WriteInt32($queueDescription, 12, 1)
    $queueOut = New-NativeBlock ([IntPtr]::Size)
    $allocatorOut = New-NativeBlock ([IntPtr]::Size)
    $listOut = New-NativeBlock ([IntPtr]::Size)
    $fenceOut = New-NativeBlock ([IntPtr]::Size)
    @($queueOut,$allocatorOut,$listOut,$fenceOut) | ForEach-Object { $allocations.Add($_) }

    $createQueue = Get-ComCall $device 8 ([int]) ([Type[]]@([IntPtr],[IntPtr],[IntPtr],[IntPtr]))
    Assert-HResult ($createQueue.DynamicInvoke($device,$queueDescription,$queueIid,$queueOut)) 'CreateCommandQueue'
    $queue = [Runtime.InteropServices.Marshal]::ReadIntPtr($queueOut)
    $createAllocator = Get-ComCall $device 9 ([int]) ([Type[]]@([IntPtr],[uint32],[IntPtr],[IntPtr]))
    Assert-HResult ($createAllocator.DynamicInvoke($device,[uint32]3,$allocatorIid,$allocatorOut)) 'CreateCommandAllocator'
    $allocator = [Runtime.InteropServices.Marshal]::ReadIntPtr($allocatorOut)
    $createList = Get-ComCall $device 12 ([int]) ([Type[]]@([IntPtr],[uint32],[uint32],[IntPtr],[IntPtr],[IntPtr],[IntPtr]))
    Assert-HResult ($createList.DynamicInvoke($device,[uint32]0,[uint32]3,$allocator,[IntPtr]::Zero,$listIid,$listOut)) 'CreateCommandList'
    $commandList = [Runtime.InteropServices.Marshal]::ReadIntPtr($listOut)

    $copyBuffer = Get-ComCall $commandList 15 ([void]) ([Type[]]@([IntPtr],[IntPtr],[uint64],[IntPtr],[uint64],[uint64]))
    [void]$copyBuffer.DynamicInvoke($commandList,$blitResource,[uint64]0,$resource,[uint64]0,$copyBytes)
    $barrier = New-NativeBlock 32
    $allocations.Add($barrier)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($barrier,8,$blitResource)
    [Runtime.InteropServices.Marshal]::WriteInt32($barrier,16,-1)
    [Runtime.InteropServices.Marshal]::WriteInt32($barrier,20,0x400)
    [Runtime.InteropServices.Marshal]::WriteInt32($barrier,24,0x800)
    $resourceBarrier = Get-ComCall $commandList 26 ([void]) ([Type[]]@([IntPtr],[uint32],[IntPtr]))
    [void]$resourceBarrier.DynamicInvoke($commandList,[uint32]1,$barrier)
    [void]$copyBuffer.DynamicInvoke($commandList,$consumerResource,[uint64]0,$blitResource,[uint64]0,$copyBytes)
    $closeList = Get-ComCall $commandList 9 ([int]) ([Type[]]@([IntPtr]))
    Assert-HResult ($closeList.DynamicInvoke($commandList)) 'Close command list'

    $listArray = New-NativeBlock ([IntPtr]::Size)
    $allocations.Add($listArray)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($listArray,$commandList)
    $execute = Get-ComCall $queue 10 ([void]) ([Type[]]@([IntPtr],[uint32],[IntPtr]))
    [void]$execute.DynamicInvoke($queue,[uint32]1,$listArray)

    $createFence = Get-ComCall $device 36 ([int]) ([Type[]]@([IntPtr],[uint64],[uint32],[IntPtr],[IntPtr]))
    Assert-HResult ($createFence.DynamicInvoke($device,[uint64]0,[uint32]1,$fenceIid,$fenceOut)) 'CreateFence'
    $fence = [Runtime.InteropServices.Marshal]::ReadIntPtr($fenceOut)

    $sharedBlitOut = New-NativeBlock ([IntPtr]::Size)
    $sharedFenceOut = New-NativeBlock ([IntPtr]::Size)
    @($sharedBlitOut,$sharedFenceOut) | ForEach-Object { $allocations.Add($_) }
    $sharedResourceNamePointer = if ($SharedResourceName) { [Runtime.InteropServices.Marshal]::StringToHGlobalUni($SharedResourceName) } else { [IntPtr]::Zero }
    $sharedFenceNamePointer = if ($SharedFenceName) { [Runtime.InteropServices.Marshal]::StringToHGlobalUni($SharedFenceName) } else { [IntPtr]::Zero }
    if ($sharedResourceNamePointer -ne [IntPtr]::Zero) { $allocations.Add($sharedResourceNamePointer) }
    if ($sharedFenceNamePointer -ne [IntPtr]::Zero) { $allocations.Add($sharedFenceNamePointer) }
    $createSharedHandle = Get-ComCall $device 31 ([int]) ([Type[]]@([IntPtr],[IntPtr],[IntPtr],[uint32],[IntPtr],[IntPtr]))
    Assert-HResult ($createSharedHandle.DynamicInvoke($device,$blitResource,[IntPtr]::Zero,[uint32]0x10000000,$sharedResourceNamePointer,$sharedBlitOut)) 'CreateSharedHandle(blit)'
    Assert-HResult ($createSharedHandle.DynamicInvoke($device,$fence,[IntPtr]::Zero,[uint32]0x10000000,$sharedFenceNamePointer,$sharedFenceOut)) 'CreateSharedHandle(fence)'
    $sharedBlitHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($sharedBlitOut)
    $sharedFenceHandle = [Runtime.InteropServices.Marshal]::ReadIntPtr($sharedFenceOut)
    if ($sharedBlitHandle -eq [IntPtr]::Zero -or $sharedFenceHandle -eq [IntPtr]::Zero) { throw 'D3D12 returned a null shared handle.' }
    $signal = Get-ComCall $queue 14 ([int]) ([Type[]]@([IntPtr],[IntPtr],[uint64]))
    Assert-HResult ($signal.DynamicInvoke($queue,$fence,[uint64]1)) 'Signal publication fence'
    $completion = [Threading.AutoResetEvent]::new($false)
    try {
        $setCompletion = Get-ComCall $fence 9 ([int]) ([Type[]]@([IntPtr],[uint64],[IntPtr]))
        Assert-HResult ($setCompletion.DynamicInvoke($fence,[uint64]1,$completion.SafeWaitHandle.DangerousGetHandle())) 'SetEventOnCompletion'
        if (!$completion.WaitOne(10000)) { throw 'Timed out waiting for the verification copy.' }
    } finally { $completion.Dispose() }

    $consumerMappedOut = New-NativeBlock ([IntPtr]::Size)
    $allocations.Add($consumerMappedOut)
    $consumerMap = Get-ComCall $consumerResource 8 ([int]) ([Type[]]@([IntPtr],[uint32],[IntPtr],[IntPtr]))
    Assert-HResult ($consumerMap.DynamicInvoke($consumerResource,[uint32]0,[IntPtr]::Zero,$consumerMappedOut)) 'Map consumer scratch'
    $consumerMapped = [Runtime.InteropServices.Marshal]::ReadIntPtr($consumerMappedOut)
    [uint64[]]$copied = @()
    $payloadHash = $null
    $copiedPayloadHash = $null
    if ($null -ne $payloadBytes) {
        $copiedPayload = [byte[]]::new($payloadBytes.Length)
        if ($copiedPayload.Length -gt 0) {
            [Runtime.InteropServices.Marshal]::Copy($consumerMapped, $copiedPayload, 0, $copiedPayload.Length)
        }
        $payloadHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payloadBytes))
        $copiedPayloadHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($copiedPayload))
        if ($copiedPayloadHash -cne $payloadHash) { throw 'GPU broadcast copy did not preserve the payload bytes.' }
    } else {
        $copied = for ($index=0; $index -lt $written.Count; $index++) {
            $bits = [Runtime.InteropServices.Marshal]::ReadInt64($consumerMapped,$index*8)
            [BitConverter]::ToUInt64([BitConverter]::GetBytes($bits),0)
        }
        if (($copied -join ',') -cne ($written -join ',')) { throw 'GPU broadcast copy did not preserve the uint64 lanes.' }
    }
    $consumerUnmap = Get-ComCall $consumerResource 9 ([void]) ([Type[]]@([IntPtr],[uint32],[IntPtr]))
    [void]$consumerUnmap.DynamicInvoke($consumerResource,[uint32]0,[IntPtr]::Zero)
    $unmap = Get-ComCall $resource 9 ([void]) ([Type[]]@([IntPtr], [uint32], [IntPtr]))
    [void]$unmap.DynamicInvoke($resource, [uint32]0, [IntPtr]::Zero)

    $receipt = [pscustomobject]@{
        Status = 'PASS'
        Device = ('0x{0:X}' -f $device.ToInt64())
        Resource = ('0x{0:X}' -f $resource.ToInt64())
        CpuAddress = ('0x{0:X}' -f $mapped.ToInt64())
        GpuVirtualAddress = ('0x{0:X16}' -f $gpuAddress)
        ProducerScratchHeap = 'UPLOAD'
        ProducerBlitHeap = 'DEFAULT'
        ConsumerScratchHeap = 'READBACK'
        Layout = 'ROW_MAJOR'
        TileBasedRenderer = $tileBased
        UMA = $uma
        CacheCoherentUMA = $cacheCoherentUma
        ElementBits = 64
        Bytes = $Bytes
        ValidBytes = [uint64]$copyBytes
        PayloadSha256 = $payloadHash
        GpuCopiedPayloadSha256 = $copiedPayloadHash
        Values = ($observed | ForEach-Object { '0x{0:X16}' -f $_ }) -join ','
        GpuCopiedValues = ($copied | ForEach-Object { '0x{0:X16}' -f $_ }) -join ','
        PublicationFence = 1
        SharedBlitHandle = ('0x{0:X}' -f $sharedBlitHandle.ToInt64())
        SharedFenceHandle = ('0x{0:X}' -f $sharedFenceHandle.ToInt64())
        AuthoredCSharp = 0
        NativeCompiler = 'D3D12 runtime; no MSVC/Clang invocation'
    }
    $receipt
    if ($readyEvent) { [void]$readyEvent.Set() }
    if ($releaseEvent -and !$releaseEvent.WaitOne(30000)) { throw 'Timed out waiting for the cross-process consumer release.' }
}
finally {
    if ($readyEvent) { $readyEvent.Dispose() }
    if ($releaseEvent) { $releaseEvent.Dispose() }
    if ($sharedBlitHandle -ne [IntPtr]::Zero -or $sharedFenceHandle -ne [IntPtr]::Zero) {
        $kernel32 = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
        try {
            $closeHandle = Get-NativeCall ([Runtime.InteropServices.NativeLibrary]::GetExport($kernel32,'CloseHandle')) ([bool]) ([Type[]]@([IntPtr]))
            if ($sharedBlitHandle -ne [IntPtr]::Zero) { [void]$closeHandle.DynamicInvoke($sharedBlitHandle) }
            if ($sharedFenceHandle -ne [IntPtr]::Zero) { [void]$closeHandle.DynamicInvoke($sharedFenceHandle) }
        } finally { [Runtime.InteropServices.NativeLibrary]::Free($kernel32) }
    }
    foreach ($instance in @($fence,$commandList,$allocator,$queue,$consumerResource,$blitResource,$resource)) {
        if ($instance -ne [IntPtr]::Zero) {
            $release = Get-ComCall $instance 2 ([uint32]) ([Type[]]@([IntPtr]))
            [void]$release.DynamicInvoke($instance)
        }
    }
    if ($device -ne [IntPtr]::Zero) {
        $release = Get-ComCall $device 2 ([uint32]) ([Type[]]@([IntPtr]))
        [void]$release.DynamicInvoke($device)
    }
    foreach ($pointer in $allocations) { if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($pointer) } }
    if ($d3d12 -ne [IntPtr]::Zero) { [Runtime.InteropServices.NativeLibrary]::Free($d3d12) }
}
