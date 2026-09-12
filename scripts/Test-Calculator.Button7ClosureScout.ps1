<#!
Structural candidate scout only. This receipt does not claim runtime execution
order, detached behavior, or a native Calculator implementation.
#>
[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path $env:TEMP 'SMADirectButton7StructuralCapsule.bin'),
    [ValidateSet('All', 'Structural', 'VariablePlacement', 'BinderRuleProjection', 'RuntimeReachability', 'SemanticObjectProjection')]
    [string] $ThroughLayer = 'All',
    [string] $AppendLogPath
)

<#
Canonical layered Button-7 scout.

Usage:
  .\Tests\Test-Calculator.Button7ClosureScout.ps1
  .\Tests\Test-Calculator.Button7ClosureScout.ps1 -ThroughLayer VariablePlacement
  .\Tests\Test-Calculator.Button7ClosureScout.ps1 -AppendLogPath .\my-receipts.jsonl

Layers are extended in this file.  -AppendLogPath appends the compact final
receipt to a caller-selected JSONL file; no log directory is assumed.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $root 'Conformance\Calculator.ps1'

function Compile-AuthenticLambda([string] $Text) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, $sourcePath, [ref] $tokens, [ref] $errors)
    if ($errors.Count) { throw $errors[0] }
    $predicate = { param($node) ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($node.Name -eq 'Invoke-CalculatorLogic') }
    $function = @($ast.FindAll($predicate, $true))[0]
    $variablePredicate = { param($node) ($node -is [System.Management.Automation.Language.VariableExpressionAst]) -and ($node.VariablePath.UserPath -eq 'type') -and ($node.Parent -isnot [System.Management.Automation.Language.ParameterAst]) }
    $typeBodyVariableBeforeCompile = @($function.Body.FindAll($variablePredicate, $true))[0]
    $tupleIndexProperty = $typeBodyVariableBeforeCompile.GetType().GetProperty('TupleIndex', [Reflection.BindingFlags] 'Instance,Public,NonPublic')
    $typeBodyTupleIndexBeforeCompile = [int] $tupleIndexProperty.GetValue($typeBodyVariableBeforeCompile)
    $typeBodyHashBeforeCompile = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($typeBodyVariableBeforeCompile)
    $flags = [Reflection.BindingFlags] 'Instance,NonPublic'
    $provider = [ScriptBlock].Assembly.GetType('System.Management.Automation.Language.IParameterMetadataProvider', $true)
    $ctor = [ScriptBlock].GetConstructor($flags, $null, [type[]] @($provider, [bool]), $null)
    $compileOne = [ScriptBlock].GetMethod('Compile', $flags, $null, [type[]] @([bool]), $null)
    $top = [ScriptBlock] $ctor.Invoke(@($ast, $false)); $null = $compileOne.Invoke($top, @($true))
    $block = [ScriptBlock] $ctor.Invoke(@($function, $false)); $data = $block.GetType().GetField('_scriptBlockData', $flags).GetValue($block)
    $compilerType = [PSObject].Assembly.GetType('System.Management.Automation.Language.Compiler', $true); $compiler = [Activator]::CreateInstance($compilerType, $true)
    $compile = $compilerType.GetMethods($flags) | Where-Object { ($_.Name -eq 'Compile') -and ($_.GetParameters().Count -eq 2) } | Select-Object -First 1
    $null = $compile.Invoke($compiler, @($data, $true))
    [pscustomobject] @{ Ast = $ast; FunctionAst = $function; Tokens = $tokens; Data = $data; Compiler = $compiler; TypeBodyVariable = $typeBodyVariableBeforeCompile; TypeBodyTupleIndexBeforeCompile = $typeBodyTupleIndexBeforeCompile; TypeBodyHashBeforeCompile = $typeBodyHashBeforeCompile; Lambda = [System.Linq.Expressions.LambdaExpression] $compilerType.GetField('_endBlockLambda', $flags).GetValue($compiler) }
}

function Get-PublicValue($Object, [string] $Property) {
    $propertyInfo = $Object.GetType().GetProperty($Property, [Reflection.BindingFlags] 'Instance,Public')
    if ($propertyInfo) { try { return $propertyInfo.GetValue($Object) } catch { return $null } }
    return $null
}

function Get-InstanceMemberValue($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $flags = [Reflection.BindingFlags] 'Instance,Public,NonPublic'
    $propertyInfo = $Object.GetType().GetProperty($Name, $flags)
    if ($propertyInfo) { try { return $propertyInfo.GetValue($Object) } catch { return $null } }
    $fieldInfo = $Object.GetType().GetField($Name, $flags)
    if ($fieldInfo) { try { return $fieldInfo.GetValue($Object) } catch { return $null } }
    return $null
}

function Complete-LayeredReceipt($Receipt) {
    if ($AppendLogPath) {
        $parent = Split-Path $AppendLogPath -Parent
        if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
        Add-Content -LiteralPath $AppendLogPath -Value ($Receipt | ConvertTo-Json -Depth 12 -Compress) -Encoding utf8
    }
    return $Receipt
}

function Get-CompiledSemanticPopulation([System.Linq.Expressions.LambdaExpression] $Lambda) {
    $seen = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $queue = [Collections.Generic.Queue[object]]::new(); $queue.Enqueue($Lambda)
    $dynamic = [Collections.Generic.List[object]]::new(); $nodeTypes = [Collections.Generic.List[string]]::new(); $id = 0
    while ($queue.Count) {
        $node = $queue.Dequeue()
        if ((-not $seen.Add($node)) -or ($node -isnot [System.Linq.Expressions.Expression])) { continue }
        $id++; $nodeTypes.Add([string] $node.NodeType)
        if ($node -is [System.Linq.Expressions.DynamicExpression]) {
            $binder = $node.Binder
            $dynamic.Add([pscustomobject] [ordered] @{ ExpressionObjectId = $id; BinderType = $binder.GetType().FullName; Name = (Get-PublicValue $binder 'Name'); Operation = [string] (Get-PublicValue $binder 'Operation'); Explicit = (Get-PublicValue $binder 'Explicit'); DelegateType = $node.DelegateType.FullName; Expression = $node })
        }
        foreach ($propertyInfo in $node.GetType().GetProperties([Reflection.BindingFlags] 'Instance,Public')) {
            try { $value = $propertyInfo.GetValue($node) } catch { continue }
            if ($value -is [System.Linq.Expressions.Expression]) { $queue.Enqueue($value) }
            elseif (($value -is [Collections.IEnumerable]) -and ($value -isnot [string])) { foreach ($child in $value) { if ($child -is [System.Linq.Expressions.Expression]) { $queue.Enqueue($child) } } }
        }
    }
    [pscustomobject] @{ Dynamic = @($dynamic); NodeTypes = @($nodeTypes | Group-Object | ForEach-Object { [pscustomobject] @{ NodeType = $_.Name; Count = $_.Count } }) }
}

function Replace-Extent([string] $Text, $Extent, [string] $Replacement) { $Text.Substring(0, $Extent.StartOffset) + $Replacement + $Text.Substring($Extent.EndOffset) }
function Find-OperatorToken($Tokens, $Binary) { @($Tokens | Where-Object { ($_.Extent.StartOffset -ge $Binary.Left.Extent.EndOffset) -and ($_.Extent.EndOffset -le $Binary.Right.Extent.StartOffset) -and ($_.Kind -eq $Binary.Operator) }) | Select-Object -First 1 }
function Get-UnquotedText([string] $Text) { $Text.Trim([char[]] @([char] 39, [char] 34)) }

