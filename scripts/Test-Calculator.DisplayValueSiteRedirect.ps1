[CmdletBinding()]
param(
    [uint32] $AccessNodeId = 1329,
    [string] $ExpectedAccessExtent = '$state.DisplayValue',
    [string] $Member = 'DisplayValue',
    [string] $ExpectedReceiver = 'CalculatorState',
    [string] $ExpectedBinderKind = 'PSGetMemberBinder',
    [string] $ProbeMemberName = '__SMADirectProbe1329__',
    [ValidateSet('NativeUtf16String','NativeUInt32Length')][string] $ReplacementKind = 'NativeUtf16String',
    [object] $ExpectedResult = '42'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repo 'Conformance\Calculator.ps1'
$identityPath = Join-Path $PSScriptRoot 'Test-Calculator.DisplayValueSiteIdentity.ps1'
$identity = . $identityPath -AccessNodeId $AccessNodeId `
    -ExpectedAccessExtent $ExpectedAccessExtent -OriginalMember $Member `
    -ExpectedReceiver $ExpectedReceiver -ExpectedBinderKind $ExpectedBinderKind `
    -ProbeMemberName $ProbeMemberName
if ($identity.Status -cne 'PASS' -or $identity.AccessSiteRedirected) {
    throw 'The prerequisite DisplayValue site-identity receipt is invalid.'
}

$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
$sourceText = [IO.File]::ReadAllText($sourcePath)
$sourceAst = Get-ParsedSource $sourceText $sourcePath
$lambda = Get-CompiledFunctionLambda $sourceAst 'Render-CalculatorWidget'
$fingerprints = @(Get-DynamicFingerprints $lambda -IncludeExpression)
$target = @($fingerprints | Where-Object { $_.DynamicOrdinal -eq $identity.DynamicOrdinal })
if ($target.Count -ne 1) { throw 'The verified dynamic ordinal did not select exactly one expression.' }
$target = $target[0]
if ($target.BinderKind -cne $identity.BinderKind -or
    $target.BinderText -notmatch ('^GetMember: ' + [regex]::Escape($Member) + ' ') -or
    $target.ReceiverType -cne $ExpectedReceiver) {
    throw 'The captured expression differs from the verified site identity.'
}

$fingerprintText = [ordered]@{
    DynamicOrdinal=$target.DynamicOrdinal; BinderKind=$target.BinderKind
    BinderText=$target.BinderText; DelegateType=$target.DelegateType
    ReceiverType=$target.ReceiverType; ArgumentTypes=$target.ArgumentTypes
    ReturnType=$target.ReturnType
} | ConvertTo-Json -Compress -Depth 5
$fingerprintSha = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($fingerprintText)))

$assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('SMADirect.DisplayRedirect.'+[guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$typeBuilder = $assembly.DefineDynamicModule('Bridge').DefineType(
    'SMADirect.DisplayRedirectCarrier',[Reflection.TypeAttributes]'Public,Class,Sealed,Abstract')
$sites = [Collections.Generic.List[object]]::new()
$state = @{ DynamicOrdinal=[uint32]$identity.DynamicOrdinal; Rewrites=[Collections.Generic.List[object]]::new() }
$spec = [pscustomobject]@{
    DynamicOrdinal=[uint32]$identity.DynamicOrdinal
    ExpectedSourceSha256=$sourceHash
    ActualSourceSha256=$sourceHash
    BinderKind=$identity.BinderKind
    MemberIdentity=$identity.Member
    ReceiverType=$identity.Receiver
    FingerprintSha256=$fingerprintSha
    ReplacementKind=$ReplacementKind
    LengthOffset=[uint32]0
    StorageOffset=[uint32]8
}
$replacement = Convert-DynamicToPersistedCallSites -Expression $target.Expression `
    -TypeBuilder $typeBuilder -Sites $sites -TraversalState $state -VerifiedReplacement $spec
if ($sites.Count -ne 0 -or $state.Rewrites.Count -ne 1) {
    throw 'The redirected site created a persisted SMA call site or lacked a rewrite receipt.'
}
$carrierType = $typeBuilder.CreateType()
$pointerField = $carrierType.GetField(
    "__smaNativeState$($identity.DynamicOrdinal)",[Reflection.BindingFlags]'Public,Static')
if (-not $pointerField) { throw 'Native state pointer field was not emitted.' }

# Bind the verified rewrite to the runtime FieldInfo after type creation.
$runtimeSites = [Collections.Generic.List[object]]::new()
$runtimeState = @{ DynamicOrdinal=[uint32]$identity.DynamicOrdinal; Rewrites=[Collections.Generic.List[object]]::new() }
Add-Member -InputObject $spec -NotePropertyName PointerField -NotePropertyValue $pointerField
$replacement = Convert-DynamicToPersistedCallSites -Expression $target.Expression `
    -TypeBuilder $typeBuilder -Sites $runtimeSites -TraversalState $runtimeState -VerifiedReplacement $spec
if ($runtimeSites.Count -ne 0 -or $runtimeState.Rewrites.Count -ne 1) {
    throw 'Runtime-bound replacement did not preserve the verified binder removal.'
}

$nativeState = [Runtime.InteropServices.Marshal]::AllocHGlobal(72)
try {
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeState,0,2)
    [Runtime.InteropServices.Marshal]::WriteInt32($nativeState,4,32)
    [Runtime.InteropServices.Marshal]::WriteInt16($nativeState,8,[int16][char]'4')
    [Runtime.InteropServices.Marshal]::WriteInt16($nativeState,10,[int16][char]'2')
    $pointerField.SetValue($null,$nativeState)
    $bridgeLambda = [Linq.Expressions.Expression]::Lambda[Func[object]]($replacement)
    $result = $bridgeLambda.Compile().Invoke()
} finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($nativeState)
}
if ($result -cne $ExpectedResult) { throw "Native read returned '$result', expected '$ExpectedResult'." }

$rewrittenAnalysisAssembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('SMADirect.RewriteAnalysis.'+[guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$analysisType = $rewrittenAnalysisAssembly.DefineDynamicModule('Analysis').DefineType('Carrier')
$analysisSites = [Collections.Generic.List[object]]::new()
$analysisState = @{DynamicOrdinal=[uint32]0;AnalysisOnly=$true;DynamicExpressions=[Collections.Generic.List[object]]::new()}
$null = Convert-DynamicToPersistedCallSites -Expression $replacement `
    -TypeBuilder $analysisType -Sites $analysisSites -TraversalState $analysisState
if ($analysisState.DynamicExpressions.Count -ne 0) { throw 'The replacement still contains a dynamic binder.' }

[pscustomobject]@{
    Status='PASS'
    DeclarationNodeId=[uint64]$identity.DeclarationNodeId
    AccessNodeId=[uint64]$identity.AccessNodeId
    DynamicOrdinal=[uint32]$identity.DynamicOrdinal
    PersistedCallSiteIndex=$null
    BinderKind=$identity.BinderKind
    Member=$identity.Member
    Receiver=$identity.Receiver
    FingerprintSha256=$fingerprintSha
    BinderRemoved=$true
    ReceiverRepresentationRewritten=$true
    NativeClosureExecuted=$true
    NativeReadResult=$result
    ReplacementExpression=$replacement.ToString()
    OriginalAccessSiteRedirected=$true
    ManagedResultBridgeRemaining=($ReplacementKind -eq 'NativeUtf16String')
    ManagedStringMaterialized=($ReplacementKind -eq 'NativeUtf16String')
    WholeFunctionLowered=$false
    CompleteCalculatorApplication=$false
}
