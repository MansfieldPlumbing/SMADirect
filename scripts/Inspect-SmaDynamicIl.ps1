[CmdletBinding()]
param(
    [string]$Path = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Conformance\Calculator.ps1'),
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Artifacts\Calculator.sma-il-dependencies.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InstanceNonPublic = [Reflection.BindingFlags]'Instance,NonPublic'
$StaticNonPublic = [Reflection.BindingFlags]'Static,NonPublic'

function Get-PrivateFieldValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $field = $Object.GetType().GetField($Name, $InstanceNonPublic)
    if ($null -eq $field) { return $null }
    $field.GetValue($Object)
}

function Get-AuthenticLambda($Ast, [Management.Automation.Language.FunctionDefinitionAst]$Function) {
    $provider = [ScriptBlock].Assembly.GetType('System.Management.Automation.Language.IParameterMetadataProvider', $true)
    $ctor = [ScriptBlock].GetConstructor($InstanceNonPublic, $null, [type[]]@($provider, [bool]), $null)
    $source = [ScriptBlock]$ctor.Invoke([object[]]@($Ast, $false))
    $compileSource = [ScriptBlock].GetMethod('Compile', $InstanceNonPublic, $null, [type[]]@([bool]), $null)
    $null = $compileSource.Invoke($source, @($true))
    $block = [ScriptBlock]$ctor.Invoke([object[]]@($Function, $false))
    $data = Get-PrivateFieldValue $block '_scriptBlockData'
    $compilerType = [PSObject].Assembly.GetType('System.Management.Automation.Language.Compiler', $true)
    $compiler = [Activator]::CreateInstance($compilerType, $true)
    $compile = $compilerType.GetMethods($InstanceNonPublic) | Where-Object { $_.Name -eq 'Compile' -and $_.GetParameters().Count -eq 2 } | Select-Object -First 1
    $null = $compile.Invoke($compiler, @($data, $true))
    [Linq.Expressions.LambdaExpression]$compilerType.GetField('_endBlockLambda', $InstanceNonPublic).GetValue($compiler)
}

function Get-OpCodeMap {
    $map = @{}
    foreach ($field in [Reflection.Emit.OpCodes].GetFields([Reflection.BindingFlags]'Public,Static')) {
        if ($field.FieldType -eq [Reflection.Emit.OpCode]) {
            $op = [Reflection.Emit.OpCode]$field.GetValue($null)
            $map[[uint16](([int]$op.Value) -band 0xFFFF)] = $op
        }
    }
    $map
}

function Get-OperandSize([Reflection.Emit.OperandType]$OperandType, [byte[]]$Code, [int]$Position) {
    switch ($OperandType) {
        'InlineNone' { return 0 }
        'ShortInlineBrTarget' { return 1 }
        'ShortInlineI' { return 1 }
        'ShortInlineVar' { return 1 }
        'InlineVar' { return 2 }
        'InlineI' { return 4 }
        'InlineBrTarget' { return 4 }
        'InlineField' { return 4 }
        'InlineMethod' { return 4 }
        'InlineSig' { return 4 }
        'InlineString' { return 4 }
        'InlineTok' { return 4 }
        'InlineType' { return 4 }
        'ShortInlineR' { return 4 }
        'InlineI8' { return 8 }
        'InlineR' { return 8 }
        'InlineSwitch' { return 4 + (4 * [BitConverter]::ToInt32($Code, $Position)) }
        default { throw "Unhandled operand type: $OperandType" }
    }
}

