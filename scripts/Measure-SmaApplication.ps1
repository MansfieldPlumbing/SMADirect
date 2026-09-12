[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,

    [string] $PopulationRoot,

    [string] $OutputRoot,

    [string] $JitPath = 'C:\bin\pwsh\clrjit.dll'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Text {
    param([AllowEmptyString()][string] $Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash)
}

function Get-Preview {
    param([AllowEmptyString()][string] $Text, [int] $Limit = 160)
    $oneLine = $Text -replace '\r\n|\r|\n', '\n'
    if ($oneLine.Length -le $Limit) { return $oneLine }
    return $oneLine.Substring(0, $Limit) + '…'
}

function ConvertTo-CanonicalObject {
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [bool] -or
        $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or $Value -is [single] -or
        $Value -is [double] -or $Value -is [decimal] -or $Value -is [datetime]) {
        return $Value
    }

    if ($Value -is [Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string] $_ } | Sort-Object -CaseSensitive)) {
            $ordered[$key] = ConvertTo-CanonicalObject $Value[$key]
        }
        return $ordered
    }

    if ($Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-CanonicalObject $_ })
    }

    $properties = $Value.PSObject.Properties | Where-Object MemberType -in NoteProperty, Property |
        Sort-Object Name -CaseSensitive
    $ordered = [ordered]@{}
    foreach ($property in $properties) {
        $ordered[$property.Name] = ConvertTo-CanonicalObject $property.Value
    }
    return $ordered
}

function Get-NodeDetails {
    param([Management.Automation.Language.Ast] $Node)

    $details = [ordered]@{}
    if ($Node -is [Management.Automation.Language.FunctionDefinitionAst]) {
        $details.Kind = 'Function'
        $details.Name = $Node.Name
        $details.ParameterCount = @($Node.Parameters).Count
        $details.BodyStartOffset = $Node.Body.Extent.StartOffset
        $details.BodyEndOffset = $Node.Body.Extent.EndOffset
    }
    elseif ($Node -is [Management.Automation.Language.VariableExpressionAst]) {
        $details.Kind = 'Variable'
        $details.Name = $Node.VariablePath.UserPath
        $details.Splatted = $Node.Splatted
    }
    elseif ($Node -is [Management.Automation.Language.CommandAst]) {
        $details.Kind = 'Command'
        $details.Name = $Node.GetCommandName()
        $details.ElementCount = @($Node.CommandElements).Count
        $details.InvocationOperator = [string] $Node.InvocationOperator
    }
    elseif ($Node -is [Management.Automation.Language.InvokeMemberExpressionAst]) {
        $details.Kind = 'InvokeMember'
        $details.Member = $Node.Member.Extent.Text
        $details.Static = $Node.Static
        $details.ArgumentCount = @($Node.Arguments).Count
    }
    elseif ($Node -is [Management.Automation.Language.MemberExpressionAst]) {
        $details.Kind = 'Member'
        $details.Member = $Node.Member.Extent.Text
        $details.Static = $Node.Static
    }
    elseif ($Node -is [Management.Automation.Language.AssignmentStatementAst]) {
        $details.Kind = 'Assignment'
        $details.Operator = [string] $Node.Operator
    }
    elseif ($Node -is [Management.Automation.Language.BinaryExpressionAst]) {
        $details.Kind = 'BinaryOperator'
        $details.Operator = [string] $Node.Operator
    }
    elseif ($Node -is [Management.Automation.Language.UnaryExpressionAst]) {
        $details.Kind = 'UnaryOperator'
        $details.TokenKind = [string] $Node.TokenKind
    }
    elseif ($Node -is [Management.Automation.Language.TypeExpressionAst]) {
        $details.Kind = 'TypeExpression'
        $details.TypeName = $Node.TypeName.FullName
    }
    elseif ($Node -is [Management.Automation.Language.ConvertExpressionAst]) {
        $details.Kind = 'Conversion'
        $details.TypeName = $Node.Type.TypeName.FullName
    }
    elseif ($Node -is [Management.Automation.Language.HashtableAst]) {
        $details.Kind = 'Hashtable'
        $details.PairCount = @($Node.KeyValuePairs).Count
    }
    elseif ($Node -is [Management.Automation.Language.IfStatementAst]) {
        $details.Kind = 'If'
        $details.ClauseCount = @($Node.Clauses).Count
        $details.HasElse = $null -ne $Node.ElseClause
    }
    elseif ($Node -is [Management.Automation.Language.SwitchStatementAst]) {
        $details.Kind = 'Switch'
        $details.ClauseCount = @($Node.Clauses).Count
    }
    elseif ($Node -is [Management.Automation.Language.LoopStatementAst]) {
        $details.Kind = 'Loop'
        $details.Label = $Node.Label
    }
    elseif ($Node -is [Management.Automation.Language.ReturnStatementAst]) {
        $details.Kind = 'Return'
    }
    elseif ($Node -is [Management.Automation.Language.ThrowStatementAst]) {
        $details.Kind = 'Throw'
    }

    return $details
}

