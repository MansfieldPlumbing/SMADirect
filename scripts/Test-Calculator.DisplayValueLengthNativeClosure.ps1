[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$redirect = & (Join-Path $PSScriptRoot 'Test-Calculator.DisplayValueSiteRedirect.ps1') `
    -AccessNodeId 1264 `
    -ExpectedAccessExtent '$state.DisplayValue.Length' `
    -Member Length `
    -ExpectedReceiver Object `
    -ProbeMemberName '__SMADirectLength1264__' `
    -ReplacementKind NativeUInt32Length `
    -ExpectedResult 2

if ($redirect.Status -cne 'PASS' -or -not $redirect.BinderRemoved -or
    -not $redirect.ReceiverRepresentationRewritten -or
    -not $redirect.NativeClosureExecuted -or
    $redirect.ManagedStringMaterialized -or $redirect.NativeReadResult -ne 2) {
    throw 'DisplayValue.Length native consumer closure did not satisfy its receipt.'
}

[pscustomobject]@{
    Status='PASS'
    AccessNodeId=$redirect.AccessNodeId
    DynamicOrdinal=$redirect.DynamicOrdinal
    BinderKind=$redirect.BinderKind
    Member='DisplayValue.Length'
    Receiver='native CalculatorState pointer'
    NativeOperation='uint32 load at LengthOffset 0'
    NativeReadResult=$redirect.NativeReadResult
    BinderRemoved=$redirect.BinderRemoved
    ReceiverRepresentationRewritten=$redirect.ReceiverRepresentationRewritten
    NativeClosureExecuted=$redirect.NativeClosureExecuted
    OriginalAccessSiteRedirected=$redirect.OriginalAccessSiteRedirected
    ManagedStringMaterialized=$redirect.ManagedStringMaterialized
    ManagedResultBridgeRemainingGlobally=$true
    MeasureTextClosed=$false
    DrawTextClosed=$false
    PresentationInputLifetimeClosed=$false
    CompleteCalculatorApplication=$false
}
