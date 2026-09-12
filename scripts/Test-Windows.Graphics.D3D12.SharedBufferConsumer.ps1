[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SharedResourceName,
    [Parameter(Mandatory)][string] $SharedFenceName,
    [Parameter(Mandatory)][ValidateRange(1,16777216)][int] $ValidBytes,
    [Parameter(Mandatory)][string] $ExpectedSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:DelegateAssembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('SMADirect.ConsumerDelegates.' + [Guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$script:DelegateModule = $script:DelegateAssembly.DefineDynamicModule('SMADirect.ConsumerDelegates')
$script:DelegateOrdinal = 0

function New-CallType([Type]$ReturnType,[Type[]]$ParameterTypes) {
    $script:DelegateOrdinal++
    $type=$script:DelegateModule.DefineType("ConsumerCall$($script:DelegateOrdinal)",[Reflection.TypeAttributes]'Class,Public,Sealed,AnsiClass,AutoClass',[MulticastDelegate])
    $ctor=$type.DefineConstructor([Reflection.MethodAttributes]'RTSpecialName,HideBySig,Public',[Reflection.CallingConventions]::Standard,[Type[]]@([object],[IntPtr]))
    $ctor.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $invoke=$type.DefineMethod('Invoke',[Reflection.MethodAttributes]'Public,HideBySig,NewSlot,Virtual',$ReturnType,$ParameterTypes)
    $invoke.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $type.CreateType()
}
function Get-Call([IntPtr]$Address,[Type]$ReturnType,[Type[]]$ParameterTypes) {
    [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($Address,(New-CallType $ReturnType $ParameterTypes))
}
function Get-ComCall([IntPtr]$Instance,[int]$Index,[Type]$ReturnType,[Type[]]$ParameterTypes) {
    $vtable=[Runtime.InteropServices.Marshal]::ReadIntPtr($Instance)
    Get-Call ([Runtime.InteropServices.Marshal]::ReadIntPtr($vtable,$Index*[IntPtr]::Size)) $ReturnType $ParameterTypes
}
function New-Block([int]$Size) {
    $pointer=[Runtime.InteropServices.Marshal]::AllocHGlobal($Size)
    [Runtime.InteropServices.Marshal]::Copy([byte[]]::new($Size),0,$pointer,$Size)
    $pointer
}
function New-GuidBlock([Guid]$Value) {
    $pointer=New-Block 16
    [Runtime.InteropServices.Marshal]::Copy($Value.ToByteArray(),0,$pointer,16)
    $pointer
}
function Assert-HResult([int]$Value,[string]$Operation) {
    if($Value-lt 0){$bits=[BitConverter]::ToUInt32([BitConverter]::GetBytes($Value),0);throw "$Operation failed: 0x$($bits.ToString('X8'))"}
}

$blocks=[Collections.Generic.List[IntPtr]]::new()
$objects=[Collections.Generic.List[IntPtr]]::new()
$handles=[Collections.Generic.List[IntPtr]]::new()
$d3d12=[IntPtr]::Zero
$kernel32=[IntPtr]::Zero
try {
    $d3d12=[Runtime.InteropServices.NativeLibrary]::Load('d3d12.dll')
    $createDevice=Get-Call ([Runtime.InteropServices.NativeLibrary]::GetExport($d3d12,'D3D12CreateDevice')) ([int]) ([Type[]]@([IntPtr],[uint32],[IntPtr],[IntPtr]))
    $deviceIid=New-GuidBlock ([Guid]'189819F1-1DB6-4B57-BE54-1821339B85F7');$blocks.Add($deviceIid)
    $deviceOut=New-Block 8;$blocks.Add($deviceOut)
    Assert-HResult ([int]$createDevice.DynamicInvoke([IntPtr]::Zero,[uint32]0xB000,$deviceIid,$deviceOut)) 'D3D12CreateDevice'
    $device=[Runtime.InteropServices.Marshal]::ReadIntPtr($deviceOut);$objects.Add($device)

    $resourceIid=New-GuidBlock ([Guid]'696442BE-A72E-4059-BC79-5B5C98040FAD');$blocks.Add($resourceIid)
    $fenceIid=New-GuidBlock ([Guid]'0A753DCF-C4D8-4B91-ADF6-BE5A60D95A76');$blocks.Add($fenceIid)
    $openByName=Get-ComCall $device 33 ([int]) ([Type[]]@([IntPtr],[IntPtr],[uint32],[IntPtr]))
    $openShared=Get-ComCall $device 32 ([int]) ([Type[]]@([IntPtr],[IntPtr],[IntPtr],[IntPtr]))
    function Open-Shared([string]$Name,[IntPtr]$Iid) {
        $namePointer=[Runtime.InteropServices.Marshal]::StringToHGlobalUni($Name);$blocks.Add($namePointer)
        $handleOut=New-Block 8;$blocks.Add($handleOut)
        Assert-HResult ([int]$openByName.DynamicInvoke($device,$namePointer,[uint32]0x10000000,$handleOut)) "OpenSharedHandleByName($Name)"
        $handle=[Runtime.InteropServices.Marshal]::ReadIntPtr($handleOut);$handles.Add($handle)
        $objectOut=New-Block 8;$blocks.Add($objectOut)
        Assert-HResult ([int]$openShared.DynamicInvoke($device,$handle,$Iid,$objectOut)) "OpenSharedHandle($Name)"
        $object=[Runtime.InteropServices.Marshal]::ReadIntPtr($objectOut);$objects.Add($object)
        $object
    }
    $sharedResource=Open-Shared $SharedResourceName $resourceIid
    $sharedFence=Open-Shared $SharedFenceName $fenceIid
    $producerCompletion=[Threading.AutoResetEvent]::new($false)
    try {
        $setProducerCompletion=Get-ComCall $sharedFence 9 ([int]) ([Type[]]@([IntPtr],[uint64],[IntPtr]))
        Assert-HResult ([int]$setProducerCompletion.DynamicInvoke($sharedFence,[uint64]1,$producerCompletion.SafeWaitHandle.DangerousGetHandle())) 'Wait for producer publication'
        if(!$producerCompletion.WaitOne(10000)){throw 'Timed out waiting for producer publication fence.'}
    } finally {$producerCompletion.Dispose()}

    $capacity=[int](($ValidBytes+4095)-band(-bnot 4095))
    $heap=New-Block 20;$blocks.Add($heap);[Runtime.InteropServices.Marshal]::WriteInt32($heap,0,3);[Runtime.InteropServices.Marshal]::WriteInt32($heap,12,1);[Runtime.InteropServices.Marshal]::WriteInt32($heap,16,1)
    $desc=New-Block 56;$blocks.Add($desc);[Runtime.InteropServices.Marshal]::WriteInt32($desc,0,1);[Runtime.InteropServices.Marshal]::WriteInt64($desc,16,$capacity);[Runtime.InteropServices.Marshal]::WriteInt32($desc,24,1);[Runtime.InteropServices.Marshal]::WriteInt16($desc,28,1);[Runtime.InteropServices.Marshal]::WriteInt16($desc,30,1);[Runtime.InteropServices.Marshal]::WriteInt32($desc,36,1);[Runtime.InteropServices.Marshal]::WriteInt32($desc,44,1)
    $readbackOut=New-Block 8;$blocks.Add($readbackOut)
    $createResource=Get-ComCall $device 27 ([int]) ([Type[]]@([IntPtr],[IntPtr],[uint32],[IntPtr],[uint32],[IntPtr],[IntPtr],[IntPtr]))
    Assert-HResult ([int]$createResource.DynamicInvoke($device,$heap,[uint32]0,$desc,[uint32]0x400,[IntPtr]::Zero,$resourceIid,$readbackOut)) 'Create consumer readback'
    $readback=[Runtime.InteropServices.Marshal]::ReadIntPtr($readbackOut);$objects.Add($readback)

    $queueIid=New-GuidBlock ([Guid]'0EC870A6-5D7E-4C22-8CFC-5BAAE07616ED');$blocks.Add($queueIid)
    $allocatorIid=New-GuidBlock ([Guid]'6102DEE4-AF59-4B09-B999-B44D73F09B24');$blocks.Add($allocatorIid)
    $listIid=New-GuidBlock ([Guid]'5B160D0F-AC1B-4185-8BA8-B3AE42A5A455');$blocks.Add($listIid)
    $queueDesc=New-Block 16;$blocks.Add($queueDesc);[Runtime.InteropServices.Marshal]::WriteInt32($queueDesc,0,3);[Runtime.InteropServices.Marshal]::WriteInt32($queueDesc,12,1)
    $queueOut=New-Block 8;$allocatorOut=New-Block 8;$listOut=New-Block 8;$localFenceOut=New-Block 8;@($queueOut,$allocatorOut,$listOut,$localFenceOut)|%{$blocks.Add($_)}
    $createQueue=Get-ComCall $device 8 ([int]) ([Type[]]@([IntPtr],[IntPtr],[IntPtr],[IntPtr]));Assert-HResult ([int]$createQueue.DynamicInvoke($device,$queueDesc,$queueIid,$queueOut)) 'Create consumer queue';$queue=[Runtime.InteropServices.Marshal]::ReadIntPtr($queueOut);$objects.Add($queue)
    $createAllocator=Get-ComCall $device 9 ([int]) ([Type[]]@([IntPtr],[uint32],[IntPtr],[IntPtr]));Assert-HResult ([int]$createAllocator.DynamicInvoke($device,[uint32]3,$allocatorIid,$allocatorOut)) 'Create consumer allocator';$allocator=[Runtime.InteropServices.Marshal]::ReadIntPtr($allocatorOut);$objects.Add($allocator)
    $createList=Get-ComCall $device 12 ([int]) ([Type[]]@([IntPtr],[uint32],[uint32],[IntPtr],[IntPtr],[IntPtr],[IntPtr]));Assert-HResult ([int]$createList.DynamicInvoke($device,[uint32]0,[uint32]3,$allocator,[IntPtr]::Zero,$listIid,$listOut)) 'Create consumer list';$list=[Runtime.InteropServices.Marshal]::ReadIntPtr($listOut);$objects.Add($list)
    $copy=Get-ComCall $list 15 ([void]) ([Type[]]@([IntPtr],[IntPtr],[uint64],[IntPtr],[uint64],[uint64]));$copy.DynamicInvoke($list,$readback,[uint64]0,$sharedResource,[uint64]0,[uint64]$ValidBytes)
    $close=Get-ComCall $list 9 ([int]) ([Type[]]@([IntPtr]));Assert-HResult ([int]$close.DynamicInvoke($list)) 'Close consumer list'
    $listArray=New-Block 8;$blocks.Add($listArray);[Runtime.InteropServices.Marshal]::WriteIntPtr($listArray,$list)
    $execute=Get-ComCall $queue 10 ([void]) ([Type[]]@([IntPtr],[uint32],[IntPtr]));$execute.DynamicInvoke($queue,[uint32]1,$listArray)
    $createFence=Get-ComCall $device 36 ([int]) ([Type[]]@([IntPtr],[uint64],[uint32],[IntPtr],[IntPtr]));Assert-HResult ([int]$createFence.DynamicInvoke($device,[uint64]0,[uint32]0,$fenceIid,$localFenceOut)) 'Create consumer completion fence';$localFence=[Runtime.InteropServices.Marshal]::ReadIntPtr($localFenceOut);$objects.Add($localFence)
    $signal=Get-ComCall $queue 14 ([int]) ([Type[]]@([IntPtr],[IntPtr],[uint64]));Assert-HResult ([int]$signal.DynamicInvoke($queue,$localFence,[uint64]1)) 'Signal consumer completion'
    $completion=[Threading.AutoResetEvent]::new($false);try{$setCompletion=Get-ComCall $localFence 9 ([int]) ([Type[]]@([IntPtr],[uint64],[IntPtr]));Assert-HResult ([int]$setCompletion.DynamicInvoke($localFence,[uint64]1,$completion.SafeWaitHandle.DangerousGetHandle())) 'Set consumer completion';if(!$completion.WaitOne(10000)){throw 'Timed out waiting for consumer copy.'}}finally{$completion.Dispose()}
    $mappedOut=New-Block 8;$blocks.Add($mappedOut);$map=Get-ComCall $readback 8 ([int]) ([Type[]]@([IntPtr],[uint32],[IntPtr],[IntPtr]));Assert-HResult ([int]$map.DynamicInvoke($readback,[uint32]0,[IntPtr]::Zero,$mappedOut)) 'Map consumer readback';$mapped=[Runtime.InteropServices.Marshal]::ReadIntPtr($mappedOut)
    $bytes=[byte[]]::new($ValidBytes);[Runtime.InteropServices.Marshal]::Copy($mapped,$bytes,0,$bytes.Length);$unmap=Get-ComCall $readback 9 ([void]) ([Type[]]@([IntPtr],[uint32],[IntPtr]));$unmap.DynamicInvoke($readback,[uint32]0,[IntPtr]::Zero)
    $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));if($actual-cne$ExpectedSha256){throw "Cross-process hash mismatch: $actual"}
    [pscustomobject]@{Status='PASS';ConsumerPid=$PID;ValidBytes=$ValidBytes;ExpectedSha256=$ExpectedSha256;ObservedSha256=$actual;Binding='Open once by NT name; resource and fence pinned for receipt';AuthoredCSharp=0}
}
finally {
    $kernel32=[Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
    try{$closeHandle=Get-Call ([Runtime.InteropServices.NativeLibrary]::GetExport($kernel32,'CloseHandle')) ([bool]) ([Type[]]@([IntPtr]));foreach($handle in $handles){if($handle-ne[IntPtr]::Zero){[void]$closeHandle.DynamicInvoke($handle)}}}finally{[Runtime.InteropServices.NativeLibrary]::Free($kernel32)}
    for($index=$objects.Count-1;$index-ge0;$index--){$object=$objects[$index];if($object-ne[IntPtr]::Zero){$release=Get-ComCall $object 2 ([uint32]) ([Type[]]@([IntPtr]));[void]$release.DynamicInvoke($object)}}
    foreach($block in $blocks){if($block-ne[IntPtr]::Zero){[Runtime.InteropServices.Marshal]::FreeHGlobal($block)}}
    if($d3d12-ne[IntPtr]::Zero){[Runtime.InteropServices.NativeLibrary]::Free($d3d12)}
}