function Get-ScopeValueDescription($Value) {
    $result = [ordered]@{ ValueKind = $null; ResolvedMember = $null; DeclaringType = $null; DeclaringAssembly = $null; ValueText = $null }
    if ($null -eq $Value) { $result.ValueKind = 'null'; return $result }
    $result.ValueKind = $Value.GetType().FullName
    try {
        # DynamicScope stores generic members as the same internal wrappers used by
        # DynamicResolver; recover their runtime handle instead of calling them opaque.
        if ($Value.GetType().FullName -eq 'System.Reflection.Emit.GenericMethodInfo') {
            $methodHandle = Get-PrivateFieldValue $Value 'm_methodHandle'
            $context = Get-PrivateFieldValue $Value 'm_context'
            $m = [Reflection.MethodBase]::GetMethodFromHandle($methodHandle, $context)
            $result.ValueKind = 'GenericMethodInfo'; $result.ResolvedMember = $m.ToString(); $result.DeclaringType = $m.DeclaringType.FullName; $result.DeclaringAssembly = $m.DeclaringType.Assembly.GetName().Name
        } elseif ($Value.GetType().FullName -eq 'System.Reflection.Emit.GenericFieldInfo') {
            $fieldHandle = Get-PrivateFieldValue $Value 'm_fieldHandle'
            $context = Get-PrivateFieldValue $Value 'm_context'
            $f = [Reflection.FieldInfo]::GetFieldFromHandle($fieldHandle, $context)
            $result.ValueKind = 'GenericFieldInfo'; $result.ResolvedMember = $f.ToString(); $result.DeclaringType = $f.DeclaringType.FullName; $result.DeclaringAssembly = $f.DeclaringType.Assembly.GetName().Name
        }
        elseif ($Value -is [RuntimeMethodHandle]) {
            $m = [Reflection.MethodBase]::GetMethodFromHandle($Value)
            $result.ResolvedMember = $m.ToString(); $result.DeclaringType = $m.DeclaringType.FullName; $result.DeclaringAssembly = $m.DeclaringType.Assembly.GetName().Name
        } elseif ($Value -is [RuntimeFieldHandle]) {
            $f = [Reflection.FieldInfo]::GetFieldFromHandle($Value)
            $result.ResolvedMember = $f.ToString(); $result.DeclaringType = $f.DeclaringType.FullName; $result.DeclaringAssembly = $f.DeclaringType.Assembly.GetName().Name
        } elseif ($Value -is [RuntimeTypeHandle]) {
            $t = [Type]::GetTypeFromHandle($Value)
            $result.ResolvedMember = $t.FullName; $result.DeclaringType = $t.FullName; $result.DeclaringAssembly = $t.Assembly.GetName().Name
        } elseif ($Value -is [Reflection.Emit.DynamicMethod]) {
            $result.ResolvedMember = $Value.ToString(); $result.DeclaringType = 'DynamicMethod'; $result.ValueText = $Value.Name
        } elseif ($Value -is [string]) {
            $result.ValueKind = 'StringLiteral'; $result.ValueText = $Value
        } elseif ($Value -is [byte[]]) {
            $result.ValueKind = 'Signature'; $result.ValueText = [Convert]::ToHexString($Value)
        } else {
            $result.ValueText = [string]$Value
        }
    } catch { $result.ValueText = "UNRESOLVED: $($_.Exception.Message)" }
    $result
}

function Read-DynamicIl([byte[]]$Code, $Scope) {
    $map = Get-OpCodeMap
    $tokens = Get-PrivateFieldValue $Scope 'm_tokens'
    $rows = [Collections.Generic.List[object]]::new()
    for ($p = 0; $p -lt $Code.Length) {
        $offset = $p; $first = $Code[$p++]
        $key = if ($first -eq 0xFE) { [uint16](0xFE00 -bor $Code[$p++]) } else { [uint16]$first }
        $op = $map[$key]; if ($null -eq $op) { throw "Unknown IL opcode 0x{0:X4} at {1}" -f $key,$offset }
        $operandStart = $p; $size = Get-OperandSize $op.OperandType $Code $p
        $token = $null; $scopeItem = $null
        if ($op.OperandType -in @('InlineField','InlineMethod','InlineSig','InlineString','InlineTok','InlineType')) {
            $token = [BitConverter]::ToInt32($Code, $p)
            $index = $token -band 0x00FFFFFF
            if ($null -ne $tokens -and $index -lt $tokens.Count) { $scopeItem = $tokens[$index] }
        }
        $desc = Get-ScopeValueDescription $scopeItem
        $rows.Add([ordered]@{
            ILOffset = $offset; Opcode = $op.Name; OperandType = [string]$op.OperandType
            OperandHex = if ($size) { [Convert]::ToHexString($Code[$operandStart..($operandStart + $size - 1)]) } else { $null }
            MetadataToken = if ($null -ne $token) { ('0x{0:X8}' -f [uint32]$token) } else { $null }
            DynamicScopeIndex = if ($null -ne $token) { $token -band 0x00FFFFFF } else { $null }
            ResolvedMember = $desc.ResolvedMember; DeclaringType = $desc.DeclaringType; DeclaringAssembly = $desc.DeclaringAssembly
            DynamicScopeValueKind = $desc.ValueKind; StringLiteralOrValue = $desc.ValueText
            SourceExpressionAssociation = 'UNPROVEN: DynamicIL has no source-span table in this observer'
        })
        $p += $size
    }
    @($rows)
}

