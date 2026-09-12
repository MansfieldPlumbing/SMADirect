[CmdletBinding()]
param(
    [switch] $SkipGpuTransport
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repo 'Conformance\Calculator.ps1'
$portsPath = Join-Path $repo 'Compiler\DirectPort.ResolutionPorts.psm1'
$gpuReceipt = Join-Path $PSScriptRoot 'Test-Windows.Graphics.D3D12.SystemMemory.ps1'

Import-Module $portsPath -Force
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $sourcePath, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count) { throw "Calculator parse failed: $($parseErrors[0].Message)" }

$allNodes = @($ast.FindAll({ param($node) $true }, $true) |
    Sort-Object { $_.Extent.StartOffset }, { $_.Extent.EndOffset }, { $_.GetType().FullName })
$nodeIds = @{}
for ($i = 0; $i -lt $allNodes.Count; $i++) { $nodeIds[$allNodes[$i]] = $i }

$typeDefinitions = @($ast.FindAll({
    param($node) $node -is [System.Management.Automation.Language.TypeDefinitionAst]
}, $true))
$declarations = foreach ($type in $typeDefinitions) {
    foreach ($member in $type.Members) {
        $memberType = $null
        $projectionKind = 'Method'
        if ($member -is [System.Management.Automation.Language.PropertyMemberAst]) {
            $memberType = $member.PropertyType.TypeName.FullName
            $projectionKind = 'Property'
        } elseif ($member.Name -eq $type.Name) {
            $projectionKind = 'Constructor'
        }
        [pscustomobject]@{
            Owner = $type.Name
            Name = $member.Name
            Kind = $projectionKind
            MemberType = $memberType
            Node = $member
        }
    }
}

# This is deliberately small, source-derived flow analysis. It never asks CLR
# reflection which members exist.
$variableTypes = @{}
$assignments = @($ast.FindAll({
    param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]
}, $true))
foreach ($assignment in $assignments) {
    if ($assignment.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
    $left = $assignment.Left.VariablePath.UserPath
    $constructors = @($assignment.Right.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.MemberExpressionAst] -and
        $node.Static -and $node.Member.Value -eq 'new' -and
        $node.Expression -is [System.Management.Automation.Language.TypeExpressionAst]
    }, $true))
    $constructorTypes = @($constructors | ForEach-Object { $_.Expression.TypeName.FullName } | Sort-Object -Unique)
    if ($constructorTypes.Count -eq 1) { $variableTypes[$left] = $constructorTypes[0] }
}