function Get-Button7AstCandidateSlice($Ast, $Tokens) {
    $functionPredicate = { param($n) ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($n.Name -eq 'Invoke-CalculatorLogic') }
    $function = @($Ast.FindAll($functionPredicate, $true))[0]
    $outerIf = @($function.Body.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.IfStatementAst] })[0]
    $binaryPredicate = { param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] }
    $typeNum = @($outerIf.Clauses[0][0].FindAll($binaryPredicate, $true) | Where-Object { $_.Operator -eq [System.Management.Automation.Language.TokenKind]::Ieq })[0]
    $numBody = $outerIf.Clauses[0][1]
    $innerIf = @($numBody.Statements | Where-Object { $_ -is [System.Management.Automation.Language.IfStatementAst] })[0]
    $logicalOr = @($innerIf.Clauses[0][0].FindAll($binaryPredicate, $true) | Where-Object { $_.Operator -eq [System.Management.Automation.Language.TokenKind]::Or })[0]
    $displayZero = @($logicalOr.FindAll($binaryPredicate, $true) | Where-Object { $_.Operator -eq [System.Management.Automation.Language.TokenKind]::Ieq })[0]
    $initialThen = $innerIf.Clauses[0][1]
    $labelDot = @($initialThen.FindAll($binaryPredicate, $true) | Where-Object { ($_.Left.Extent.Text -eq '$label') -and ((Get-UnquotedText $_.Right.Extent.Text) -eq '.') })[0]
    $memberPredicate = { param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }
    $displayGet = @($displayZero.FindAll($memberPredicate, $true) | Where-Object { $_.Member.Extent.Text -eq 'DisplayValue' })[0]
    $initialMembers = @($initialThen.FindAll($memberPredicate, $true))
    $displaySet = @($initialMembers | Where-Object { $_.Member.Extent.Text -eq 'DisplayValue' })[0]
    $resetSet = @($initialMembers | Where-Object { $_.Member.Extent.Text -eq 'ResetOnNext' })[0]
    $hasLastSet = @($numBody.FindAll($memberPredicate, $true) | Where-Object { ($_.Member.Extent.Text -eq 'HasLastRepeat') -and ($_.Extent.StartOffset -gt $innerIf.Extent.EndOffset) })[0]
    $records = [Collections.Generic.List[object]]::new(); $next = 1
    foreach ($pair in @(@('type_eq_num', $typeNum, 'binary'), @('display_eq_zero', $displayZero, 'binary'), @('label_eq_dot', $labelDot, 'binary'), @('display_or_reset', $logicalOr, 'control'), @('member_display_get', $displayGet, 'member'), @('member_display_set', $displaySet, 'member'), @('member_reset_set', $resetSet, 'member'), @('member_haslast_set', $hasLastSet, 'member'))) {
        if ($null -ne $pair[1]) { $records.Add([pscustomobject] @{ Id = $next; Name = $pair[0]; Ast = $pair[1]; Kind = $pair[2] }); $next++ }
    }
    return $records
}

# //////////////////////////////////////////////////////////////////////
# LAYER — SOURCE-CONTRACT VARIABLE PLACEMENT
# //////////////////////////////////////////////////////////////////////
$GetButton7VariablePlacement = {
    param($Fixture, $StructuralCandidates)

    $variablePredicate = { param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }
    $compilerInputAst = Get-InstanceMemberValue $Fixture.Data 'Ast'
    $inputRootIsParseRoot = [object]::ReferenceEquals($Fixture.Ast, $compilerInputAst)
    $inputRootIsFunctionAst = [object]::ReferenceEquals($Fixture.FunctionAst, $compilerInputAst)
    $inputRootContainsCandidate = {
        param($Candidate)
        if ($null -eq $compilerInputAst) { return $false }
        foreach ($node in $compilerInputAst.FindAll({ param($n) $true }, $true)) {
            if ([object]::ReferenceEquals($node, $Candidate.Ast)) { return $true }
        }
        return $false
    }

    $parameterDeclarations = [Collections.Generic.List[object]]::new()
    foreach ($parameter in $Fixture.FunctionAst.Parameters) {
        $parameterName = $parameter.Name.VariablePath.UserPath
        if ($parameterName -notin @('state', 'label', 'type')) { continue }
        $parameterDeclarations.Add([pscustomobject] [ordered] @{
            VariablePath = $parameterName
            ParentType = $parameter.Name.Parent.GetType().FullName
            TupleIndex = [int] (Get-InstanceMemberValue $parameter.Name 'TupleIndex')
            Extent = $parameter.Name.Extent.Text
            Start = $parameter.Name.Extent.StartOffset
            End = $parameter.Name.Extent.EndOffset
        })
    }

    $occurrences = [Collections.Generic.List[object]]::new()
    foreach ($candidate in $StructuralCandidates) {
        $variables = @($candidate.Ast.FindAll($variablePredicate, $true))
        foreach ($variable in $variables) {
            $path = $variable.VariablePath.UserPath
            if ($path -notin @('state', 'label', 'type')) { continue }
            $tupleIndex = [int] (Get-InstanceMemberValue $variable 'TupleIndex')
            $occurrences.Add([pscustomobject] [ordered] @{
                Candidate = $candidate.Name
                VariablePath = $path
                TupleIndex = $tupleIndex
                Automatic = [bool] (Get-InstanceMemberValue $variable 'Automatic')
                Assigned = [bool] (Get-InstanceMemberValue $variable 'Assigned')
                StaticType = [string] (Get-InstanceMemberValue $variable 'StaticType')
                Extent = $variable.Extent.Text
                Start = $variable.Extent.StartOffset
                End = $variable.Extent.EndOffset
                ParentType = $variable.Parent.GetType().FullName
                CandidateIsInCompilerInputAst = (& $inputRootContainsCandidate $candidate)
                VariableIsInCompilerInputAst = (& $inputRootContainsCandidate ([pscustomobject] @{ Ast = $variable }))
            })
        }
    }

    $expected = [ordered] @{ state = 9; label = 10; type = 11 }
    $variables = [Collections.Generic.List[object]]::new()
    foreach ($name in $expected.Keys) {
        $entries = @($occurrences | Where-Object { $_.VariablePath -eq $name })
        if ($entries.Count -eq 0) { throw "No Button-7 structural-candidate VariableExpressionAst found for `$${name}." }
        $indices = @($entries | ForEach-Object { $_.TupleIndex } | Sort-Object -Unique)
        if ($indices.Count -ne 1) { throw "TupleIndex is inconsistent across Button-7 candidate occurrences of `$${name}: $($indices -join ', ')." }
        $actual = [int] $indices[0]
        $variables.Add([pscustomobject] [ordered] @{
            VariablePath = $name
            ExpectedTupleIndex = $expected[$name]
            ObservedTupleIndex = $actual
            Classification = if ($actual -ge 0) { 'SOURCE_CONTRACT_LOCAL_TUPLE' } else { 'SOURCE_CONTRACT_DYNAMIC_LOOKUP' }
            VariableOpsLookupRequired = ($actual -lt 0)
            SourcePredictionMatch = (($actual -ge 0) -and ($actual -eq $expected[$name]))
            Occurrences = @($entries)
        })
    }

    # Compiler.Compile stores VariableAnalysis' final map on this exact
    # CompiledScriptBlockData instance; this inspects it directly.
    $map = Get-InstanceMemberValue $Fixture.Data 'NameToIndexMap'
    $mapEntries = [Collections.Generic.List[object]]::new()
    $allMapEntries = [Collections.Generic.List[object]]::new()
    if ($map) {
        foreach ($entry in $map.GetEnumerator()) {
            $allMapEntries.Add([pscustomobject] @{ VariablePath = [string] $entry.Key; TupleIndex = [int] $entry.Value })
        }
        foreach ($name in $expected.Keys) {
            $found = $false; $value = $null
            try { $found = $map.TryGetValue($name, [ref] $value) } catch { $found = $false }
            $mapEntries.Add([pscustomobject] @{ VariablePath = $name; Found = $found; TupleIndex = if ($found) { [int] $value } else { $null } })
        }
    }
    $mapMatchesPrediction = ($mapEntries.Count -eq 3) -and (-not @($mapEntries | Where-Object { (-not $_.Found) -or ($_.TupleIndex -ne $expected[$_.VariablePath]) }).Count)
    $bodyMatchesMap = $true
    foreach ($variableSummary in $variables) {
        $entry = @($mapEntries | Where-Object { $_.VariablePath -eq $variableSummary.VariablePath })[0]
        if (($null -eq $entry) -or (-not $entry.Found) -or ($variableSummary.ObservedTupleIndex -ne $entry.TupleIndex)) { $bodyMatchesMap = $false; break }
    }

    $typeBodyVariable = $Fixture.TypeBodyVariable
    $tupleProperty = $typeBodyVariable.GetType().GetProperty('TupleIndex', [Reflection.BindingFlags] 'Instance,Public,NonPublic')
    $tupleField = $typeBodyVariable.GetType().GetField('<TupleIndex>k__BackingField', [Reflection.BindingFlags] 'Instance,Public,NonPublic')
    $typeProbe = [pscustomobject] [ordered] @{
        RuntimeType = $typeBodyVariable.GetType().FullName
        PropertyUsed = $tupleProperty.Name
        PropertyDeclaringType = $tupleProperty.DeclaringType.FullName
        GetterVisibility = if ($tupleProperty.GetMethod.IsPublic) { 'PUBLIC' } elseif ($tupleProperty.GetMethod.IsAssembly) { 'INTERNAL' } else { 'NONPUBLIC' }
        BackingField = $tupleField.Name
        BackingFieldDeclaringType = $tupleField.DeclaringType.FullName
        RawPropertyValue = $tupleProperty.GetValue($typeBodyVariable)
        RawBackingFieldValue = $tupleField.GetValue($typeBodyVariable)
        Extent = $typeBodyVariable.Extent.Text
        Start = $typeBodyVariable.Extent.StartOffset
        End = $typeBodyVariable.Extent.EndOffset
        RuntimeHashBeforeCompile = $Fixture.TypeBodyHashBeforeCompile
        RuntimeHashAfterCompile = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($typeBodyVariable)
        TupleIndexBeforeCompile = $Fixture.TypeBodyTupleIndexBeforeCompile
        TupleIndexAfterCompile = [int] $tupleProperty.GetValue($typeBodyVariable)
        SameObjectBeforeAfterCompile = $true
        IsInCompilerInputAst = (& $inputRootContainsCandidate ([pscustomobject] @{ Ast = $typeBodyVariable }))
    }
    [pscustomobject] [ordered] @{
        CompilerInputAstPresent = ($null -ne $compilerInputAst)
        CompilerInputAstIsParseRoot = $inputRootIsParseRoot
        CompilerInputAstIsFunctionAst = $inputRootIsFunctionAst
        ParameterDeclarations = @($parameterDeclarations)
        Variables = @($variables)
        Occurrences = @($occurrences)
        CompilerNameToIndexMap = [pscustomobject] @{ Available = ($null -ne $map); Entries = @($mapEntries); AllEntries = @($allMapEntries | Sort-Object TupleIndex, VariablePath) }
        TypeBodyVariableReflection = $typeProbe
        SourcePredictionPass = ($inputRootIsFunctionAst -and $mapMatchesPrediction -and (-not @($variables | Where-Object { -not $_.SourcePredictionMatch }).Count))
        AstFieldMapConsistency = if ($bodyMatchesMap) { 'ESTABLISHED' } else { 'UNRESOLVED' }
    }
}

