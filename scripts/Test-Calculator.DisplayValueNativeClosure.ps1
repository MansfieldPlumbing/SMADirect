[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repo 'Conformance\Calculator.ps1'
$emitterPath = Join-Path $repo 'Compiler\Emit-RyuJitDetachedPE.ps1'
$portsPath = Join-Path $repo 'Compiler\DirectPort.ResolutionPorts.psm1'
$outputPath = Join-Path $repo 'Build\Windows\Calculator.DisplayValue.Receipt.exe'
$siteRedirectPath = Join-Path $PSScriptRoot 'Test-Calculator.DisplayValueSiteRedirect.ps1'
Import-Module $portsPath -Force

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $sourcePath, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count) { throw "Calculator parse failed: $($parseErrors[0].Message)" }

$owners = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.TypeDefinitionAst] -and
    $node.Name -ceq 'CalculatorState'
}, $true))
if ($owners.Count -ne 1) { throw 'Expected exactly one CalculatorState declaration.' }

$properties = @($owners[0].Members | Where-Object {
    $_ -is [System.Management.Automation.Language.PropertyMemberAst] -and
    $_.Name -ceq 'DisplayValue'
})
if ($properties.Count -ne 1) { throw 'Expected exactly one CalculatorState.DisplayValue declaration.' }
$property = $properties[0]
if ($property.PropertyType.TypeName.FullName -cne 'string') {
    throw 'CalculatorState.DisplayValue is no longer declared as string.'
}
if (-not $property.InitialValue -or $property.InitialValue.Extent.Text -cne '"0"') {
    throw 'CalculatorState.DisplayValue initializer is no longer the admitted "0" literal.'
}

$allNodes = @($ast.FindAll({ param($node) $true }, $true) |
    Sort-Object { $_.Extent.StartOffset }, { $_.Extent.EndOffset }, { $_.GetType().FullName })
$declarationNodeId = [uint64][array]::IndexOf($allNodes, $property)
if ($declarationNodeId -eq 0 -or $declarationNodeId -eq [uint64]::MaxValue) { throw 'DisplayValue declaration node identity is invalid.' }
$declarationText = 'CalculatorState.DisplayValue:string:auto'
$declarationDigest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($declarationText))
$projectionId = [BitConverter]::ToUInt64($declarationDigest, 0)
$capability = [BitConverter]::ToUInt64($declarationDigest, 8)
$projection = New-DirectPortStructuralProjection -ProjectionId $projectionId -SourceNodeId $declarationNodeId `
    -Kind Property -OwnerIdentity CalculatorState -MemberIdentity DisplayValue `
    -Signature $declarationText -Capability $capability `
    -EvidenceSha256 ([Convert]::ToHexString($declarationDigest)) -PublicationValue 1

$receipt = & $emitterPath -Personality CalculatorDisplay -OutputPath $outputPath
$siteRedirect = & $siteRedirectPath
if ($siteRedirect.DeclarationNodeId -ne $declarationNodeId) { throw 'Redirect declaration does not match the structural projection.' }
if ($receipt.Status -cne 'PASS') { throw 'Detached DisplayValue receipt did not pass.' }
if ($receipt.ClrDirectory -ne 0) { throw 'Detached DisplayValue PE unexpectedly contains a CLR directory.' }
if ($receipt.ExitCode -ne 0 -or -not $receipt.GetterVerified) {
    throw 'Detached DisplayValue setter/getter round trip failed.'
}
if ($receipt.NativeLayout -cne 'CalculatorState.DisplayValue.v1' -or
    $receipt.LengthOffset -ne 0 -or $receipt.CapacityOffset -ne 4 -or
    $receipt.Utf16Offset -ne 8 -or $receipt.InlineCapacity -ne 32) {
    throw 'Detached DisplayValue native layout differs from the admitted layout.'
}

$layoutDigest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(
    'CalculatorState.DisplayValue.v1|Length=0|Capacity=4|Utf16=8|Chars=32|Overflow=Reject'))
$layoutId = [BitConverter]::ToUInt64($layoutDigest, 0)
$layout = New-DirectPortNativeLayout -LayoutId $layoutId -ProjectionId $projectionId `
    -LayoutIdentity $receipt.NativeLayout -LengthOffset 0 -CapacityOffset 4 -StorageOffset 8 `
    -StorageCapacityChars 32 -OverflowBehavior Reject -Encoding UTF-16LE `
    -EvidenceSha256 ([Convert]::ToHexString($layoutDigest)) -PublicationValue 1
$bindingDigest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(
    ('{0}|{1}|{2}|{3}' -f $siteRedirect.AccessNodeId, $siteRedirect.DynamicOrdinal, $layoutId, $receipt.Sha256)))
$bindingId = [BitConverter]::ToUInt64($bindingDigest, 0)
$binding = New-DirectPortLoweringBinding -BindingId $bindingId -SourceNodeId $siteRedirect.AccessNodeId `
    -DeclarationNodeId $declarationNodeId -DynamicOrdinal $siteRedirect.DynamicOrdinal `
    -ProjectionId $projectionId -LayoutId $layoutId -NativeArtifactSha256 $receipt.Sha256 `
    -NativeClosureExecuted $siteRedirect.NativeClosureExecuted `
    -AccessSiteRedirected $siteRedirect.OriginalAccessSiteRedirected `
    -SmaBinderKind $siteRedirect.BinderKind -SmaReceiverType $siteRedirect.Receiver `
    -MatchingSmaSiteCount 1 `
    -ReceiverRepresentationRewritten $siteRedirect.ReceiverRepresentationRewritten -PublicationValue 1
$transportRecords = @($projection, $layout, $binding) | ConvertTo-DirectPortProjectionText

[pscustomobject]@{
    Status = 'PASS'
    SourceDeclaration = 'CalculatorState.DisplayValue : string = "0"'
    SourceStartOffset = $property.Extent.StartOffset
    NativeLayout = $receipt.NativeLayout
    LengthOffset = $receipt.LengthOffset
    CapacityOffset = $receipt.CapacityOffset
    Utf16Offset = $receipt.Utf16Offset
    InlineCapacity = $receipt.InlineCapacity
    SetterValue = $receipt.SetterValue
    GetterVerified = $receipt.GetterVerified
    RyuJitBodyBytes = $receipt.RyuJitBodyBytes
    DetachedPeBytes = $receipt.Bytes
    DetachedPeSha256 = $receipt.Sha256
    ClrDirectory = $receipt.ClrDirectory
    NativeFieldOperationsClosed = 2
    StorageCapacityChars = $layout.StorageCapacityChars
    OverflowBehavior = $layout.OverflowBehavior
    LoweringBindingState = $binding.BindingState
    DeclarationNodeId = $binding.DeclarationNodeId
    AccessNodeId = $binding.AccessNodeId
    DynamicOrdinal = $binding.DynamicOrdinal
    OriginalAccessSiteRedirected = $binding.AccessSiteRedirected
    AuthenticSmaBinder = $binding.SmaBinderKind
    AuthenticTypedBinderSites = $binding.MatchingSmaSiteCount
    ReceiverRepresentationRewritten = $binding.ReceiverRepresentationRewritten
    ManagedResultBridgeRemaining = $siteRedirect.ManagedResultBridgeRemaining
    WholeFunctionLowered = $siteRedirect.WholeFunctionLowered
    BindingRecords = $transportRecords.Count
    CalculatorApplicationClosed = $false
    PresentationInputLifetimeClosed = 0
    RemainingBoundary = 'DirectPort COM/D3D12/DirectWrite UI, callbacks, event flow, window lifetime, full string ownership'
} | Format-List