function Get-AstReceipt {
    param([string] $Path, [string] $RelativePath)

    $tokens = $null
    $errors = $null
    $root = [Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $errors)
    $nodes = @($root.FindAll({ param($candidate) $true }, $true))
    $indices = [Collections.Generic.Dictionary[Management.Automation.Language.Ast, int]]::new()
    for ($index = 0; $index -lt $nodes.Count; $index++) { $indices[$nodes[$index]] = $index }

    $nodeRecords = for ($index = 0; $index -lt $nodes.Count; $index++) {
        $node = $nodes[$index]
        $parentIndex = $null
        if ($null -ne $node.Parent -and $indices.ContainsKey($node.Parent)) {
            $parentIndex = $indices[$node.Parent]
        }
        $extentText = $node.Extent.Text
        [ordered]@{
            Index = $index
            ParentIndex = $parentIndex
            Type = $node.GetType().FullName
            StartOffset = $node.Extent.StartOffset
            EndOffset = $node.Extent.EndOffset
            StartLine = $node.Extent.StartLineNumber
            StartColumn = $node.Extent.StartColumnNumber
            EndLine = $node.Extent.EndLineNumber
            EndColumn = $node.Extent.EndColumnNumber
            ExtentSha256 = Get-Sha256Text $extentText
            Preview = Get-Preview $extentText
            Details = Get-NodeDetails $node
        }
    }

    $tokenRecords = @($tokens | ForEach-Object {
        [ordered]@{
            Kind = [string] $_.Kind
            TokenFlags = [string] $_.TokenFlags
            StartOffset = $_.Extent.StartOffset
            EndOffset = $_.Extent.EndOffset
            StartLine = $_.Extent.StartLineNumber
            StartColumn = $_.Extent.StartColumnNumber
            TextSha256 = Get-Sha256Text $_.Text
            Preview = Get-Preview $_.Text 100
        }
    })

    $errorRecords = @($errors | ForEach-Object {
        [ordered]@{
            ErrorId = $_.ErrorId
            Message = $_.Message
            StartOffset = $_.Extent.StartOffset
            EndOffset = $_.Extent.EndOffset
            StartLine = $_.Extent.StartLineNumber
            StartColumn = $_.Extent.StartColumnNumber
            IncompleteInput = $_.IncompleteInput
        }
    })

    $functionNames = @($nodes | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] } |
        ForEach-Object Name)

    return [ordered]@{
        Schema = 'smadirect.ast-receipt.v1'
        Path = $RelativePath
        FileSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
        ParseErrorCount = $errorRecords.Count
        ParseErrors = $errorRecords
        TokenCount = $tokenRecords.Count
        Tokens = $tokenRecords
        NodeCount = $nodeRecords.Count
        Nodes = @($nodeRecords)
        FunctionNames = $functionNames
    }
}