# //////////////////////////////////////////////////////////////////////
# LAYER 3 — AUTHENTIC BINDER RULE PROJECTION
# //////////////////////////////////////////////////////////////////////
$GetButton7BinderRuleProjection = {
    param($Fixture, $Population)

    $engineContext = Get-InstanceMemberValue $ExecutionContext '_context'
    $hasEverUsedConstrainedLanguage = [bool] (Get-InstanceMemberValue $engineContext 'HasEverUsedConstrainedLanguage')
    # The unchanged source owns CalculatorState's definition. This module is
    # used only to materialize an admitted representative receiver for binder
    # rule generation; it does not invoke Calculator behavior.
    $calculator = New-Module -AsCustomObject -ArgumentList $sourcePath {
        param($path)
        $env:DP_SKIP_START = '1'
        . $path
        $script:Layer3State = [CalculatorState]::new()
        function Get-Layer3State { $script:Layer3State }
        Export-ModuleMember -Function Get-Layer3State
    }
    $state = $calculator.'Get-Layer3State'()
    $state.DisplayValue = '0'; $state.ResetOnNext = $false; $state.HasLastRepeat = $false
    $empty = [System.Dynamic.BindingRestrictions]::Empty
    $newMeta = { param($value) [System.Dynamic.DynamicMetaObject]::new([System.Linq.Expressions.Expression]::Constant($value, $value.GetType()), $empty, $value) }

    function Get-RuleExpressionFacts($Expression) {
        $seen = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
        $queue = [Collections.Generic.Queue[object]]::new(); $queue.Enqueue($Expression)
        $methods = [Collections.Generic.List[string]]::new(); $properties = [Collections.Generic.List[string]]::new(); $fields = [Collections.Generic.List[string]]::new()
        while ($queue.Count) {
            $node = $queue.Dequeue()
            if (($null -eq $node) -or (-not $seen.Add($node)) -or ($node -isnot [System.Linq.Expressions.Expression])) { continue }
            if ($node -is [System.Linq.Expressions.MethodCallExpression]) { $methods.Add("$($node.Method.DeclaringType.FullName)::$($node.Method.Name)") }
            elseif ($node -is [System.Linq.Expressions.MemberExpression]) {
                if ($node.Member -is [Reflection.PropertyInfo]) { $properties.Add("$($node.Member.DeclaringType.FullName).$($node.Member.Name)") }
                elseif ($node.Member -is [Reflection.FieldInfo]) { $fields.Add("$($node.Member.DeclaringType.FullName).$($node.Member.Name)") }
            }
            foreach ($propertyInfo in $node.GetType().GetProperties([Reflection.BindingFlags] 'Instance,Public')) {
                try { $value = $propertyInfo.GetValue($node) } catch { continue }
                if ($value -is [System.Linq.Expressions.Expression]) { $queue.Enqueue($value) }
                elseif (($value -is [Collections.IEnumerable]) -and ($value -isnot [string])) { foreach ($child in $value) { if ($child -is [System.Linq.Expressions.Expression]) { $queue.Enqueue($child) } } }
            }
        }
        [pscustomobject] @{ Methods = @($methods | Sort-Object -Unique); Properties = @($properties | Sort-Object -Unique); Fields = @($fields | Sort-Object -Unique) }
    }

    function Get-BinderState($Binder) {
        $state = [ordered] @{ Version = (Get-InstanceMemberValue $Binder '_version'); HasTypeTableMember = (Get-InstanceMemberValue $Binder '_hasTypeTableMember'); HasInstanceMember = (Get-InstanceMemberValue $Binder '_hasInstanceMember'); ClassScope = (Get-InstanceMemberValue $Binder '_classScope'); Static = (Get-InstanceMemberValue $Binder '_static') }
        $getBinder = Get-InstanceMemberValue $Binder '_getMemberBinder'
        if ($getBinder) { $state.UnderlyingGetMemberBinder = Get-BinderState $getBinder }
        [pscustomobject] $state
    }

    function Project-Rule($Site, $Dynamic, $Target, $Arguments) {
        $binder = $Dynamic.Expression.Binder
        $rule = $binder.Bind($Target, [System.Dynamic.DynamicMetaObject[]] $Arguments)
        $restriction = $rule.Restrictions.ToExpression()
        $expressionFacts = Get-RuleExpressionFacts $rule.Expression
        $restrictionFacts = Get-RuleExpressionFacts $restriction
        [pscustomobject] [ordered] @{
            SourceSiteIdentity = $Site
            DynamicOrdinal = 'NOT_USED_BY_DESIGN'
            DynamicExpressionObjectId = $Dynamic.ExpressionObjectId
            BinderObjectReferenceHash = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($binder)
            BinderRuntimeType = $binder.GetType().FullName
            DelegateType = $Dynamic.DelegateType
            BinderSemanticProperties = [pscustomobject] @{ Name = (Get-PublicValue $binder 'Name'); Operation = [string] (Get-PublicValue $binder 'Operation'); DestinationType = [string] (Get-PublicValue $binder 'Type'); Explicit = (Get-PublicValue $binder 'Explicit') }
            BinderState = Get-BinderState $binder
            SpecializationTargetRuntimeType = $Target.Value.GetType().FullName
            SpecializationArgumentRuntimeTypes = @($Arguments | ForEach-Object { $_.Value.GetType().FullName })
            RuleExpression = [pscustomobject] @{ NodeType = [string] $rule.Expression.NodeType; Type = $rule.Expression.Type.FullName; Diagnostic = [string] $rule.Expression }
            RuleRestriction = [pscustomobject] @{ NodeType = [string] $restriction.NodeType; Type = $restriction.Type.FullName; Diagnostic = [string] $restriction }
            ReferencedMethods = $expressionFacts.Methods
            ReferencedProperties = $expressionFacts.Properties
            ReferencedFields = $expressionFacts.Fields
            BindTimeDependencies = @("AUTHENTIC_BINDER_BIND: binder fallback / member adapter resolution; HasEverUsedConstrainedLanguage=$hasEverUsedConstrainedLanguage", 'Potential bind-time host services defined by PowerShell source: ExecutionContext, TypeTable, DotNetAdapter, reflection metadata')
            RuleExpressionDependencies = @($expressionFacts.Methods + $expressionFacts.Properties + $expressionFacts.Fields)
            RuleRestrictionDependencies = @($restrictionFacts.Methods + $restrictionFacts.Properties + $restrictionFacts.Fields)
            RuleContainsPSToStringBinder = [bool] (@($expressionFacts.Methods + $expressionFacts.Properties + $expressionFacts.Fields) -match 'PSToStringBinder').Count
            RuleContainsExecutionContext = [bool] (@($expressionFacts.Methods + $expressionFacts.Properties + $expressionFacts.Fields) -match 'ExecutionContext|GetExecutionContextFromTLS').Count
        }
    }

    function Get-UniqueBinderCount($Dynamics) {
        $seen = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
        foreach ($dynamic in $Dynamics) { $null = $seen.Add($dynamic.Expression.Binder) }
        return $seen.Count
    }

    $find = {
        param($TypeSuffix, $Property, $Value)
        @($Population.Dynamic | Where-Object { $_.BinderType.EndsWith($TypeSuffix) -and ((Get-PublicValue $_.Expression.Binder $Property) -eq $Value) })
    }
    $getDisplay = @(& $find 'PSGetMemberBinder' 'Name' 'DisplayValue')
    $setDisplay = @(& $find 'PSSetMemberBinder' 'Name' 'DisplayValue')
    $setReset = @(& $find 'PSSetMemberBinder' 'Name' 'ResetOnNext')
    $setRepeat = @(& $find 'PSSetMemberBinder' 'Name' 'HasLastRepeat')
    $equals = @(& $find 'PSBinaryOperationBinder' 'Operation' 'Equal')
    $boolConvert = @($Population.Dynamic | Where-Object { $_.BinderType.EndsWith('PSConvertBinder') -and ((Get-PublicValue $_.Expression.Binder 'Type') -eq [bool]) })
    foreach ($pair in @(@('DisplayValue GET', $getDisplay), @('DisplayValue SET', $setDisplay), @('ResetOnNext SET', $setReset), @('HasLastRepeat SET', $setRepeat), @('String Equal', $equals))) { if ($pair[1].Count -eq 0) { throw "No existing authentic binder found for $($pair[0])." } }
    $uniqueCounts = [ordered] @{ DisplayValueGet = (Get-UniqueBinderCount $getDisplay); DisplayValueSet = (Get-UniqueBinderCount $setDisplay); ResetOnNextSet = (Get-UniqueBinderCount $setReset); HasLastRepeatSet = (Get-UniqueBinderCount $setRepeat); Equal = (Get-UniqueBinderCount $equals); BoolConvert = (Get-UniqueBinderCount $boolConvert) }
    if (@($uniqueCounts.Values | Where-Object { $_ -gt 1 }).Count) { throw 'A Layer-3 binder family has more than one existing binder object; exact site-object selection is not established by the frozen structural layer.' }

    $stateMeta = & $newMeta $state; $labelMeta = & $newMeta '7'; $boolMeta = & $newMeta $false; $stringZeroMeta = & $newMeta '0'; $stringNumMeta = & $newMeta 'num'
    $records = [Collections.Generic.List[object]]::new()
    $records.Add((Project-Rule 'member_display_get' $getDisplay[0] $stateMeta @()))
    $records.Add((Project-Rule 'member_display_set' $setDisplay[0] $stateMeta @($labelMeta)))
    $records.Add((Project-Rule 'member_reset_set' $setReset[0] $stateMeta @($boolMeta)))
    $records.Add((Project-Rule 'member_haslast_set' $setRepeat[0] $stateMeta @($boolMeta)))
    $records.Add((Project-Rule 'type_eq_num' $equals[0] $stringNumMeta @(& $newMeta 'num')))
    $records.Add((Project-Rule 'display_eq_zero' $equals[0] $stringZeroMeta @(& $newMeta '0')))
    $records.Add((Project-Rule 'label_eq_dot' $equals[0] $labelMeta @(& $newMeta '.')))
    if ($boolConvert.Count) { $records.Add((Project-Rule 'bool_conversion_support' $boolConvert[0] $boolMeta @())) }
    [pscustomobject] [ordered] @{ Layer = 'AUTHENTIC_BINDER_RULE_PROJECTION'; HasEverUsedConstrainedLanguage = $hasEverUsedConstrainedLanguage; Records = @($records); ExistingBinderPopulation = [pscustomobject] @{ DisplayValueGet = $getDisplay.Count; DisplayValueSet = $setDisplay.Count; ResetOnNextSet = $setReset.Count; HasLastRepeatSet = $setRepeat.Count; Equal = $equals.Count; BoolConvert = $boolConvert.Count; UniqueBinderObjects = $uniqueCounts } }
}

