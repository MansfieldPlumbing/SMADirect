[CmdletBinding()]
param(
    [string] $MemoryMapName = 'SMADirect_AstTransport'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mapping = [IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting(
    $MemoryMapName,
    [IO.MemoryMappedFiles.MemoryMappedFileRights]::Read)
$accessor = $mapping.CreateViewAccessor(0, 0, [IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read)
$temporaryPayload = Join-Path ([IO.Path]::GetTempPath()) (
    'smadirect-ast-' + [Guid]::NewGuid().ToString('N') + '.bin')

try {
    $magic = $accessor.ReadUInt32(0)
    $nodeCount = $accessor.ReadInt32(4)
    $typeCount = $accessor.ReadInt32(8)
    $position = $accessor.ReadInt32(12)
    if ($magic -ne [uint32]0x05700001) { throw ('Unexpected AST transport magic 0x{0:X8}.' -f $magic) }

    for ($index = 0; $index -lt $nodeCount; $index++) {
        $payloadLength = $accessor.ReadInt32($position + 28)
        if ($payloadLength -lt 0) { throw "Negative payload length at node $index." }
        $position += 36 + $payloadLength
    }

    $transportImage = [byte[]]::new($position)
    $read = $accessor.ReadArray(0, $transportImage, 0, $transportImage.Length)
    if ($read -ne $transportImage.Length) { throw 'The complete AST transport image was not readable.' }
    [IO.File]::WriteAllBytes($temporaryPayload, $transportImage)
    $sourceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($transportImage))

    $receiptId = [Guid]::NewGuid().ToString('N')
    $resourceName = "Global\SMADirect_AstBlit_$receiptId"
    $fenceName = "Global\SMADirect_AstFence_$receiptId"
    $readyName = "Local\SMADirect_AstReady_$receiptId"
    $releaseName = "Local\SMADirect_AstRelease_$receiptId"
    $ready = [Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$readyName)
    $release = [Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$releaseName)
    $producer = $null
    try {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = (Get-Process -Id $PID).Path
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in @(
            '-NoProfile','-File',(Join-Path $PSScriptRoot 'Test-Windows.Graphics.D3D12.SystemMemory.ps1'),
            '-PayloadPath',$temporaryPayload,'-SharedResourceName',$resourceName,
            '-SharedFenceName',$fenceName,'-ReadyEventName',$readyName,'-ReleaseEventName',$releaseName)) {
            [void]$start.ArgumentList.Add($argument)
        }
        $producer = [Diagnostics.Process]::Start($start)
        if (!$ready.WaitOne(15000)) {
            throw 'Timed out waiting for the independent D3D12 producer.'
        }

        $consumerOutput = @(& (Join-Path $PSScriptRoot 'Test-Windows.Graphics.D3D12.SharedBufferConsumer.ps1') `
            -SharedResourceName $resourceName -SharedFenceName $fenceName `
            -ValidBytes $transportImage.Length -ExpectedSha256 $sourceHash)
        $consumerReceipt = $consumerOutput | Where-Object {
            if ($null -eq $_) { return $false }
            $statusProperty = $_.PSObject.Properties['Status']
            $null -ne $statusProperty -and $statusProperty.Value -eq 'PASS'
        } | Select-Object -Last 1
        if ($null -eq $consumerReceipt) {
            throw ('Independent consumer produced no PASS receipt: ' + ($consumerOutput -join '; '))
        }
        if ($consumerReceipt.Status -ne 'PASS' -or $consumerReceipt.ObservedSha256 -cne $sourceHash) {
            throw 'The independent D3D12 consumer did not reconstruct the exact SMA population image.'
        }
    }
    finally {
        [void]$release.Set()
        if ($producer -and !$producer.WaitForExit(15000)) { $producer.Kill($true); $producer.WaitForExit() }
        $ready.Dispose()
        $release.Dispose()
    }
    if ($producer.ExitCode -ne 0) {
        throw "Independent producer failed: $($producer.StandardError.ReadToEnd())"
    }

    [pscustomobject]@{
        Status = 'PASS'
        SmaContribution = 'Authentic PowerShell AST node kinds, source extents, and parent topology'
        DirectPortContribution = 'Packed population identity and long-lived publication schema'
        D3D12Contribution = 'Producer UPLOAD -> named shared DEFAULT blit; independent consumer READBACK'
        ConsumerContribution = 'Separate process; one-time named-handle bind and byte-fidelity verification'
        RyuJitContribution = 'Not exercised by this receipt; machine-code emission remains a separate stage'
        AstNodes = $nodeCount
        AstTypes = $typeCount
        ValidBytes = $transportImage.Length
        PayloadSha256 = $sourceHash
        GpuCopiedPayloadSha256 = $consumerReceipt.ObservedSha256
        ProducerPid = $producer.Id
        ConsumerPid = $consumerReceipt.ConsumerPid
        ProducerScratchHeap = 'UPLOAD'
        ProducerBlitHeap = 'DEFAULT'
        ConsumerScratchHeap = 'READBACK'
        ResourceName = $resourceName
        FenceName = $fenceName
        AuthoredCSharp = 0
    }
}
finally {
    $accessor.Dispose()
    $mapping.Dispose()
    if ([IO.File]::Exists($temporaryPayload)) { [IO.File]::Delete($temporaryPayload) }
}