$manifest = (Resolve-Path -LiteralPath $ManifestPath).Path
if (-not $PopulationRoot) { $PopulationRoot = Split-Path -Parent $manifest }
$population = (Resolve-Path -LiteralPath $PopulationRoot).Path.TrimEnd('\', '/')
if (-not $OutputRoot) {
    $OutputRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'evidence'
}
$outputFullPath = [IO.Path]::GetFullPath($OutputRoot)

$manifestRelative = [IO.Path]::GetRelativePath($population, $manifest)
if ($manifestRelative.StartsWith('..')) { throw "Manifest must be inside PopulationRoot: $population" }
$manifestData = Import-PowerShellDataFile -LiteralPath $manifest

$reachableNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void] $reachableNames.Add($manifestRelative.Replace('\', '/'))
foreach ($key in 'RootModule', 'RootScript', 'Style', 'Abi') {
    if ($manifestData.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string] $manifestData[$key])) {
        $candidate = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $manifest) ([string] $manifestData[$key])))
        $relative = [IO.Path]::GetRelativePath($population, $candidate)
        if ($relative.StartsWith('..') -or [IO.Path]::IsPathRooted($relative)) {
            throw "Manifest member '$key' escapes PopulationRoot: $candidate"
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Manifest member '$key' does not exist: $candidate"
        }
        [void] $reachableNames.Add($relative.Replace('\', '/'))
    }
}

$populationFiles = @(Get-ChildItem -LiteralPath $population -File -Recurse | Sort-Object FullName)
$fileRecords = @($populationFiles | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($population, $_.FullName).Replace('\', '/')
    [ordered]@{
        Path = $relative
        Bytes = $_.Length
        Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
        Reachable = $reachableNames.Contains($relative)
    }
})

$scriptFiles = @($populationFiles | Where-Object Extension -in '.ps1', '.psm1')
$astReceipts = @($scriptFiles | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($population, $_.FullName).Replace('\', '/')
    Get-AstReceipt -Path $_.FullName -RelativePath $relative
})

