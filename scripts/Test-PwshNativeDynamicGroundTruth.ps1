[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'Fixtures\PwshNative.DynamicDispatch.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $source),
    [ref]$tokens,
    [ref]$errors)
if ($errors.Count -ne 0) { throw 'Dynamic-dispatch source has parse errors.' }

$scriptMethods = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -eq 'Add-Member'
}, $true)
$dynamicInvocations = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
}, $true)
$indexedSelections = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.IndexExpressionAst]
}, $true)

$offset = & $source -Kind offset -Value 7
$scale = & $source -Kind scale -Value 7
if ($offset -ne 10) { throw "Offset dispatch returned $offset; expected 10." }
if ($scale -ne 28) { throw "Scale dispatch returned $scale; expected 28." }

[pscustomobject][ordered]@{
    Status = 'GROUND_TRUTH_PASS'
    Source = (Resolve-Path $source).Path
    ScriptMethods = $scriptMethods.Count
    DynamicInvocations = $dynamicInvocations.Count
    IndexedSelections = $indexedSelections.Count
    OffsetResult = $offset
    ScaleResult = $scale
    NativeLowering = 'NO ADMITTED LOWERING'
}
