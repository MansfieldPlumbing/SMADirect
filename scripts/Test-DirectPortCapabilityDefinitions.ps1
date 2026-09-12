[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$directPortPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Conformance\DirectPort.ps1'
. $directPortPath

function Assert-Receipt([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$required = @(
    'Native.Library.Open',
    'Native.Export.Get',
    'Native.Call.Get',
    'Native.Memory.Allocate',
    'Native.Memory.Release',
    'Canvas.New',
    'Windows.Host.New',
    'Runspace.New',
    'Application.Load'
)

foreach ($name in $required) {
    Assert-Receipt $global:DirectPort.CapabilityDefinitions.Contains($name) "Missing capability definition: $name"
    Assert-Receipt ($global:DirectPort.CapabilityDefinitions[$name].Capability -is [scriptblock]) "Capability is not a ScriptBlock: $name"
}

$before = $global:DirectPort.Node.LocalCapabilities.Count
[void](Register-DirectPortCapabilityDefinition -Name 'Receipt.Add' -Capability { param([int] $A, [int] $B) $A + $B })
Assert-Receipt ($global:DirectPort.Node.LocalCapabilities.Count -eq $before) 'Registration implicitly admitted a capability.'

$entry = Add-DirectPortCapabilityToNode -Name 'Receipt.Add' -Node $global:DirectPort.Node -ExecutionOwner $global:DirectPort.Node
Assert-Receipt ($entry.Source -ceq 'LOCAL') 'Explicit admission did not create a resolver-local capability.'
Assert-Receipt ((& $entry.Capability 19 23) -eq 42) 'Admitted ScriptBlock did not invoke directly.'

$androidNode = New-DirectPortNode -Name 'Receipt.Android'
$rejected = $false
try {
    [void](Add-DirectPortCapabilityToNode -Name 'Windows.Host.New' -Node $androidNode -Platform Android)
}
catch {
    $rejected = $_.Exception.Message -like "*requires platform 'Windows'*"
}
Assert-Receipt $rejected 'Android admission did not reject a Windows-only realization.'
Assert-Receipt ($androidNode.LocalCapabilities.Count -eq 0) 'Rejected platform capability mutated the receiver.'

[pscustomobject]@{
    Status                    = 'PASS'
    Definitions               = $global:DirectPort.CapabilityDefinitions.Count
    RegistrationIsInert       = $true
    ExplicitAdmission         = $true
    DirectScriptBlockInvoke   = $true
    WindowsRejectedOnAndroid  = $true
    SchedulerIntroduced       = $false
    FrameSemanticIntroduced   = $false
}
