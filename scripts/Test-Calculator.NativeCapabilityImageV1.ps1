$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Apps\Calculator.CapabilityImageV1.psm1') -Force

function Get-AuthenticCapabilityLambda {
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
    return [System.Linq.Expressions.LambdaExpression]$compilerType.GetField('_endBlockLambda',$flags).GetValue($compiler)
}

$source = Join-Path $root 'Apps\ObjectReplica\CalculatorCapabilityImageV1Replica.cpp'
$exe = Join-Path $root 'Apps\ObjectReplica\CalculatorCapabilityImageV1Replica.exe'
$vcvars = 'C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "Missing C++ build environment: $vcvars" }
$build = "call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /Fe:`"$exe`" `"$source`" d3d12.lib dxgi.lib"
cmd.exe /c $build | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw 'Capability replica native build failed.' }

$image = Export-CalculatorCapabilityImageV1 (Get-AuthenticCapabilityLambda)
$imageFile = Join-Path $env:TEMP "smadirect-capability-$([guid]::NewGuid().ToString('N')).bin"
[IO.File]::WriteAllBytes($imageFile,$image.Bytes)
$id = [guid]::NewGuid().ToString('N')
$resourceName = "Global\SMADirect_Capability_$id"
$fenceName = "Global\SMADirect_CapabilityFence_$id"
$producerOutput = Join-Path $env:TEMP "smadirect-capability-producer-$id.txt"
try {
    $producer = Start-Process $exe -ArgumentList @('producer',$resourceName,$fenceName,$imageFile) -RedirectStandardOutput $producerOutput -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    $native = & $exe consumer $resourceName $fenceName 2>&1
    $exitCode = $LASTEXITCODE
    $producer.WaitForExit(7000) | Out-Null
    if ($exitCode -ne 0 -or $native -notmatch 'verdict=PASS') { throw "Native capability image receipt failed: $native" }
    [pscustomobject][ordered]@{
        test = 'Calculator CapabilityImage v1 native replica'
        pass = $true
        schema = $image.Schema
        capabilityId = $image.CapabilityId
        producer = "objects=$($image.ObjectCount) expressions=$($image.ExpressionObjects) members=$($image.MemberCount) opaque=$($image.HostedOpaque)"
        native = ($native -join "`n")
        proven = 'Authentic SMA LambdaExpression population crossed the shared DEFAULT-buffer pipe and reconstructed as a non-executing native object yard with resolved references.'
        notProven = 'No expression, binder, ScriptBlock, or Calculator behavior executes in the native process.'
        verdict = 'PASS'
    }
}
finally {
    Remove-Item $imageFile,$producerOutput -Force -ErrorAction SilentlyContinue
}
