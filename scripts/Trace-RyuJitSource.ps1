[CmdletBinding(DefaultParameterSetName='Symbol')]
param(
    [Parameter(Mandatory, ParameterSetName='Il')][string] $IlOpcode,
    [Parameter(Mandatory, ParameterSetName='Tree')][string] $GenTree,
    [Parameter(Mandatory, ParameterSetName='Helper')][string] $Helper,
    [Parameter(Mandatory, ParameterSetName='Callback')][string] $Callback,
    [Parameter(Mandatory, ParameterSetName='Symbol')][string] $Symbol,
    [string] $Runtime = 'C:\Dev\References\SMADirect-Telemetry\dotnet-runtime',
    [string] $OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Artifacts\ryujit-source-graph.jsonl'),
    [ValidateRange(0,40)][int] $Context = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell's parser validates this tool. Runtime C++ is always queried by
# Git's indexed grep; it is never parsed as PowerShell or recursively loaded.
$tokens = $null; $parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Tool parse failure: $($parseErrors[0].Message)" }
if (-not (Test-Path -LiteralPath (Join-Path $Runtime '.git'))) { throw "Runtime checkout is not a Git worktree: $Runtime" }

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) { $null = New-Item -ItemType Directory -Force $outputDirectory }

function Invoke-RuntimeQuery {
    param([string]$Needle, [string[]]$Scope, [switch]$Regex)
    if ($Regex) {
        $lines = if ($Context -gt 0) { & git -C $Runtime grep -n "-C$Context" -E -e $Needle -- @Scope 2>$null }
                 else { & git -C $Runtime grep -n -E -e $Needle -- @Scope 2>$null }
    } else {
        $lines = if ($Context -gt 0) { & git -C $Runtime grep -n "-C$Context" -F -e $Needle -- @Scope 2>$null }
                 else { & git -C $Runtime grep -n -F -e $Needle -- @Scope 2>$null }
    }
    if ($LASTEXITCODE -gt 1) { throw "git grep failed for '$Needle'." }
    foreach ($line in @($lines)) {
        if ($line -match '^(?<path>.*?):(?<line>\d+):(?<text>.*)$') {
            [pscustomobject]@{ Path=$Matches.path; Line=[int]$Matches.line; Text=$Matches.text.Trim() }
        } elseif ($line -match '^(?<path>.*?)-(?<line>\d+)-(?<text>.*)$') {
            [pscustomobject]@{ Path=$Matches.path; Line=[int]$Matches.line; Text=$Matches.text.Trim() }
        }
    }
}

function Add-Edge {
    param([string]$From,[string]$Edge,[string]$To,[pscustomobject]$Hit,[string]$Classification)
    $record = [ordered]@{ from=$From; edge=$Edge; to=$To; source=("{0}:{1}" -f $Hit.Path,$Hit.Line) }
    if ($Classification) { $record.classification=$Classification }
    $json = $record | ConvertTo-Json -Compress
    if ($script:seen.Add($json)) { $script:records.Add($json); $record }
}

$script:seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:records = [Collections.Generic.List[string]]::new()

$jitImporter = @('src/coreclr/jit')
$jitLower = @('src/coreclr/jit')
$jitCodegen = @('src/coreclr/jit')
$jitEncode = @('src/coreclr/jit/instrsxarch.h','src/coreclr/jit/emitxarch.cpp')
$aot = @('src/coreclr/tools/Common/JitInterface','src/coreclr/tools/aot/ILCompiler.RyuJit/JitInterface')
$classByCallback = @{
    'resolveToken'='COMPILE_TIME_FACT'; 'getFieldOffset'='COMPILE_TIME_FACT'; 'getTypeLayout'='COMPILE_TIME_FACT'
    'getHelperFtn'='FINAL_ADDRESS_SOURCE'; 'getCallInfo'='FINAL_ADDRESS_SOURCE'; 'getAddressOfPInvokeTarget'='FINAL_ADDRESS_SOURCE'
    'allocMem'='OUTPUT_METADATA'; 'allocUnwindInfo'='OUTPUT_METADATA'; 'allocGCInfo'='OUTPUT_METADATA'; 'setEHinfo'='OUTPUT_METADATA'; 'recordRelocation'='OUTPUT_METADATA'
}