$parserAssembly = [Management.Automation.Language.Parser].Assembly
$parserAssemblyPath = $parserAssembly.Location
$jitIdentity = if (Test-Path -LiteralPath $JitPath -PathType Leaf) {
    $jitItem = Get-Item -LiteralPath $JitPath
    [ordered]@{
        Path = $jitItem.FullName
        Bytes = $jitItem.Length
        Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $jitItem.FullName).Hash
        FileVersion = $jitItem.VersionInfo.FileVersion
        ProductVersion = $jitItem.VersionInfo.ProductVersion
    }
} else {
    [ordered]@{ Path = [IO.Path]::GetFullPath($JitPath); Missing = $true }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$gitHead = (& git -C $repoRoot rev-parse HEAD 2>$null) -join ''
$gitBranch = (& git -C $repoRoot branch --show-current 2>$null) -join ''
$gitStatus = @(& git -C $repoRoot status --porcelain=v1 --untracked-files=all 2>$null)
$outputRelativeToRepo = [IO.Path]::GetRelativePath($repoRoot, $outputFullPath).Replace('\', '/').TrimEnd('/')
if (-not $outputRelativeToRepo.StartsWith('..') -and -not [IO.Path]::IsPathRooted($outputRelativeToRepo)) {
    # Evidence generated by this observation is not source state and must not perturb
    # the next observation's repository identity.
    $gitStatus = @($gitStatus | Where-Object {
        $statusPath = if ($_.Length -gt 3) { $_.Substring(3).Replace('\', '/') } else { '' }
        -not ($statusPath -eq $outputRelativeToRepo -or $statusPath.StartsWith($outputRelativeToRepo + '/'))
    })
}

$identity = [ordered]@{
    Schema = 'smadirect.telemetry-identity.v1'
    Repository = [ordered]@{ Head = $gitHead; Branch = $gitBranch; Status = $gitStatus }
    PowerShell = [ordered]@{
        Edition = $PSVersionTable.PSEdition
        Version = $PSVersionTable.PSVersion.ToString()
        ProcessArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        OSArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        OSDescription = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    }
    ParserAssembly = [ordered]@{
        FullName = $parserAssembly.FullName
        Path = $parserAssemblyPath
        Bytes = (Get-Item -LiteralPath $parserAssemblyPath).Length
        Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $parserAssemblyPath).Hash
    }
    RyuJit = $jitIdentity
    ResolutionEnvironment = [ordered]@{
        DOTNET_ROOT = [Environment]::GetEnvironmentVariable('DOTNET_ROOT')
        DOTNET_ROOT_X64 = [Environment]::GetEnvironmentVariable('DOTNET_ROOT_X64')
        PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath')
    }
}

$observation = [ordered]@{
    Schema = 'smadirect.t0-t1-observation.v1'
    Status = 'T0/T1 collected'
    Admission = 'Unassessed; no lowering claim'
    Application = [ordered]@{
        Id = $manifestData.Id
        Name = $manifestData.Name
        EntryPoint = $manifestData.EntryPoint
        ManifestPath = $manifestRelative.Replace('\', '/')
        ManifestData = ConvertTo-CanonicalObject $manifestData
    }
    Identity = $identity
    Population = [ordered]@{
        FileCount = $fileRecords.Count
        ReachableCount = @($fileRecords | Where-Object Reachable).Count
        UnreferencedCount = @($fileRecords | Where-Object { -not $_.Reachable }).Count
        Files = $fileRecords
    }
    Ast = $astReceipts
}

$canonicalObservation = ConvertTo-CanonicalObject $observation
$observationJson = $canonicalObservation | ConvertTo-Json -Depth 100 -Compress
$observationSha256 = Get-Sha256Text $observationJson

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss.fffffffZ')
$safeId = ([string] $manifestData.Id) -replace '[^A-Za-z0-9._-]', '_'
$bundlePath = Join-Path $outputFullPath "$timestamp-$safeId"
$inputsPath = Join-Path $bundlePath 'inputs'
$astPath = Join-Path $bundlePath 'ast'
[void] (New-Item -ItemType Directory -Path $inputsPath, $astPath -Force)

$runManifest = [ordered]@{
    Schema = 'smadirect.telemetry-bundle.v1'
    CollectedUtc = [DateTime]::UtcNow.ToString('o')
    ObservationSha256 = $observationSha256
    Status = 'T0/T1 collected'
    Admission = 'Unassessed; no lowering claim'
}
$runManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $bundlePath 'manifest.json') -Encoding utf8
$canonicalObservation | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $bundlePath 'observation.json') -Encoding utf8
$fileRecords | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $inputsPath 'population.json') -Encoding utf8

foreach ($receipt in $astReceipts) {
    $safeName = $receipt.Path -replace '[^A-Za-z0-9._-]', '_'
    $receipt | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $astPath "$safeName.ast.json") -Encoding utf8
}

$verdict = @(
    "# T0/T1 telemetry verdict: $($manifestData.Id)"
    ''
    '- Status: **T0/T1 collected**'
    '- Admission: **Unassessed; no lowering claim**'
    "- Observation SHA-256: ``$observationSha256``"
    "- Population: $($fileRecords.Count) files; $(@($fileRecords | Where-Object Reachable).Count) reachable; $(@($fileRecords | Where-Object { -not $_.Reachable }).Count) unreferenced"
    "- Parsed SMA files: $($astReceipts.Count)"
    "- Parse errors: $(@($astReceipts | ForEach-Object ParseErrors).Count)"
    ''
    'Unsupported semantic extents are not classified by this collector. Until a later lowering receipt proves them, their status is **NO ADMITTED LOWERING**.'
)
$verdict | Set-Content -LiteralPath (Join-Path $bundlePath 'verdict.md') -Encoding utf8

[pscustomobject]@{
    BundlePath = $bundlePath
    ObservationSha256 = $observationSha256
    ApplicationId = [string] $manifestData.Id
    FileCount = $fileRecords.Count
    ReachableCount = @($fileRecords | Where-Object Reachable).Count
    UnreferencedCount = @($fileRecords | Where-Object { -not $_.Reachable }).Count
    ParsedFileCount = $astReceipts.Count
    ParseErrorCount = @($astReceipts | ForEach-Object ParseErrors).Count
}
