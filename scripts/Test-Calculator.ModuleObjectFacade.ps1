$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$root=Split-Path $PSScriptRoot -Parent
$calculatorPath=Join-Path $root 'Conformance\Calculator.ps1'
$calculator=New-Module -AsCustomObject -ArgumentList $calculatorPath {
    param($path)
    $env:DP_SKIP_START='1'
    . $path
    $script:CalculatorStateRoot=[CalculatorState]::new()
    function Get-CalculatorSemanticRoots {
        [pscustomobject]@{ State=$script:CalculatorStateRoot; Buttons=$script:Buttons; Canvas=[pscustomobject]@{ Status='HOSTED/OPAQUE'; Capability='DirectPort.Canvas' } }
    }
    Export-ModuleMember -Function Invoke-CalculatorLogic,Get-CalculatorSemanticRoots
}

$roots=$calculator.'Get-CalculatorSemanticRoots'()
if($roots.Buttons.Count -ne 19){throw "Expected 19 module-owned buttons; got $($roots.Buttons.Count)."}
if($roots.State.DisplayValue -ne '0'){throw 'Expected module-owned initial display value 0.'}
$calculator.'Invoke-CalculatorLogic'($roots.State,'7','num')
if($roots.State.DisplayValue -ne '7'){throw 'Exported ScriptMethod did not invoke the original module-scoped Calculator function.'}
$members=@($calculator.PSObject.Members|Where-Object{$_.MemberType -in 'ScriptMethod','Property','NoteProperty'}|ForEach-Object{"$($_.Name):$($_.MemberType)"})
[pscustomobject][ordered]@{
    test='Calculator New-Module AsCustomObject facade'
    pass=$true
    facadeType=$calculator.GetType().FullName
    semanticMembers=$members
    stateIdentity=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($roots.State)
    buttonCount=$roots.Buttons.Count
    button104Label=$roots.Buttons[4].Label
    before='0'
    after=$roots.State.DisplayValue
    proven='PowerShell created one object interface whose ScriptMethods execute in the private module scope containing unchanged Calculator.ps1.'
    hosted='Both exported ScriptMethods remain hosted PowerShell behavior.'
    detached='NONE'
    verdict='PASS: module object facade is a cleaner hosted semantic root; no detachment claim.'
}