switch ($PSCmdlet.ParameterSetName) {
    'Il' {
        $importHits = @(Invoke-RuntimeQuery -Needle $IlOpcode -Scope $jitImporter | Where-Object Path -match '/importer.*\.cpp$')
        foreach ($hit in $importHits) {
            $trees = [regex]::Matches($hit.Text, '\bGT_[A-Z0-9_]+\b') | ForEach-Object Value | Select-Object -Unique
            foreach ($tree in $trees) { Add-Edge $IlOpcode 'imports-as' $tree $hit $null }
            $importMethods = [regex]::Matches($hit.Text, '\bimp[A-Za-z0-9_]+') | ForEach-Object Value | Select-Object -Unique
            foreach ($method in $importMethods) {
                Add-Edge $IlOpcode 'imports-via' $method $hit $null
                if ($method -eq 'gtNewIndir') { Add-Edge $IlOpcode 'imports-as' 'GT_IND' $hit $null }
                if ($method -eq 'gtNewStoreIndNode') { Add-Edge $IlOpcode 'imports-as' 'GT_STOREIND' $hit $null }
            }
        }
        # Indirect-load/store opcode families share importer labels. Querying
        # that exact label is a second targeted lookup, not a file walk.
        $sharedLabel = if ($IlOpcode -like 'CEE_LDIND_*') { 'LDIND:' } elseif ($IlOpcode -like 'CEE_STIND_*') { 'STIND:' } else { $null }
        if ($sharedLabel) {
            foreach ($hit in @(Invoke-RuntimeQuery -Needle $sharedLabel -Scope $jitImporter | Where-Object Path -match '/importer.*\.cpp$')) {
                foreach ($tree in @([regex]::Matches($hit.Text, '\bGT_[A-Z0-9_]+\b') | ForEach-Object Value | Select-Object -Unique)) {
                    Add-Edge $IlOpcode 'imports-as' $tree $hit $null
                }
                foreach ($method in @([regex]::Matches($hit.Text, '\bgtNew[A-Za-z0-9_]+') | ForEach-Object Value | Select-Object -Unique)) {
                    Add-Edge $IlOpcode 'imports-via' $method $hit $null
                    if ($method -eq 'gtNewIndir') { Add-Edge $IlOpcode 'imports-as' 'GT_IND' $hit $null }
                    if ($method -eq 'gtNewStoreIndNode') { Add-Edge $IlOpcode 'imports-as' 'GT_STOREIND' $hit $null }
                }
            }
        }
        if (@($script:records | Where-Object { ($_ | ConvertFrom-Json).edge -in @('imports-as','imports-via') }).Count -eq 0) {
            $synthetic = [pscustomobject]@{Path='src/coreclr/jit';Line=0;Text='no importer hit'}
            Add-Edge $IlOpcode 'dependency' 'UNKNOWN' $synthetic 'UNKNOWN'
        }
    }
    'Tree' {
        foreach ($hit in @(Invoke-RuntimeQuery -Needle $GenTree -Scope $jitLower | Where-Object Path -match '/lower.*\.cpp$') ) {
            $lowering = [regex]::Match($hit.Text, '\b(?:Lower|ContainCheck)[A-Za-z0-9_]+')
            Add-Edge $GenTree 'lowered-by' $(if($lowering.Success){$lowering.Value}else{'lowering-context'}) $hit $null
        }
        foreach ($hit in @(Invoke-RuntimeQuery -Needle $GenTree -Scope $jitCodegen | Where-Object Path -match '/codegen.*\.(cpp|h)$') ) {
            $instruction = [regex]::Match($hit.Text, '\bINS_[A-Za-z0-9_]+')
            if ($instruction.Success) { Add-Edge $GenTree 'emits' $instruction.Value $hit $null }
            else { Add-Edge $GenTree 'handled-by' 'codegen-context' $hit $null }
        }
    }
    'Helper' {
        foreach ($hit in @(Invoke-RuntimeQuery $Helper @('src/coreclr/inc/corinfo.h','src/coreclr/jit'))) { Add-Edge $Helper 'requested-or-defined-by' $Helper $hit $null }
        foreach ($hit in @(Invoke-RuntimeQuery $Helper $aot)) { Add-Edge $Helper 'nativeaot-interpreted-by' $Helper $hit $null }
    }
    'Callback' {
        $classification = if ($classByCallback.ContainsKey($Callback)) { $classByCallback[$Callback] } else { 'UNKNOWN' }
        foreach ($hit in @(Invoke-RuntimeQuery $Callback @('src/coreclr/jit','src/coreclr/inc'))) { Add-Edge $Callback 'requested-by' $Callback $hit $classification }
        foreach ($hit in @(Invoke-RuntimeQuery $Callback $aot)) { Add-Edge $Callback 'nativeaot-interpreted-by' $Callback $hit $classification }
    }
    'Symbol' {
        foreach ($hit in @(Invoke-RuntimeQuery $Symbol @('src/coreclr/jit','src/coreclr/inc','src/coreclr/tools/Common/JitInterface','src/coreclr/tools/aot/ILCompiler.RyuJit/JitInterface','src/coreclr/tools/Common/Compiler/DependencyAnalysis','src/coreclr/tools/Common/Compiler/ObjectWriter'))) {
            Add-Edge $Symbol 'observed-in' $Symbol $hit $null
        }
    }
}

# Follow only instructions discovered by this invocation into xarch encoding.
$discoveredInstructions = @($script:records | ForEach-Object { ($_ | ConvertFrom-Json).to } | Where-Object { $_ -like 'INS_*' } | Select-Object -Unique)
foreach ($instruction in $discoveredInstructions) {
    foreach ($hit in @(Invoke-RuntimeQuery $instruction $jitEncode)) { Add-Edge $instruction 'encoded-by' 'xarch-encoding-context' $hit $null }
}
# Output is the compact graph for this query. Existing query graphs are not
# reread as source and are replaced atomically per invocation.
[IO.File]::WriteAllLines($OutputPath, [string[]]$script:records)
$script:records | ForEach-Object { $_ | ConvertFrom-Json }
