[CmdletBinding()]
param([switch] $PassThru)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\Compiler\DirectPort.ResolutionPorts.psm1'
Import-Module $modulePath -Force

$evidence = '0264A33C4F6872FAF2F05A4AE9755E5B80129856F5C58E8097DF7ECCDF2346C7'
$projection = New-DirectPortStructuralProjection -ProjectionId 7001 -SourceNodeId 1416 `
    -Kind Method -OwnerIdentity 'CalculatorState' -MemberIdentity 'get_DisplayValue' `
    -Signature '()->string' -Capability 9001 -EvidenceSha256 $evidence -PublicationValue 1
$candidate = New-DirectPortResolutionCandidate -CandidateId 8001 -UnresolvedSiteId 241 `
    -ProjectionId 7001 -Confidence 0.97 -Reason 'owner and observed result shape agree' `
    -EvidenceCapability 9101 -ObservationCount 12 -PublicationValue 4

$confidenceRejected = $false
try {
    $null = New-DirectPortVerifiedResolution -Candidate $candidate -Projection $projection `
        -VerificationKind 'SourceExtentAndResultShape' -VerificationSha256 $evidence `
        -VerifierCapability 9201 -ExactMatch:$false
} catch {
    $confidenceRejected = $_.Exception.Message -like 'NO ADMITTED LOWERING*'
}
if (!$confidenceRejected) { throw 'Confidence-only promotion was not rejected.' }

$verified = New-DirectPortVerifiedResolution -Candidate $candidate -Projection $projection `
    -VerificationKind 'SourceExtentAndResultShape' -VerificationSha256 $evidence `
    -VerifierCapability 9201 -ExactMatch:$true -PublicationValue 5
$text = @($projection,$candidate,$verified) | ConvertTo-DirectPortProjectionText
if ($text.Count -ne 3) { throw 'Projection text did not preserve all three records.' }
foreach ($line in $text) { $null = $line | ConvertFrom-Json -ErrorAction Stop }

$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $modulePath),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Resolution-port module has parser errors.' }
$prohibited = @($ast.FindAll({param($node)
    ($node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Get-Member','Add-Type')) -or
    ($node -is [Management.Automation.Language.TypeExpressionAst] -and $node.TypeName.FullName -like 'System.Reflection*')
},$true))
if ($prohibited.Count) { throw 'Structural projection implementation performs reflection discovery.' }

$receipt=[pscustomobject]@{
    Status='PASS'
    StructuralProjection=1
    RankedCandidates=1
    VerifiedResolutions=1
    ConfidenceOnlyPromotion='REJECTED'
    ReflectionDiscovery=0
    TextEncoding='UTF-8 NDJSON-compatible records'
    TextLines=$text.Count
}
if ($PassThru) { $receipt } else { $receipt | Format-List }
