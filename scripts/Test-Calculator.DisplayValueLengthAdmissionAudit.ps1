[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This audit deliberately distinguishes a correct SMA-site replacement from a
# CLR-free native closure. It is observation only: do not alter the lowering
# to make this specimen cleaner before the JIT host exists.
$redirect = & (Join-Path $PSScriptRoot 'Test-Calculator.DisplayValueSiteRedirect.ps1') `
    -AccessNodeId 1264 `
    -ExpectedAccessExtent '$state.DisplayValue.Length' `
    -Member Length `
    -ExpectedReceiver Object `
    -ProbeMemberName '__SMADirectLength1264__' `
    -ReplacementKind NativeUInt32Length `
    -ExpectedResult 2

if ($redirect.Status -cne 'PASS' -or -not $redirect.BinderRemoved -or
    -not $redirect.ReceiverRepresentationRewritten) {
    throw 'The authentic SMA-site replacement prerequisite failed.'
}

$usesMarshal = $redirect.ReplacementExpression -match 'ReadInt32'
if (-not $usesMarshal) { throw 'The audit expected Marshal.ReadInt32 in the current replacement.' }

[pscustomobject][ordered]@{
    Status = 'OBSERVED_NOT_ADMITTED'
    AccessNodeId = $redirect.AccessNodeId
    DynamicOrdinal = $redirect.DynamicOrdinal
    AuthenticSmaBinderRemoved = $redirect.BinderRemoved
    ReceiverRepresentationRewritten = $redirect.ReceiverRepresentationRewritten
    ReplacementMechanism = 'System.Runtime.InteropServices.Marshal.ReadInt32(IntPtr, Int32)'
    DependencyBucket = 'CLR_RUNTIME'
    NativeClosureAdmitted = $false
    Reason = 'The replacement executes through Marshal, not an emitted native pointer-load or declared native helper.'
    NextRequiredClosure = 'Observe this dependency through the JIT host; do not alter the Calculator lowering first.'
}