function New-NormalLambdaCompiler([Linq.Expressions.LambdaExpression]$Lambda) {
    $lcType = [Linq.Expressions.Expression].Assembly.GetType('System.Linq.Expressions.Compiler.LambdaCompiler', $true)
    $analyze = $lcType.GetMethods($StaticNonPublic) | Where-Object { $_.Name -eq 'AnalyzeLambda' -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    $analysisArgs = [object[]]@($Lambda); $tree = $analyze.Invoke($null, $analysisArgs); $lowered = [Linq.Expressions.LambdaExpression]$analysisArgs[0]
    $ctor = $lcType.GetConstructors($InstanceNonPublic) | Where-Object { $_.GetParameters().Count -eq 2 } | Select-Object -First 1
    $compiler = $ctor.Invoke([object[]]@($tree, $lowered))
    $emit = $lcType.GetMethods($InstanceNonPublic) | Where-Object { $_.Name -eq 'EmitLambdaBody' -and $_.GetParameters().Count -eq 0 } | Select-Object -First 1
    $null = $emit.Invoke($compiler, @())
    [ordered]@{ Type = $lcType; Compiler = $compiler; Lowered = $lowered; DynamicMethod = [Reflection.Emit.DynamicMethod](Get-PrivateFieldValue $compiler '_method') }
}

$full = (Resolve-Path -LiteralPath $Path).Path; $tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($full, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "PowerShell parse failed: $($errors[0].Message)" }
$functions = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))
$results = [Collections.Generic.List[object]]::new()
foreach ($function in $functions) {
    try {
        $lambda = Get-AuthenticLambda $ast $function
        $normal = New-NormalLambdaCompiler $lambda
        $getDescriptor = [Reflection.Emit.DynamicMethod].GetMethod('GetMethodDescriptor', $InstanceNonPublic)
        $null = $getDescriptor.Invoke($normal.DynamicMethod, @())
        $resolver = Get-PrivateFieldValue $normal.DynamicMethod '_resolver'
        $code = [byte[]](Get-PrivateFieldValue $resolver 'm_code'); $scope = Get-PrivateFieldValue $resolver 'm_scope'
        $bound = Get-PrivateFieldValue $normal.Compiler '_boundConstants'
        $toArray = $bound.GetType().GetMethod('ToArray', $InstanceNonPublic)
        $boundItems = @($toArray.Invoke($bound, @()) | ForEach-Object { Get-ScopeValueDescription $_ })
        $scopeItems = @((Get-PrivateFieldValue $scope 'm_tokens') | ForEach-Object { Get-ScopeValueDescription $_ })
        $results.Add([ordered]@{
            Function = $function.Name; FunctionStartOffset = $function.Extent.StartOffset; DynamicMethod = $normal.DynamicMethod.Name
            AuthenticILBytes = [Convert]::ToHexString($code); ILByteCount = $code.Length
            MaxStack = Get-PrivateFieldValue $resolver 'm_stackSize'; LocalSignature = [Convert]::ToHexString([byte[]](Get-PrivateFieldValue $resolver 'm_localSignature'))
            EH = [ordered]@{ ExceptionInfo = @((Get-PrivateFieldValue $resolver 'm_exceptions') | ForEach-Object { [string]$_ }); ExceptionHeader = if($null -ne (Get-PrivateFieldValue $resolver 'm_exceptionHeader')){[Convert]::ToHexString([byte[]](Get-PrivateFieldValue $resolver 'm_exceptionHeader'))}else{$null} }
            DynamicScopeTokens = $scopeItems; ILDependencies = Read-DynamicIl $code $scope; BoundConstants = $boundItems
            RyuJitExtent = 'UNASSESSED'; NativeDependencyClosure = 'UNASSESSED'
        })
    } catch { $results.Add([ordered]@{ Function=$function.Name; FunctionStartOffset=$function.Extent.StartOffset; MaterializationError=$_.Exception.Message; RyuJitExtent='UNASSESSED'; NativeDependencyClosure='UNASSESSED' }) }
}
$out = [ordered]@{ Schema='smadirect.authentic-dynamic-il.v1'; Status='OBSERVATION_ONLY'; Application=[ordered]@{Path=$full;Sha256=(Get-FileHash $full -Algorithm SHA256).Hash}; Runtime=[System.Environment]::Version.ToString(); FunctionCount=$functions.Count; Functions=@($results) }
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath)); [IO.Directory]::CreateDirectory($parent)|Out-Null
$out | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$materialized = @($results | Where-Object { -not $_.Contains('MaterializationError') }).Count
$failed = @($results | Where-Object { $_.Contains('MaterializationError') }).Count
[pscustomobject]@{OutputPath=[IO.Path]::GetFullPath($OutputPath);FunctionCount=$functions.Count;Materialized=$materialized;Failed=$failed;Status=$out.Status}
