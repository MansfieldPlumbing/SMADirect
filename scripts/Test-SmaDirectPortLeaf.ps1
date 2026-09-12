param([switch]$PassThru)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Compiler/Win32.NativeCall.ps1')
. (Join-Path $root 'Compiler/Win32.NativeLibrary.ps1')

# This is the same export and delegate shape used by New-DirectPortCanvas.
# The specimen invokes it once without creating a window or another dispatch layer.
$source = 'param([System.Delegate]$NativeCall) $NativeCall.DynamicInvoke([IntPtr]::Zero)'
$specimen = & (Join-Path $PSScriptRoot 'Test-SmaRyuJitSpine.ps1') `
    -Source $source -SpecimenName DirectPortGetModuleHandleProbe -PassThru
$kernel = Open-NativeLibrary 'kernel32.dll'
try {
    $export = Get-NativeExport $kernel 'GetModuleHandleW'
    $nativeCall = Get-NativeCall $export ([IntPtr]) ([Type[]]@([IntPtr]))
    $result = @($specimen.ScriptBlock.Invoke([object[]]@($nativeCall)))
    if ($result.Count -ne 1) { throw "DirectPort leaf returned $($result.Count) values; expected one module handle." }
    $actual = [IntPtr]$result[0].PSObject.BaseObject
    $process = [Diagnostics.Process]::GetCurrentProcess()
    try { $expected = $process.MainModule.BaseAddress } finally { $process.Dispose() }
    if ($actual -eq [IntPtr]::Zero -or $actual -ne $expected) {
        throw "GetModuleHandleW returned $actual; expected the current process image at $expected."
    }
    $receipt = [pscustomobject][ordered]@{
        Status = 'PASS'
        Source = 'POWERSHELL'
        AuthenticSma = 'PASS'
        RyuJit = 'PASS'
        NativeBoundary = 'kernel32.dll!GetModuleHandleW'
        CurrentCarrier = 'Src/SMAScripts/DirectPort.ps1:313'
        CarrierMechanism = 'Get-NativeCall / Marshal.GetDelegateForFunctionPointer / Delegate.DynamicInvoke'
        Execution = 'SMA ScriptBlock.Invoke of unchanged specimen'
        ModuleHandle = $actual
        NativeRuntimeClosure = 'UNKNOWN; successful hosted invocation does not establish native detachment'
        Specimen = $specimen
    }
    if ($PassThru) { $receipt } else { $receipt | Select-Object -ExcludeProperty Specimen }
} finally {
    Close-NativeLibrary $kernel
}