$foreachStatements = @($ast.FindAll({
    param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst]
}, $true))
foreach ($statement in $foreachStatements) {
    $sourceVariables = @($statement.Condition.FindAll({
        param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))
    foreach ($sourceVariable in $sourceVariables) {
        $sourceName = $sourceVariable.VariablePath.UserPath
        if ($variableTypes.ContainsKey($sourceName)) {
            $variableTypes[$statement.Variable.VariablePath.UserPath] = $variableTypes[$sourceName]
            break
        }
    }
}

# Propagate only unambiguous direct aliases or indexed reads from a known array.
for ($pass = 0; $pass -lt 4; $pass++) {
    foreach ($assignment in $assignments) {
        if ($assignment.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        $left = $assignment.Left.VariablePath.UserPath
        $rightVariables = @($assignment.Right.FindAll({
            param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)
        $known = @($rightVariables | Where-Object { $variableTypes.ContainsKey($_) } |
            ForEach-Object { $variableTypes[$_] } | Sort-Object -Unique)
        if ($known.Count -eq 1) { $variableTypes[$left] = $known[0] }
    }
}

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $projections = foreach ($declaration in $declarations) {
        $signature = '{0}.{1}:{2}:{3}' -f $declaration.Owner, $declaration.Name,
            $declaration.Kind, $declaration.MemberType
        $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature))
        $hex = [Convert]::ToHexString($digest)
        $projectionId = [BitConverter]::ToUInt64($digest, 0)
        $capability = [BitConverter]::ToUInt64($digest, 8)
        New-DirectPortStructuralProjection `
            -ProjectionId $projectionId `
            -SourceNodeId $nodeIds[$declaration.Node] `
            -Kind $declaration.Kind `
            -OwnerIdentity $declaration.Owner `
            -MemberIdentity $declaration.Name `
            -Signature $signature `
            -Capability $capability `
            -EvidenceSha256 $hex `
            -PublicationValue 1
    }

    $projectionIndex = @{}
    foreach ($projection in $projections) {
        $projectionIndex[('{0}|{1}' -f $projection.OwnerIdentity, $projection.MemberIdentity)] = $projection
    }

    $memberSites = @($ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.MemberExpressionAst]
    }, $true))
    $verified = @()
    $candidates = @()
    $unresolved = @()
    foreach ($site in $memberSites) {
        $receiverType = $null
        if ($site.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $variable = $site.Expression.VariablePath.UserPath
            if ($variable -eq 'this') {
                $parent = $site.Parent
                while ($parent -and $parent -isnot [System.Management.Automation.Language.TypeDefinitionAst]) {
                    $parent = $parent.Parent
                }
                if ($parent) { $receiverType = $parent.Name }
            } elseif ($variableTypes.ContainsKey($variable)) {
                $receiverType = $variableTypes[$variable]
            }
        }
        $key = '{0}|{1}' -f $receiverType, $site.Member.Value
        if (-not $receiverType -or -not $projectionIndex.ContainsKey($key)) {
            $unresolved += $site
            continue
        }
        $projection = $projectionIndex[$key]
        $candidate = New-DirectPortResolutionCandidate `
            -CandidateId ([uint64](1000000 + $nodeIds[$site])) `
            -UnresolvedSiteId $nodeIds[$site] `
            -ProjectionId $projection.ProjectionId `
            -Confidence 1.0 `
            -Reason 'SourceDerivedReceiverTypeAndDeclarationMatch' `
            -EvidenceCapability $projection.Capability `
            -ObservationCount 1 `
            -PublicationValue 1
        $candidates += $candidate
        $verified += New-DirectPortVerifiedResolution `
            -Candidate $candidate -Projection $projection `
            -VerificationKind 'ExactSourceDeclarationMatch' `
            -VerificationSha256 $projection.EvidenceSha256 `
            -VerifierCapability $projection.Capability `
            -ExactMatch $true -PublicationValue 1
    }

    $publication = @($projections) + @($candidates) + @($verified)
    $lines = foreach ($record in $publication) { ConvertTo-DirectPortProjectionText $record }
    $payloadPath = Join-Path ([IO.Path]::GetTempPath()) ('CalculatorProjectionPopulation-{0}.ndjson' -f $PID)
    [IO.File]::WriteAllLines($payloadPath, $lines, [Text.UTF8Encoding]::new($false))
    try {
        if (-not $SkipGpuTransport) { & $gpuReceipt -PayloadPath $payloadPath }
        if ($LASTEXITCODE -and -not $SkipGpuTransport) { throw "D3D12 payload receipt exited $LASTEXITCODE" }
    } finally {
        Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
    }

    if ($verified.Count -lt 1) { throw 'No exact Calculator member sites were verified.' }
    [pscustomobject]@{
        Verdict = 'PASS'
        AstNodes = $allNodes.Count
        AuthoredDeclarations = $declarations.Count
        MemberSites = $memberSites.Count
        ExactSourceResolvedSites = $verified.Count
        UnresolvedOrFuzzySites = $unresolved.Count
        CoveragePercent = [math]::Round(100.0 * $verified.Count / $memberSites.Count, 2)
        ProjectionRecords = $projections.Count
        CandidateRecords = $candidates.Count
        VerifiedRecords = $verified.Count
        PublicationLines = $lines.Count
        ReflectionDiscovery = 0
        NativeClosure = 'NO ADMITTED LOWERING: resolutions are proven; native storage/call emission remains open'
    } | Format-List
} finally {
    $sha.Dispose()
}
