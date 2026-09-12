[CmdletBinding()]
param([switch] $PassThru)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$calculatorPath = Join-Path $PSScriptRoot '..\Conformance\Calculator.ps1'
$portsPath = Join-Path $PSScriptRoot '..\Compiler\DirectPort.ResolutionPorts.psm1'
Import-Module $portsPath -Force

$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $calculatorPath),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Calculator has parser errors.'}
$nodes=@($ast.FindAll({param($node)$true},$true)|Sort-Object {$_.Extent.StartOffset},{$_.Extent.EndOffset},{$_.GetType().Name})
$site=$nodes|Where-Object {
    $_ -is [Management.Automation.Language.MemberExpressionAst] -and
    $_.Member.Extent.Text -eq 'DisplayValue' -and $_.Extent.StartLineNumber -eq 202
}|Select-Object -First 1
if($null-eq$site){throw 'The rendered DisplayValue member site was not found.'}
$siteId=[uint64][Array]::IndexOf($nodes,$site)

$stateType=$nodes|Where-Object {$_-is[Management.Automation.Language.TypeDefinitionAst]-and$_.Name-eq'CalculatorState'}|Select-Object -First 1
$property=$stateType.Members|Where-Object {$_-is[Management.Automation.Language.PropertyMemberAst]-and$_.Name-eq'DisplayValue'}|Select-Object -First 1
if($null-eq$property){throw 'CalculatorState.DisplayValue declaration was not found.'}
$declaredType=$property.PropertyType.TypeName.FullName
if($declaredType-ne'string'){throw "Unexpected DisplayValue type '$declaredType'."}

$sourceBytes=[IO.File]::ReadAllBytes((Resolve-Path $calculatorPath))
$sourceHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($sourceBytes))
function Get-StableCapability([string]$Text) {
    $bytes=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))
    $value=[BitConverter]::ToUInt64($bytes,0)
    if($value-eq0){return[uint64]1};$value
}
$projectionId=Get-StableCapability "projection|$sourceHash|CalculatorState|DisplayValue"
$memberCapability=Get-StableCapability "member|$sourceHash|CalculatorState|DisplayValue|string"
$evidenceCapability=Get-StableCapability "evidence|$sourceHash|$siteId"
$verifierCapability=Get-StableCapability "verifier|Calculator.DisplayValue.v1"

$projection=New-DirectPortStructuralProjection -ProjectionId $projectionId -SourceNodeId $siteId `
    -Kind Property -OwnerIdentity 'CalculatorState' -MemberIdentity 'DisplayValue' `
    -Signature 'string get; string set' -Capability $memberCapability -EvidenceSha256 $sourceHash -PublicationValue 1
$candidate=New-DirectPortResolutionCandidate -CandidateId (Get-StableCapability "candidate|$siteId|$projectionId") `
    -UnresolvedSiteId $siteId -ProjectionId $projectionId -Confidence 0.99 `
    -Reason 'member spelling, declared owner property, and declared string type agree' `
    -EvidenceCapability $evidenceCapability -ObservationCount 1 -PublicationValue 2

$oldSkip=$env:DP_SKIP_START
try {
    $env:DP_SKIP_START='1'
    . $calculatorPath
    $observed=& ([scriptblock]::Create('$state=[CalculatorState]::new();$state.DisplayValue="projection-proof";$state.DisplayValue'))
} finally {
    if($null-eq$oldSkip){Remove-Item Env:DP_SKIP_START -ErrorAction SilentlyContinue}else{$env:DP_SKIP_START=$oldSkip}
}
if($observed-cne'projection-proof'){throw 'Authentic PowerShell property behavior did not match the projection.'}
$verificationText="$sourceHash|$siteId|CalculatorState|DisplayValue|string|$observed"
$verificationHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($verificationText)))
$verified=New-DirectPortVerifiedResolution -Candidate $candidate -Projection $projection `
    -VerificationKind 'AuthenticPowerShellPropertyRoundTrip' -VerificationSha256 $verificationHash `
    -VerifierCapability $verifierCapability -ExactMatch:$true -PublicationValue 3

$projectionText=(@($projection,$candidate,$verified)|ConvertTo-DirectPortProjectionText)-join"`n"
$projectionBytes=[Text.Encoding]::UTF8.GetBytes($projectionText)
$temporaryPayload=Join-Path ([IO.Path]::GetTempPath()) ('calculator-projection-'+[Guid]::NewGuid().ToString('N')+'.ndjson')
try {
    [IO.File]::WriteAllBytes($temporaryPayload,$projectionBytes)
    $transport=& (Join-Path $PSScriptRoot 'Test-Windows.Graphics.D3D12.SystemMemory.ps1') -PayloadPath $temporaryPayload
} finally {
    if([IO.File]::Exists($temporaryPayload)){[IO.File]::Delete($temporaryPayload)}
}
if($transport.Status-ne'PASS'-or$transport.PayloadSha256-cne$transport.GpuCopiedPayloadSha256){throw 'Projection text D3D12 transport failed.'}

$receipt=[pscustomobject]@{
    Status='PASS'
    SourceNodeId=$siteId
    SourceExtent=$site.Extent.Text
    Declaration='CalculatorState.DisplayValue : string'
    RuntimeObservation=$observed
    CandidateConfidence=$candidate.Confidence
    VerificationKind=$verified.VerificationKind
    VerifiedMemberCapability=('0x{0:X16}'-f[uint64]$verified.MemberCapability)
    ProjectionTextValidBytes=$projectionBytes.Length
    ProjectionTextSha256=$transport.PayloadSha256
    ReflectionDiscovery=0
    NativeClosure='NO ADMITTED LOWERING: explicit native string storage and property call closure not yet emitted'
}
if($PassThru){$receipt}else{$receipt|Format-List}
