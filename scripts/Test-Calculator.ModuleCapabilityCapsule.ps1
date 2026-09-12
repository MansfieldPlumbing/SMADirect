$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent;$path=Join-Path $root 'Conformance\Calculator.ps1'
$calculator=New-Module -AsCustomObject -ArgumentList $path {
    param($calculatorPath);$env:DP_SKIP_START='1';. $calculatorPath;$script:CalculatorStateRoot=[CalculatorState]::new()
    function Get-CalculatorSemanticRoots {[pscustomobject]@{State=$script:CalculatorStateRoot;Buttons=$script:Buttons;Canvas=[pscustomobject]@{Status='HOSTED/OPAQUE';Capability='DirectPort.Canvas'}}}
    Export-ModuleMember -Function Invoke-CalculatorLogic,Get-CalculatorSemanticRoots
}
$method=$calculator.PSObject.Methods['Invoke-CalculatorLogic']
if($null -eq $method){throw 'Facade did not expose Invoke-CalculatorLogic as a PSScriptMethod.'}
$scriptBlock=$method.Script
$roots=$calculator.'Get-CalculatorSemanticRoots'()
if($scriptBlock.File -ne $path){throw 'PSScriptMethod Script did not retain the unchanged Calculator source identity.'}
[pscustomobject][ordered]@{
    test='Calculator module capability capsule census';pass=$true
    facade=[ordered]@{Type=$calculator.GetType().FullName;Members=@($calculator.PSObject.Methods.Name)}
    capability=[ordered]@{Name=$method.Name;Type=$method.GetType().FullName;OverloadDefinitions=@($method.OverloadDefinitions);ScriptType=$scriptBlock.GetType().FullName;ScriptFile=$scriptBlock.File;ScriptId=[string]$scriptBlock.Id}
    roots=[ordered]@{StateIdentity=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($roots.State);DisplayValue=$roots.State.DisplayValue;ButtonCount=$roots.Buttons.Count;Button104Label=$roots.Buttons[4].Label;Canvas=$roots.Canvas.Status}
    proven='Facade, PSScriptMethod identity, public ScriptBlock identity, and module-owned semantic roots are observable as objects.'
    hosted='PSScriptMethod.Invoke requires a PowerShell runspace; ScriptBlock execution remains hosted.'
    detached='NONE'
    semanticGap='Public PSScriptMethod.Script identifies executable hosted behavior but does not expose a detached object-level transition representation.'
    verdict='PASS: hosted semantic capsule census completed; detachment not claimed.'
}
