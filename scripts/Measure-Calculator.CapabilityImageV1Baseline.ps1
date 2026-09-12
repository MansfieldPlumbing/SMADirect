$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Apps\Calculator.CapabilityImageV1.psm1') -Force

function Get-CalculatorCapability10104Lambda {
    $path = Join-Path $root 'Conformance\Calculator.ps1'
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw $errors[0] }
    $functionAst = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-CalculatorLogic' },$true))[0]
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $provider = [ScriptBlock].Assembly.GetType('System.Management.Automation.Language.IParameterMetadataProvider',$true)
    $ctor = [ScriptBlock].GetConstructor($flags,$null,[type[]]@($provider,[bool]),$null)
    $scriptBlock = [ScriptBlock]$ctor.Invoke(@($functionAst,$false))
    $data = $scriptBlock.GetType().GetField('_scriptBlockData',$flags).GetValue($scriptBlock)
    $compilerType = [PSObject].Assembly.GetType('System.Management.Automation.Language.Compiler',$true)
    $compiler = [Activator]::CreateInstance($compilerType,$true)
    $compile = $compilerType.GetMethods($flags) | Where-Object { $_.Name -eq 'Compile' -and $_.GetParameters().Count -eq 2 } | Select-Object -First 1
    $null = $compile.Invoke($compiler,@($data,$true))
    [System.Linq.Expressions.LambdaExpression]$compilerType.GetField('_endBlockLambda',$flags).GetValue($compiler)
}

$image = Export-CalculatorCapabilityImageV1 (Get-CalculatorCapability10104Lambda)
$bytes = $image.Bytes
$read32 = { param([int]$Offset) [BitConverter]::ToUInt32($bytes,$Offset) }
$objectOffset = & $read32 40; $memberOffset = & $read32 44; $valueOffset = & $read32 48; $arenaOffset = & $read32 52
$native = Join-Path $root 'Apps\ObjectReplica\CalculatorCapabilityImageV1Replica.exe'

[pscustomobject][ordered]@{
    test = 'Calculator CapabilityImage v1 frozen physical baseline'
    pass = $true
    schema = $image.Schema
    capabilityId = $image.CapabilityId
    imageBytes = $bytes.Length
    headerBytes = 56
    objectDirectoryBytes = $memberOffset - $objectOffset
    memberDirectoryBytes = $valueOffset - $memberOffset
    value64Bytes = $arenaOffset - $valueOffset
    stringArenaBytes = $bytes.Length - $arenaOffset
    objectCount = $image.ObjectCount
    memberCount = $image.MemberCount
    value64Words = $image.ValueWordCount
    nativeReplicaExeBytes = if (Test-Path $native) { (Get-Item $native).Length } else { $null }
    proven = 'This is a physical measurement of the frozen, non-executing capability image only.'
    notProven = 'No native execution or semantic detachment is measured.'
    verdict = 'PASS'
}
