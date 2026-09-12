$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Apps\Calculator.CapabilityImageV1.psm1') -Force

function Get-CalculatorCapabilityLambda {
    $path = Join-Path $root 'Conformance\Calculator.ps1'
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw $errors[0]}
    $functionAst=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-CalculatorLogic'},$true))[0]
    $flags=[Reflection.BindingFlags]'Instance,NonPublic'
    $provider=[ScriptBlock].Assembly.GetType('System.Management.Automation.Language.IParameterMetadataProvider',$true)
    $ctor=[ScriptBlock].GetConstructor($flags,$null,[type[]]@($provider,[bool]),$null)
    $scriptBlock=[ScriptBlock]$ctor.Invoke(@($functionAst,$false))
    $data=$scriptBlock.GetType().GetField('_scriptBlockData',$flags).GetValue($scriptBlock)
    $compilerType=[PSObject].Assembly.GetType('System.Management.Automation.Language.Compiler',$true)
    $compiler=[Activator]::CreateInstance($compilerType,$true)
    $compile=$compilerType.GetMethods($flags)|Where-Object{$_.Name -eq 'Compile' -and $_.GetParameters().Count -eq 2}|Select-Object -First 1
    $null=$compile.Invoke($compiler,@($data,$true))
    [System.Linq.Expressions.LambdaExpression]$compilerType.GetField('_endBlockLambda',$flags).GetValue($compiler)
}

$calculatorPath=Join-Path $root 'Conformance\Calculator.ps1'
$calculator=New-Module -AsCustomObject -ArgumentList $calculatorPath {
    param($path)
    $env:DP_SKIP_START='1'
    . $path
    $script:State=[CalculatorState]::new()
    function Get-CalculatorSemanticRoots { [pscustomobject]@{State=$script:State;Buttons=$script:Buttons} }
    Export-ModuleMember -Function Invoke-CalculatorLogic,Get-CalculatorSemanticRoots
}
$roots=$calculator.'Get-CalculatorSemanticRoots'()
$button7=@($roots.Buttons | Where-Object { $_.Label -eq '7' -and $_.Type -eq 'num' })
if($button7.Count -ne 1){throw 'Expected exactly one authentic Calculator num/7 button.'}
$before=[ordered]@{DisplayValue=$roots.State.DisplayValue;ResetOnNext=$roots.State.ResetOnNext;HasLastRepeat=$roots.State.HasLastRepeat}
$calculator.'Invoke-CalculatorLogic'($roots.State,$button7[0].Label,$button7[0].Type)
$after=[ordered]@{DisplayValue=$roots.State.DisplayValue;ResetOnNext=$roots.State.ResetOnNext;HasLastRepeat=$roots.State.HasLastRepeat}
if($after.DisplayValue -ne '7' -or $after.ResetOnNext -or $after.HasLastRepeat){throw 'Authentic hosted Button 7 transition did not produce the expected state.'}

$lambda=Get-CalculatorCapabilityLambda
$image=Export-CalculatorCapabilityImageV1 $lambda
$opaque=@($image.Objects|Where-Object Opaque)
$binderRows=@($opaque|Where-Object{$_.Kind -eq 'SMA.BINDER_DESCRIPTOR'}|ForEach-Object{[pscustomobject]@{Type=$_.Source.GetType().FullName;Count=1}}|Group-Object Type|ForEach-Object{[pscustomobject]@{Dependency=$_.Name;Count=$_.Count;Classification='HOSTED_DEPENDENCY';Reason='Authentic SMA dynamic semantic contract is present, but no detached implementation is admitted.'}})
$variableAst=@($opaque|Where-Object{$_.Source.GetType().FullName -eq 'System.Management.Automation.Language.VariableExpressionAst'})
$method=$calculator.PSObject.Methods['Invoke-CalculatorLogic']
$blockers=[Collections.Generic.List[object]]::new()
$blockers.Add([pscustomobject]@{Dependency='PSScriptMethod.Invoke-CalculatorLogic';Classification='HOSTED_DEPENDENCY';Reason='The authentic callable executes only in the module PowerShell runspace.'})
$blockers.Add([pscustomobject]@{Dependency='PSScriptMethod.Script / ScriptBlock';Classification='HOSTED_DEPENDENCY';Reason='Public ScriptBlock identity exists, but detached invocation is not provided by its public object surface.'})
foreach($binder in $binderRows){$blockers.Add($binder)}
$blockers.Add([pscustomobject]@{Dependency='VariableExpressionAst constants';Classification='UNRESOLVED_SEMANTIC_GAP';Count=$variableAst.Count;Reason='The authentic Lambda carries source-AST variable objects rather than independent detached variable-contract objects.'})
$blockers.Add([pscustomobject]@{Dependency='Operand-specific DynamicExpression reachability';Classification='UNRESOLVED_SEMANTIC_GAP';Reason='The public Lambda graph preserves semantic objects but exposes no public trace proving which DynamicExpression objects execute for num/7 without hosted evaluation.'})

[pscustomobject][ordered]@{
    test='Calculator Button 7 semantic rehosting admission'
    auditPass=$true
    capabilityObjectId=10104
    button=[ordered]@{Label=$button7[0].Label;Type=$button7[0].Type;ExistingObjectId=104}
    authenticHostedTransition=[ordered]@{Before=$before;After=$after;CallableType=$method.GetType().FullName;ScriptType=$method.Script.GetType().FullName}
    authenticSmaSemanticRoot=[ordered]@{Type=$lambda.GetType().FullName;ExpressionObjects=$image.ExpressionObjects;SemanticRootObjectId=$image.SemanticRootObjectId;HostedDescriptors=$image.HostedOpaque}
    reachableSliceStatus='UNRESOLVED_SEMANTIC_GAP'
    blockers=$blockers
    reifiedOperations=@()
    detachedExecution='NOT_ADMITTED'
    sourceTerminationTest='NOT_RUN: native rehosting is blocked before a detached operation can be honestly materialized.'
    proven='The unchanged Calculator hosted path has the requested 0→7, false, false transition; its authentic SMA Lambda and hosted dependencies were observed without reimplementing behavior.'
    notProven='No operand-specific detached closure, native Calculator operation, source-process termination, or post-termination invocation is proven.'
    verdict='BLOCKED: HOSTED_DEPENDENCY and UNRESOLVED_SEMANTIC_GAP prevent detached rehosting.'
}
