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

function Get-PublicFact([object]$Object,[string]$Name) {
    try { return $Object.$Name } catch { return $null }
}

function Classify-Descriptor($Record) {
    $source = $Record.Source
    $typeName = $source.GetType().FullName
    $category = 'UNRESOLVED_SEMANTIC_GAP'; $role = 'Public surface does not yet state a detachable contract.'; $evidence = $typeName
    switch ($Record.Kind) {
        'SMA.BINDER_DESCRIPTOR' {
            $category = 'SEMANTIC_CONTRACT'
            $role = switch -Regex ($typeName) {
                'PSGetMemberBinder' { 'PowerShell member lookup'; break }
                'PSSetMemberBinder' { 'PowerShell member assignment'; break }
                'PSInvokeMemberBinder' { 'PowerShell member invocation'; break }
                'PSBinaryOperationBinder' { 'PowerShell binary operation'; break }
                'PSConvertBinder' { 'PowerShell conversion'; break }
                'PSToStringBinder' { 'PowerShell string conversion'; break }
                'PSEnumerableBinder' { 'PowerShell enumeration'; break }
                'PSPipeWriterBinder' { 'PowerShell pipeline output'; break }
                'PSVariableAssignmentBinder' { 'PowerShell variable assignment'; break }
                default { 'PowerShell dynamic operation' }
            }
            $evidence = "public binder type=$typeName"
        }
        'SMA.METHOD_DESCRIPTOR' {
            $category = 'REPRESENTABLE_DATA'; $role = 'Stable method/constructor identity'
            $evidence = "public member=$($source.DeclaringType.FullName)::$($source.Name)"
        }
        'SMA.MEMBER_DESCRIPTOR' {
            $category = 'REPRESENTABLE_DATA'; $role = 'Stable field/property identity'
            $evidence = "public member=$($source.DeclaringType.FullName)::$($source.Name)"
        }
        'SMA.TYPE_DESCRIPTOR' {
            $category = 'REPRESENTABLE_DATA'; $role = 'Stable type identity'
            $evidence = "public type=$($source.FullName); assembly=$($source.Assembly.GetName().Name)"
        }
        'SMA.CONSTANT_DESCRIPTOR' {
            switch ($typeName) {
                'System.Char' { $category='REPRESENTABLE_DATA'; $role='Scalar character constant'; $evidence="public scalar=$source"; break }
                'System.Management.Automation.VariablePath' { $category='SEMANTIC_CONTRACT'; $role='PowerShell variable identity'; $evidence="public userPath=$(Get-PublicFact $source 'UserPath')"; break }
                'System.Management.Automation.Language.VariableExpressionAst' { $category='UNRESOLVED_SEMANTIC_GAP'; $role='Variable reference is exposed as source-AST object, not an independent variable-contract object'; $evidence="public type=$typeName"; break }
                default { $category='UNRESOLVED_SEMANTIC_GAP'; $role='Constant has no admitted scalar/data representation yet'; $evidence="public type=$typeName" }
            }
        }
        'SMA.RUNTIME_OPAQUE' {
            switch ($typeName) {
                'System.Linq.Expressions.LabelTarget' { $category='SEMANTIC_CONTRACT'; $role='Expression control-flow target'; $evidence="public name=$(Get-PublicFact $source 'Name'); type=$((Get-PublicFact $source 'Type').FullName)"; break }
                'System.Linq.Expressions.SwitchCase' { $category='SEMANTIC_CONTRACT'; $role='Expression switch arm'; $evidence='public Body and TestValues expression relationships'; break }
                'System.Linq.Expressions.CatchBlock' { $category='SEMANTIC_CONTRACT'; $role='Expression exception-handling clause'; $evidence='public Body, Filter, Test, and Variable relationships'; break }
                default { $category='UNRESOLVED_SEMANTIC_GAP'; $role='Runtime object has no classified public contract'; $evidence="public type=$typeName" }
            }
        }
    }
    [pscustomobject][ordered]@{ObjectId=$Record.Id;DescriptorKind=$Record.Kind;PublicType=$typeName;Classification=$category;SemanticRole=$role;Evidence=$evidence}
}

$image = Export-CalculatorCapabilityImageV1 (Get-CalculatorCapability10104Lambda)
$rows = @($image.Objects | Where-Object Opaque | ForEach-Object { Classify-Descriptor $_ })
$summary = @($rows | Group-Object Classification | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Classification=$_.Name; Count=$_.Count } })
$unclassified = @($rows | Where-Object { $_.Classification -notin @('REPRESENTABLE_DATA','SEMANTIC_CONTRACT','PLATFORM_CONTRACT','HOST_IMPLEMENTATION','UNRESOLVED_SEMANTIC_GAP') })
$byKind = @($rows | Group-Object DescriptorKind,Classification,SemanticRole | Sort-Object Name | ForEach-Object { [pscustomobject]@{Key=$_.Name;Count=$_.Count} })

[pscustomobject][ordered]@{
    test = 'Calculator capability 10104 hosted dependency classification'
    pass = ($rows.Count -eq $image.HostedOpaque -and $unclassified.Count -eq 0)
    schema = $image.Schema
    capabilityId = $image.CapabilityId
    descriptorCount = $rows.Count
    classificationSummary = $summary
    descriptorSummary = $byKind
    descriptors = $rows
    proven = 'Every hosted descriptor in the authentic SMA-created capability population has a classification based only on its public type and public semantic surface.'
    notProven = 'Classification does not detach, execute, or reproduce any expression or PowerShell contract.'
    verdict = if ($rows.Count -eq $image.HostedOpaque -and $unclassified.Count -eq 0) { 'PASS' } else { 'FAIL' }
}
