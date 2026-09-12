Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Compiler\Win32.ps1')

$kernel = Open-NativeLibrary 'kernel32.dll'
$block = [IntPtr]::Zero
try {
    $getPidAddress = Get-NativeExport $kernel 'GetCurrentProcessId'
    $getPid = Get-NativeCall $getPidAddress ([uint32]) ([Type[]]@())
    $nativePid = [uint32]$getPid.DynamicInvoke()
    if ($nativePid -ne [uint32]$PID) { throw "Native PID $nativePid did not equal host PID $PID." }

    $block = New-NativeBlock 16
    for($offset=0;$offset-lt16;$offset++) {
        if([Runtime.InteropServices.Marshal]::ReadByte($block,$offset)-ne0){throw 'Native block was not zeroed.'}
    }

    [pscustomobject]@{
        Status='PASS';NativePid=$nativePid;NativeExport=$getPidAddress
        ZeroedBlockBytes=16;Cartridges=5;AuthoredCSharp=0
    }
} finally {
    Remove-NativeBlock $block
    Close-NativeLibrary $kernel
}