# //////////////////////////////////////////////////////////////////////
# LAYER 4 — AUTHENTIC HOSTED RULE REACHABILITY
# //////////////////////////////////////////////////////////////////////
$GetButton7HostedRuleReachability = {
    param($Projection, $StructuralCandidates)

    $calculator = New-Module -AsCustomObject -ArgumentList $sourcePath {
        param($path)
        $env:DP_SKIP_START = '1'
        . $path
        $script:Layer4State = [CalculatorState]::new()
        function Get-Layer4State { $script:Layer4State }
        Export-ModuleMember -Function Invoke-CalculatorLogic, Get-Layer4State
    }
    $state = $calculator.'Get-Layer4State'()
    $invoke = $calculator.PSObject.Methods['Invoke-CalculatorLogic']

    # Compile the authentic function with an inert input before instrumentation.
    # This establishes the LightLambda instruction population without executing
    # the bounded Button-7 transition that the receipt measures.
    $invoke.Invoke($state, 'unused', 'unused')
    $state.DisplayValue = '0'; $state.ResetOnNext = $false; $state.HasLastRepeat = $false

    $flags = [Reflection.BindingFlags] 'Instance,Public,NonPublic'
    $scriptBlock = $invoke.Script
    $data = $scriptBlock.GetType().GetField('_scriptBlockData', $flags).GetValue($scriptBlock)
    $endBlock = $data.GetType().GetField('<EndBlock>k__BackingField', $flags).GetValue($data)
    $lightLambda = $endBlock.Target
    if ($lightLambda.GetType().FullName -ne 'System.Management.Automation.Interpreter.LightLambda') { throw "Unexpected authentic hosted execution form: $($lightLambda.GetType().FullName)" }
    $interpreter = $lightLambda.GetType().GetField('_interpreter', $flags).GetValue($lightLambda)
    $instructionArray = $interpreter.GetType().GetField('<Instructions>k__BackingField', $flags).GetValue($interpreter)
    $instructions = $instructionArray.GetType().GetField('Instructions', $flags).GetValue($instructionArray)

    $family = {
        param($binder)
        $name = Get-PublicValue $binder 'Name'
        $operation = [string] (Get-PublicValue $binder 'Operation')
        if ($binder.GetType().FullName.EndsWith('PSGetMemberBinder') -and $name -eq 'DisplayValue') { return 'DisplayValue GET' }
        if ($binder.GetType().FullName.EndsWith('PSSetMemberBinder') -and $name -eq 'DisplayValue') { return 'DisplayValue SET' }
        if ($binder.GetType().FullName.EndsWith('PSSetMemberBinder') -and $name -eq 'ResetOnNext') { return 'ResetOnNext SET' }
        if ($binder.GetType().FullName.EndsWith('PSSetMemberBinder') -and $name -eq 'HasLastRepeat') { return 'HasLastRepeat SET' }
        if ($binder.GetType().FullName.EndsWith('PSBinaryOperationBinder') -and $operation -eq 'Equal') { return 'String Equal candidate' }
        if ($binder.GetType().FullName.EndsWith('PSConvertBinder') -and ((Get-PublicValue $binder 'Type') -eq [bool])) { return 'Boolean conversion candidate' }
        return $null
    }

    $counts = [Collections.Concurrent.ConcurrentDictionary[string,int]]::new()
    $observedArguments = [Collections.Concurrent.ConcurrentQueue[object[]]]::new()
    $keyParameter = [System.Linq.Expressions.Expression]::Parameter([string], 'key')
    $valueParameter = [System.Linq.Expressions.Expression]::Parameter([int], 'value')
    $update = [System.Linq.Expressions.Expression]::Lambda([Func[string,int,int]], [System.Linq.Expressions.Expression]::Add($valueParameter, [System.Linq.Expressions.Expression]::Constant(1)), [System.Linq.Expressions.ParameterExpression[]] @($keyParameter, $valueParameter)).Compile()
    $addOrUpdate = $counts.GetType().GetMethods() | Where-Object { ($_.Name -eq 'AddOrUpdate') -and ($_.GetParameters().Count -eq 3) -and ($_.GetParameters()[1].ParameterType -eq [int]) } | Select-Object -First 1

    $sites = [Collections.Generic.List[object]]::new()
    $seenSites = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    for ($instructionIndex = 0; $instructionIndex -lt $instructions.Length; $instructionIndex++) {
        $instruction = $instructions[$instructionIndex]
        $siteField = $instruction.GetType().GetField('_site', $flags)
        if ($null -eq $siteField) { continue }
        $site = $siteField.GetValue($instruction)
        if (($null -eq $site) -or (-not $seenSites.Add($site))) { continue }
        $binder = $site.Binder; $ruleFamily = & $family $binder
        if ($null -eq $ruleFamily) { $ruleFamily = 'UNCHARACTERIZED' }
        $targetField = $site.GetType().GetField('Target', $flags)
        $originalTarget = $targetField.GetValue($site)
        $delegateType = $targetField.FieldType
        $invokeMethod = $delegateType.GetMethod('Invoke')
        $parameters = [Collections.Generic.List[System.Linq.Expressions.ParameterExpression]]::new()
        foreach ($parameter in $invokeMethod.GetParameters()) { $parameters.Add([System.Linq.Expressions.Expression]::Parameter($parameter.ParameterType, $parameter.Name)) }
        $key = "instruction=$instructionIndex;callsite=$([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($site));binder=$([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($binder))"
        $countCall = [System.Linq.Expressions.Expression]::Call([System.Linq.Expressions.Expression]::Constant($counts), $addOrUpdate, [System.Linq.Expressions.Expression]::Constant($key), [System.Linq.Expressions.Expression]::Constant(1), [System.Linq.Expressions.Expression]::Constant($update))
        $parameterArray = [System.Linq.Expressions.ParameterExpression[]] $parameters.ToArray()
        $observationValues = [Collections.Generic.List[System.Linq.Expressions.Expression]]::new()
        $observationValues.Add([System.Linq.Expressions.Expression]::Constant($key))
        foreach ($parameter in $parameters) { $observationValues.Add([System.Linq.Expressions.Expression]::Convert($parameter, [object])) }
        $observationArray = [System.Linq.Expressions.Expression]::NewArrayInit([object], $observationValues)
        $enqueue = [System.Linq.Expressions.Expression]::Call([System.Linq.Expressions.Expression]::Constant($observedArguments), $observedArguments.GetType().GetMethod('Enqueue'), $observationArray)
        $originalCall = [System.Linq.Expressions.Expression]::Invoke([System.Linq.Expressions.Expression]::Constant($originalTarget, $delegateType), $parameterArray)
        $body = [System.Linq.Expressions.Expression]::Block($countCall, $enqueue, $originalCall)
        $wrapper = [System.Linq.Expressions.Expression]::Lambda($delegateType, $body, $parameterArray).Compile()
        $targetField.SetValue($site, $wrapper)
        $sites.Add([pscustomobject] @{ InstructionIndex = $instructionIndex; Key = $key; CallSite = $site; Binder = $binder; RuleFamily = $ruleFamily; OriginalTarget = $originalTarget; TargetField = $targetField })
    }
    if ($sites.Count -eq 0) { throw 'No authentic hosted DynamicInstruction CallSites were found in the LightLambda.' }

    $before = [ordered] @{ DisplayValue = $state.DisplayValue; ResetOnNext = $state.ResetOnNext; HasLastRepeat = $state.HasLastRepeat }
    $invoke.Invoke($state, '7', 'num')
    $after = [ordered] @{ DisplayValue = $state.DisplayValue; ResetOnNext = $state.ResetOnNext; HasLastRepeat = $state.HasLastRepeat }
    if (($after.DisplayValue -ne '7') -or $after.ResetOnNext -or $after.HasLastRepeat) { throw 'Instrumented authentic hosted Button-7 invocation changed expected Calculator behavior.' }

    $records = [Collections.Generic.List[object]]::new()
    foreach ($siteInfo in $sites) {
        $count = 0; $null = $counts.TryGetValue($siteInfo.Key, [ref] $count)
        $site = $siteInfo.CallSite; $target = $siteInfo.TargetField.GetValue($site)
        $rulesField = $site.GetType().GetField('Rules', $flags); $rules = if ($rulesField) { @($rulesField.GetValue($site)) } else { @() }
        $records.Add([pscustomobject] [ordered] @{
            StableSiteIdentity = "LightLambda.DynamicInstruction#$($siteInfo.InstructionIndex);CallSite#$([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($site))"
            ObservationKey = $siteInfo.Key
            DynamicExpressionIdentity = 'NOT_EXPOSED_BY_LIGHTLAMBDA_RUNTIME'
            CallSiteIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($site)
            BinderObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($siteInfo.Binder)
            BinderType = $siteInfo.Binder.GetType().FullName
            BinderName = Get-PublicValue $siteInfo.Binder 'Name'
            BinderOperation = [string] (Get-PublicValue $siteInfo.Binder 'Operation')
            SpecializedRuleFamily = $siteInfo.RuleFamily
            RuleExists = if ($siteInfo.RuleFamily -eq 'UNCHARACTERIZED') { 'NOT_CHARACTERIZED_BY_LAYER3' } else { 'CHARACTERIZED_BY_LAYER3' }
            RuleSpecialized = if ($siteInfo.RuleFamily -eq 'UNCHARACTERIZED') { 'NOT_CHARACTERIZED_BY_LAYER3' } else { 'CHARACTERIZED_BY_LAYER3_FOR_ADMITTED_VALUES' }
            OriginalTargetIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($siteInfo.OriginalTarget)
            OriginalTargetMethod = "$(if ($siteInfo.OriginalTarget.Method.DeclaringType) { $siteInfo.OriginalTarget.Method.DeclaringType.FullName } else { '<DynamicMethod>' })::$($siteInfo.OriginalTarget.Method.Name)"
            ActualTargetIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($target)
            ActualTargetMethod = "$(if ($target.Method.DeclaringType) { $target.Method.DeclaringType.FullName } else { '<DynamicMethod>' })::$($target.Method.Name)"
            CachedRuleDelegateIdentities = @($rules | Where-Object { $null -ne $_ } | ForEach-Object { [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($_) })
            RuleRestrictions = 'NOT_EXPOSED: CallSite caches compiled delegates, not the original DynamicMetaObject rule/restriction expression.'
            ExecutionCountDuringButton7 = $count
            RuleSelectedOrExecutedDuringButton7 = ($count -gt 0)
            SourceExtentDiagnostic = @($StructuralCandidates | Where-Object {
                ($siteInfo.RuleFamily -eq 'DisplayValue GET' -and $_.Name -eq 'member_display_get') -or
                ($siteInfo.RuleFamily -eq 'DisplayValue SET' -and $_.Name -eq 'member_display_set') -or
                ($siteInfo.RuleFamily -eq 'ResetOnNext SET' -and $_.Name -eq 'member_reset_set') -or
                ($siteInfo.RuleFamily -eq 'HasLastRepeat SET' -and $_.Name -eq 'member_haslast_set') -or
                ($siteInfo.RuleFamily -eq 'String Equal candidate' -and $_.Name -in @('type_eq_num', 'display_eq_zero', 'label_eq_dot'))
            } | ForEach-Object { "$($_.Name):$($_.Start)-$($_.End)" })
        })
    }
    $reached = @($records | Where-Object RuleSelectedOrExecutedDuringButton7)
    $notReached = @($records | Where-Object { -not $_.RuleSelectedOrExecutedDuringButton7 })
    $reachedOutsideCharacterized = @($reached | Where-Object { $_.SpecializedRuleFamily -eq 'UNCHARACTERIZED' })
    $expectedFamilies = @('DisplayValue GET', 'DisplayValue SET', 'ResetOnNext SET', 'HasLastRepeat SET', 'String Equal candidate', 'Boolean conversion candidate')
    $missingExpectedFamilies = @($expectedFamilies | Where-Object { $_ -notin @($reached.SpecializedRuleFamily) })
    [pscustomobject] [ordered] @{ Layer = 'AUTHENTIC_HOSTED_RULE_REACHABILITY'; Instrumentation = 'Temporarily replaces every authentic LightLambda DynamicInstruction CallSite.Target with an expression-compiled counter wrapper that records its actual delegate arguments and invokes the original delegate. The wrapper may be displaced by normal DLR update behavior; a positive count is direct invocation evidence.'; Button7HostedBehavior = [pscustomobject] @{ Before = $before; After = $after }; ReachableExecutableSites = @($reached); CandidateSpecializedRulesNotReached = @($notReached | Where-Object { $_.SpecializedRuleFamily -ne 'UNCHARACTERIZED' }); ReachedOutsideCharacterizedRuleFamilies = @($reachedOutsideCharacterized); ExpectedRuleFamilies = $expectedFamilies; MissingExpectedRuleFamilies = $missingExpectedFamilies; ReachabilityAuditPass = (($reached.Count -gt 0) -and ($reachedOutsideCharacterized.Count -eq 0) -and ($missingExpectedFamilies.Count -eq 0)); InternalRuntimeContext = [pscustomobject] @{ InvocationSnapshots = [object[]] $observedArguments.ToArray() } }
}

# //////////////////////////////////////////////////////////////////////
# LAYER 5 — SEMANTIC OBJECT PROJECTION
# //////////////////////////////////////////////////////////////////////
$GetButton7SemanticObjectProjection = {
    param($RuntimeReachability)

    $flags = [Reflection.BindingFlags] 'Instance,Public,NonPublic'
    $assembly = [PSObject].Assembly
    $snapshotsByKey = @{}
    foreach ($snapshot in $RuntimeReachability.InternalRuntimeContext.InvocationSnapshots) {
        if ($snapshot.Length -gt 0) { $snapshotsByKey[[string] $snapshot[0]] = $snapshot }
    }
    $getMemberMethod = $assembly.GetType('System.Management.Automation.Language.PSGetMemberBinder', $true).GetMethods($flags) | Where-Object { $_.Name -eq 'GetPSMemberInfo' } | Select-Object -First 1
    $figureConversion = $assembly.GetType('System.Management.Automation.LanguagePrimitives', $true).GetMethods([Reflection.BindingFlags] 'Static,NonPublic') | Where-Object { ($_.Name -eq 'FigureConversion') -and ($_.GetParameters().Count -eq 3) } | Select-Object -First 1
    $stringEquals = $assembly.GetType('System.Management.Automation.Language.CachedReflectionInfo', $true).GetField('StringOps_Equals', [Reflection.BindingFlags] 'Static,Public,NonPublic').GetValue($null)
    $records = [Collections.Generic.List[object]]::new()

    foreach ($site in $RuntimeReachability.ReachableExecutableSites) {
        $snapshot = $snapshotsByKey[$site.ObservationKey]
        if ($null -eq $snapshot) { throw "No runtime operand snapshot was retained for reached site $($site.StableSiteIdentity)." }
        $operands = @($snapshot | Select-Object -Skip 2)
        $record = [ordered] @{ StableSiteIdentity = $site.StableSiteIdentity; BinderObjectIdentity = $site.BinderObjectIdentity; BinderType = $site.BinderType; SpecializedRuleFamily = $site.SpecializedRuleFamily; RuleSelectedOrExecutedDuringButton7 = $site.RuleSelectedOrExecutedDuringButton7; ProjectionStatus = 'UNRESOLVED'; OperandRuntimeTypes = @($operands | ForEach-Object { if ($null -eq $_) { '<null>' } else { $_.GetType().FullName } }) }

        if ($site.SpecializedRuleFamily -in @('DisplayValue GET', 'DisplayValue SET', 'ResetOnNext SET', 'HasLastRepeat SET')) {
            $target = $operands[0]
            # The public ETS collection is useful for presentation, but exact
            # site resolution comes from this CallSite's authentic binder.
            $callSite = $snapshot[1]
            $binder = $callSite.Binder
            if ($binder.GetType().FullName.EndsWith('PSSetMemberBinder')) { $binder = Get-InstanceMemberValue $binder '_getMemberBinder' }
            $targetExpression = [System.Linq.Expressions.Expression]::Constant($target, $target.GetType())
            $metaObject = [System.Dynamic.DynamicMetaObject]::new($targetExpression, [System.Dynamic.BindingRestrictions]::Empty, $target)
            $arguments = @($metaObject, $null, $false, $null, [Reflection.MemberTypes]::Property, $null, $null)
            $member = $getMemberMethod.Invoke($binder, $arguments)
            if ($null -eq $member) { throw "Authentic GetPSMemberInfo did not resolve $($site.BinderName) for $($target.GetType().FullName)." }
            $adapter = Get-InstanceMemberValue $member 'adapter'
            $adapterData = Get-InstanceMemberValue $member 'adapterData'
            $clrMember = Get-InstanceMemberValue $adapterData 'member'
            if ($null -eq $clrMember) { $clrMember = Get-InstanceMemberValue $adapterData 'Member' }
            if ($null -eq $clrMember) { throw "PSMemberInfo $($member.GetType().FullName) did not expose a CLR member object." }
            $record.ProjectionStatus = 'PROJECTED_SEMANTIC_MEMBER_OBJECT'
            $record.TargetObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($target)
            $record.TargetRuntimeType = $target.GetType().FullName
            $record.MemberResolutionSeam = 'AUTHENTIC_PSGETMEMBERBINDER_GETPSMEMBERINFO'
            $record.MemberName = $member.Name
            $record.PSMemberInfoObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($member)
            $record.PSMemberInfoType = $member.GetType().FullName
            $record.AdapterObjectIdentity = if ($adapter) { [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($adapter) } else { $null }
            $record.AdapterType = if ($adapter) { $adapter.GetType().FullName } else { $null }
            $record.AdapterDataObjectIdentity = if ($adapterData) { [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($adapterData) } else { $null }
            $record.AdapterDataType = if ($adapterData) { $adapterData.GetType().FullName } else { $null }
            $record.CLRMemberObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($clrMember)
            $record.CLRMemberType = $clrMember.GetType().FullName
            $record.DeclaringType = $clrMember.DeclaringType.FullName
            $record.PropertyOrFieldType = if ($clrMember -is [Reflection.PropertyInfo]) { $clrMember.PropertyType.FullName } else { $clrMember.FieldType.FullName }
            $record.Getter = if ($clrMember -is [Reflection.PropertyInfo] -and $clrMember.GetMethod) { "$($clrMember.GetMethod.DeclaringType.FullName)::$($clrMember.GetMethod.Name)" } else { $null }
            $record.Setter = if ($clrMember -is [Reflection.PropertyInfo] -and $clrMember.SetMethod) { "$($clrMember.SetMethod.DeclaringType.FullName)::$($clrMember.SetMethod.Name)" } else { $null }
            $record.BindingProvenance = [pscustomobject] @{ BinderVersion = Get-InstanceMemberValue $binder '_version'; HasTypeTableMember = Get-InstanceMemberValue $binder '_hasTypeTableMember'; HasInstanceMember = Get-InstanceMemberValue $binder '_hasInstanceMember'; Static = Get-InstanceMemberValue $binder '_static' }
        }
        elseif ($site.SpecializedRuleFamily -eq 'Boolean conversion candidate') {
            $source = $operands[0]
            $conversionArgs = @($source, [bool], $false)
            $conversion = $figureConversion.Invoke($null, $conversionArgs)
            $converter = Get-InstanceMemberValue $conversion 'Converter'
            $record.ProjectionStatus = 'PROJECTED_SEMANTIC_CONVERSION_OBJECT'
            $record.SourceRuntimeType = if ($null -eq $source) { '<null>' } else { $source.GetType().FullName }
            $record.TargetType = [bool].FullName
            $record.ConversionObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($conversion)
            $record.ConversionType = $conversion.GetType().FullName
            $record.ConversionRank = [string] (Get-InstanceMemberValue $conversion 'Rank')
            $record.Debase = [bool] $conversionArgs[2]
            $record.ConverterObjectIdentity = if ($converter) { [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($converter) } else { $null }
            $record.ConverterType = if ($converter) { $converter.GetType().FullName } else { $null }
            $record.ConverterMethod = if ($converter) { "$($converter.Method.DeclaringType.FullName)::$($converter.Method.Name)" } else { $null }
        }
        elseif ($site.SpecializedRuleFamily -eq 'String Equal candidate') {
            $record.ProjectionStatus = 'PROJECTED_SEMANTIC_CALLABLE_OBJECT'
            $record.LeftObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($operands[0])
            $record.RightObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($operands[1])
            $record.CallableObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($stringEquals)
            $record.CallableType = $stringEquals.GetType().FullName
            $record.Callable = "$($stringEquals.DeclaringType.FullName)::$($stringEquals.Name)"
            $record.CultureObjectIdentity = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode([Globalization.CultureInfo]::InvariantCulture)
            $record.CultureType = [Globalization.CultureInfo]::InvariantCulture.GetType().FullName
            $record.Culture = if ([Globalization.CultureInfo]::InvariantCulture.Name) { [Globalization.CultureInfo]::InvariantCulture.Name } else { 'InvariantCulture' }
            $record.CompareOptions = [string] [Globalization.CompareOptions]::IgnoreCase
        }
        $records.Add([pscustomobject] $record)
    }

    $unresolved = @($records | Where-Object ProjectionStatus -eq 'UNRESOLVED')
    $conversionIdentities = @($records | Where-Object { $_.SpecializedRuleFamily -eq 'Boolean conversion candidate' } | Select-Object -ExpandProperty ConversionObjectIdentity -Unique)
    [pscustomobject] [ordered] @{ Layer = 'SEMANTIC_OBJECT_PROJECTION'; SourceEvidence = @('PowerShell:Binders.cs:PSGetMemberBinder.GetPSMemberInfo', 'PowerShell:LanguagePrimitives.cs:FigureConversion', 'PowerShell:Compiler.cs:CallStringEquals'); Records = @($records); UnresolvedObjectSites = @($unresolved); BooleanConversionCacheObjectIdentities = $conversionIdentities; HistoricalDynamicMetaObjectRule = if ($unresolved.Count -eq 0) { 'NOT_REQUIRED_FOR_SELECTED_OBJECT_LEVEL_CLOSURE' } else { 'NOT_ASSESSED_DUE_TO_UNRESOLVED_OBJECT_SITES' }; ProjectionPass = ($unresolved.Count -eq 0) }
}

# //////////////////////////////////////////////////////////////////////
# LAYER 0 — AUTHENTIC SMA FIXTURE
# //////////////////////////////////////////////////////////////////////
$source = [IO.File]::ReadAllText($sourcePath); $compiled = Compile-AuthenticLambda $source; $population = Get-CompiledSemanticPopulation $compiled.Lambda

# //////////////////////////////////////////////////////////////////////
# LAYER 1 — BUTTON-7 STRUCTURAL CANDIDATES
# //////////////////////////////////////////////////////////////////////
$candidates = Get-Button7AstCandidateSlice $compiled.Ast $compiled.Tokens; $resolved = [Collections.Generic.List[object]]::new()
foreach ($candidate in $candidates) {
    $mutantText = $null; $mutantKind = ''; $originalName = $null
    if ($candidate.Kind -eq 'member') { $replacement = '__SMADirectProbe_' + $candidate.Id; $mutantKind = 'member'; $originalName = $candidate.Ast.Member.Extent.Text; $mutantText = Replace-Extent $source $candidate.Ast.Member.Extent $replacement }
    elseif ($candidate.Name -in @('type_eq_num', 'display_eq_zero', 'label_eq_dot')) { $token = Find-OperatorToken $compiled.Tokens $candidate.Ast; if ($token) { $mutantKind = 'binary'; $mutantText = Replace-Extent $source $token.Extent '-ne' } }
    if ($null -eq $mutantText) { $resolved.Add([pscustomobject] @{ Id = $candidate.Id; Name = $candidate.Name; Kind = $candidate.Kind; Start = $candidate.Ast.Extent.StartOffset; End = $candidate.Ast.Extent.EndOffset; Resolution = 'NO_DYNAMIC_BINDER_ASSUMED'; Detail = 'Inspect authentic Lambda node structure; short-circuit control is not assumed to be a DLR binary binder.' }); continue }
    $mutantPopulation = Get-CompiledSemanticPopulation (Compile-AuthenticLambda $mutantText).Lambda
    if ($mutantKind -eq 'member') {
        $changed = @($mutantPopulation.Dynamic | Where-Object { $_.Name -eq $replacement })
        $same = @($population.Dynamic | Where-Object { $_.Name -eq $originalName })
        $delta = $changed.Count
        $deltaDetail = "new-member fingerprint count=$delta"
    } else {
        # A Calculator lambda may already contain NotEqual binders. The exact
        # token mutation is identified by the population delta, never by raw
        # ordinal or a global NotEqual count.
        $changed = @($mutantPopulation.Dynamic | Where-Object { $_.Operation -eq 'NotEqual' })
        $prior = @($population.Dynamic | Where-Object { $_.Operation -eq 'NotEqual' })
        $same = @($population.Dynamic | Where-Object { $_.Operation -eq 'Equal' })
        $delta = $changed.Count - $prior.Count
        $deltaDetail = "NotEqual population delta=$delta (original=$($prior.Count), mutant=$($changed.Count))"
    }
    $resolution = if ($delta -eq 1) { if ($same.Count -eq 1) { 'UNIQUE_STRUCTURAL_MATCH' } else { 'DIFFERENTIAL_IDENTIFIED_ORIGINAL_FINGERPRINT_AMBIGUOUS' } } else { 'DIFFERENTIAL_AMBIGUOUS' }
    $detail = if ($delta -eq 1) { "${deltaDetail}; original equivalent candidates=$($same.Count)" } else { "${deltaDetail}; original equivalent candidates=$($same.Count)" }
    $resolved.Add([pscustomobject] @{ Id = $candidate.Id; Name = $candidate.Name; Kind = $candidate.Kind; Start = $candidate.Ast.Extent.StartOffset; End = $candidate.Ast.Extent.EndOffset; Resolution = $resolution; Detail = $detail })
}

$expectedNames = @('type_eq_num', 'display_eq_zero', 'label_eq_dot', 'display_or_reset', 'member_display_get', 'member_display_set', 'member_reset_set', 'member_haslast_set')
if ((@($resolved.Name | Sort-Object) -join '|') -ne (@($expectedNames | Sort-Object) -join '|')) { throw 'Button-7 AST structural candidate set changed.' }
if ((@($population.NodeTypes | Where-Object { $_.NodeType -eq 'OrElse' } | Select-Object -First 1).Count) -ne 1) { throw 'Expected authentic Lambda OrElse control form was not observed.' }
if (@($resolved | Where-Object { ($_.Kind -ne 'control') -and ($_.Resolution -eq 'DIFFERENTIAL_AMBIGUOUS') }).Count) { throw 'An exact Button-7 AST mutation did not produce one differential semantic fingerprint.' }
if ($ThroughLayer -eq 'Structural') {
    $receipt = [pscustomobject] [ordered] @{ test = 'Button 7 structural candidate scout'; pass = $true; sourceSha256 = (Get-FileHash $sourcePath -Algorithm SHA256).Hash; astCandidates = $resolved; compiledDynamicPopulation = $population.Dynamic.Count; compiledNodeTypes = $population.NodeTypes; proven = 'Exact AST/token differentials correlate structural candidates with authentic Lambda object structure only.'; notProven = 'Not an execution trace, dynamic-ordinal order, detached closure, DLR binder closure, or Calculator native behavior.'; verdict = 'PASS_STRUCTURAL_LAYER' }
    Complete-LayeredReceipt $receipt
    return
}
# //////////////////////////////////////////////////////////////////////
# LAYER 2 — SOURCE-CONTRACT VARIABLE PLACEMENT
# //////////////////////////////////////////////////////////////////////
$variablePlacement = & $GetButton7VariablePlacement $compiled $candidates
if ($variablePlacement.AstFieldMapConsistency -ne 'ESTABLISHED') {
    $receipt = [pscustomobject] [ordered] @{
        test = 'Button 7 source-contract variable placement'
        pass = $false
        structuralCandidateReceipt = '6e89770'
        sourcePredictedTupleIndices = [ordered] @{ state = 9; label = 10; type = 11 }
        observedTupleIndices = [ordered] @{ state = @($variablePlacement.Variables | Where-Object VariablePath -eq 'state')[0].ObservedTupleIndex; label = @($variablePlacement.Variables | Where-Object VariablePath -eq 'label')[0].ObservedTupleIndex; type = @($variablePlacement.Variables | Where-Object VariablePath -eq 'type')[0].ObservedTupleIndex }
        compilerNameToIndexMap = $variablePlacement.CompilerNameToIndexMap
        variablePlacement = $variablePlacement
        astProvenance = 'ESTABLISHED'
        sourceIndexPrediction = if ($variablePlacement.SourcePredictionPass) { 'MATCHED' } else { 'FALSIFIED' }
        astFieldMapConsistency = $variablePlacement.AstFieldMapConsistency
        failureReason = 'The source-derived 9/10/11 prediction does not match the canonical NameToIndexMap; the map and observed body AST fields are reported separately.'
        runtimeExecutionReachability = 'NOT_PROVEN'
        dlrBinderClosure = 'NOT_PROVEN'
        detachedExecution = 'NOT_ATTEMPTED'
        nativeLowering = 'NOT_ATTEMPTED'
        verdict = 'FAIL_SOURCE_INDEX_PREDICTION'
    }
    Complete-LayeredReceipt $receipt
    return
}

if ($ThroughLayer -eq 'VariablePlacement') {
    $receipt = [pscustomobject] [ordered] @{ test = 'Button 7 variable-placement layer'; pass = $true; structuralCandidateReceipt = '6e89770'; variablePlacement = $variablePlacement; sourceIndexPrediction = if ($variablePlacement.SourcePredictionPass) { 'MATCHED' } else { 'FALSIFIED' }; verdict = 'PASS_VARIABLE_PLACEMENT_LAYER' }
    Complete-LayeredReceipt $receipt
    return
}

# //////////////////////////////////////////////////////////////////////
# LAYER 3 — AUTHENTIC BINDER RULE PROJECTION
# //////////////////////////////////////////////////////////////////////
$binderProjection = & $GetButton7BinderRuleProjection $compiled $population
if ($ThroughLayer -eq 'BinderRuleProjection') {
    $receipt = [pscustomobject] [ordered] @{ test = 'Button 7 authentic binder rule projection'; pass = $true; structuralCandidateReceipt = '6e89770'; variablePlacementReceipt = '83d992c'; variablePlacement = $variablePlacement; binderRuleProjection = $binderProjection; runtimeExecutionReachability = 'NOT_PROVEN'; detachedExecution = 'NOT_ATTEMPTED'; nativeLowering = 'NOT_ATTEMPTED'; nativeCalculatorBehavior = 'NOT_PROVEN'; verdict = 'PASS_BINDER_RULE_PROJECTION_LAYER' }
    Complete-LayeredReceipt $receipt
    return
}

# //////////////////////////////////////////////////////////////////////
# LAYER 4 — AUTHENTIC HOSTED RULE REACHABILITY
# //////////////////////////////////////////////////////////////////////
$runtimeReachability = & $GetButton7HostedRuleReachability $binderProjection $resolved
if ($ThroughLayer -eq 'RuntimeReachability') {
    $runtimeReachability.PSObject.Properties.Remove('InternalRuntimeContext')
    $receipt = [pscustomobject] [ordered] @{ test = 'Button 7 authentic hosted rule reachability'; pass = $runtimeReachability.ReachabilityAuditPass; structuralCandidateReceipt = '6e89770'; variablePlacementReceipt = '83d992c'; binderRuleProjectionReceipt = '91f23b3'; variablePlacement = $variablePlacement; binderRuleProjection = $binderProjection; runtimeReachability = $runtimeReachability; detachedExecution = 'NOT_ATTEMPTED'; nativeLowering = 'NOT_ATTEMPTED'; nativeCalculatorBehavior = 'NOT_PROVEN'; verdict = if ($runtimeReachability.ReachabilityAuditPass) { 'PASS_AUTHENTIC_HOSTED_RULE_REACHABILITY' } else { 'FAIL_NO_REACHED_RULES' } }
    Complete-LayeredReceipt $receipt
    return
}

# //////////////////////////////////////////////////////////////////////
# LAYER 5 — SEMANTIC OBJECT PROJECTION
# //////////////////////////////////////////////////////////////////////
$semanticObjectProjection = & $GetButton7SemanticObjectProjection $runtimeReachability
$runtimeReachability.PSObject.Properties.Remove('InternalRuntimeContext')
if ($ThroughLayer -eq 'SemanticObjectProjection') {
    $receipt = [pscustomobject] [ordered] @{ test = 'Button 7 semantic object projection'; pass = $semanticObjectProjection.ProjectionPass; structuralCandidateReceipt = '6e89770'; variablePlacementReceipt = '83d992c'; binderRuleProjectionReceipt = '91f23b3'; runtimeReachabilityReceipt = '49f5b88'; runtimeReachability = $runtimeReachability; semanticObjectProjection = $semanticObjectProjection; detachedExecution = 'NOT_ATTEMPTED'; nativeLowering = 'NOT_ATTEMPTED'; nativeCalculatorBehavior = 'NOT_PROVEN'; verdict = if ($semanticObjectProjection.ProjectionPass) { 'PASS_SEMANTIC_OBJECT_PROJECTION' } else { 'FAIL_UNRESOLVED_SEMANTIC_OBJECT_SITE' } }
    Complete-LayeredReceipt $receipt
    return
}

# Capsule is structural evidence only: no ordinal, execution, or behavior claim.
$stream = [IO.MemoryStream]::new(); $writer = [IO.BinaryWriter]::new($stream)
$writer.Write([uint32] 0x43533742); $writer.Write([uint32] 2); $writer.Write([Convert]::FromHexString((Get-FileHash $sourcePath -Algorithm SHA256).Hash)); $writer.Write([uint32] $resolved.Count); $writer.Write([uint32] $population.Dynamic.Count)
$kinds = @('binary', 'member', 'control'); $resolutions = @('UNIQUE_STRUCTURAL_MATCH', 'DIFFERENTIAL_IDENTIFIED_ORIGINAL_FINGERPRINT_AMBIGUOUS', 'DIFFERENTIAL_AMBIGUOUS', 'NO_DYNAMIC_BINDER_ASSUMED')
foreach ($record in $resolved) { $name = [Text.Encoding]::UTF8.GetBytes($record.Name); $detail = [Text.Encoding]::UTF8.GetBytes($record.Detail); $writer.Write([uint32] $record.Id); $writer.Write([uint32] $record.Start); $writer.Write([uint32] $record.End); $writer.Write([byte] ([array]::IndexOf($kinds, $record.Kind))); $writer.Write([byte] ([array]::IndexOf($resolutions, $record.Resolution))); $writer.Write([uint16] $name.Length); $writer.Write($name); $writer.Write([uint16] $detail.Length); $writer.Write($detail) }
$writer.Flush(); [IO.File]::WriteAllBytes($OutputPath, $stream.ToArray())

$nativeSource = Join-Path $root 'Apps\ObjectReplica\Button7ClosureScoutReceipt.cpp'; $nativeExe = Join-Path $root 'Apps\ObjectReplica\Button7ClosureScoutReceipt.exe'; $vcvars = 'C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat'
$build = "call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /Fe:`"$nativeExe`" `"$nativeSource`""; cmd.exe /c $build | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Native structural capsule consumer build failed.' }
$native = & $nativeExe $OutputPath 2>&1
if (($LASTEXITCODE -ne 0) -or ($native -notmatch 'verdict=PASS')) { throw "Native capsule receipt failed: $native" }
$receipt = [pscustomobject] [ordered] @{ test = 'Button 7 canonical layered scout'; pass = $semanticObjectProjection.ProjectionPass; sourceSha256 = (Get-FileHash $sourcePath -Algorithm SHA256).Hash; astCandidates = $resolved; compiledDynamicPopulation = $population.Dynamic.Count; compiledNodeTypes = $population.NodeTypes; variablePlacement = $variablePlacement; binderRuleProjection = $binderProjection; runtimeReachability = $runtimeReachability; semanticObjectProjection = $semanticObjectProjection; native = ($native -join "`n"); proven = 'Exact AST/token differentials identify bounded structural candidates; authentic binders project direct CLR-property and StringOps rules; existing hosted LightLambda CallSites were mechanically observed during Button 7; reached sites project to member, conversion, and callable semantic objects.'; notProven = 'Not detached closure, native lowering, or Calculator native behavior.'; verdict = if ($semanticObjectProjection.ProjectionPass) { 'PASS' } else { 'FAIL_UNRESOLVED_SEMANTIC_OBJECT_SITE' } }
Complete-LayeredReceipt $receipt
