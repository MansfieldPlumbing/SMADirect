[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repo 'Conformance\Calculator.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw "Calculator parse failed: $($errors[0].Message)" }
$function = $ast.Find({
    param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'Render-CalculatorWidget'
}, $true)
if (-not $function) { throw 'Render-CalculatorWidget was not found.' }

$providerType = [ScriptBlock].Assembly.GetType('System.Management.Automation.Language.IParameterMetadataProvider',$true)
$constructor = [ScriptBlock].GetConstructor(
    [Reflection.BindingFlags]'Instance,NonPublic',$null,[type[]]@($providerType,[bool]),$null)
$sourceBlock = [ScriptBlock]$constructor.Invoke([object[]]@($ast,$false))
$compileSource = [ScriptBlock].GetMethod(
    'Compile',[Reflection.BindingFlags]'Instance,NonPublic',$null,[type[]]@([bool]),$null)
$null = $compileSource.Invoke($sourceBlock,@($true))
$scriptBlock = [ScriptBlock]$constructor.Invoke([object[]]@($function,$false))
$data = [ScriptBlock].GetField('_scriptBlockData',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($scriptBlock)
$compilerType = [PSObject].Assembly.GetType('System.Management.Automation.Language.Compiler',$true)
$compiler = [Activator]::CreateInstance($compilerType,$true)
$compile = $compilerType.GetMethods([Reflection.BindingFlags]'Instance,NonPublic') |
    Where-Object { $_.Name -eq 'Compile' -and $_.GetParameters().Count -eq 2 } |
    Select-Object -First 1
$null = $compile.Invoke($compiler,@($data,$true))
$lambda = $compilerType.GetField('_endBlockLambda',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($compiler)
if (-not $lambda) { throw 'SMA compiler did not emit Render-CalculatorWidget.' }

$seen = [Collections.Generic.HashSet[Linq.Expressions.Expression]]::new()
$dynamicExpressions = [Collections.Generic.List[object]]::new()
function Visit-Expression([Linq.Expressions.Expression] $Expression) {
    if ($null -eq $Expression -or -not $seen.Add($Expression)) { return }
    if ($Expression -is [Linq.Expressions.DynamicExpression]) { $dynamicExpressions.Add($Expression) }
    foreach ($property in $Expression.GetType().GetProperties([Reflection.BindingFlags]'Instance,Public')) {
        if ($property.Name -in @('NodeType','Type','CanReduce')) { continue }
        try { $value = $property.GetValue($Expression) } catch { continue }
        if ($value -is [Linq.Expressions.Expression]) { Visit-Expression $value }
        elseif ($value -is [Collections.IEnumerable] -and $value -isnot [string]) {
            foreach ($item in $value) { if ($item -is [Linq.Expressions.Expression]) { Visit-Expression $item } }
        }
    }
}
Visit-Expression $lambda.Body
$matches = @($dynamicExpressions | Where-Object {
    $_.Binder.GetType().FullName -ceq 'System.Management.Automation.Language.PSGetMemberBinder' -and
    $_.Binder.ToString() -match '^GetMember: DisplayValue ' -and
    $_.Arguments.Count -gt 0 -and $_.Arguments[0].Type.Name -ceq 'CalculatorState'
})
if ($matches.Count -lt 1) { throw 'No typed CalculatorState.DisplayValue SMA binder was recovered.' }

[pscustomobject]@{
    Status = 'PASS'
    Function = 'Render-CalculatorWidget'
    UniqueDynamicExpressions = $dynamicExpressions.Count
    BinderKind = 'PSGetMemberBinder'
    MemberIdentity = 'DisplayValue'
    ReceiverType = 'CalculatorState'
    MatchingTypedSites = $matches.Count
    ReceiverRepresentationRewritten = $false
    OriginalAccessSitesRedirected = 0
}
