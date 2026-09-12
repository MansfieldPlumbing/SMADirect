param(
    [string]$DirectPortPath = 'C:\Dev\DirectPort\DirectPort.ps1'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $DirectPortPath)) { throw "DirectPort donor was not found: $DirectPortPath" }
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Apps\DirectPort.ETS.psm1') -Force
. $DirectPortPath

$target = New-DirectPortCanvas -Width 64 -Height 64 -Headless -SoftwareRendering
$canvas = New-DirectPortCanvasFacade -Target $target
try {
    $null = $canvas.BeginDraw([uint32]0)
    $null = $canvas.FillRect([single]1,[single]1,[single]10,[single]10,[uint32]::MaxValue,[single]0)
    $published = $canvas.Publish()
    if ($canvas.PSObject.TypeNames[0] -ne 'DirectPort.Canvas') { throw 'DirectPort target was not laundered to DirectPort.Canvas.' }
    if (-not $published) { throw 'The existing DirectPort native target did not publish through the facade.' }
    [pscustomobject][ordered]@{
        test = 'DirectPort ETS facade over Windows target'
        pass = $true
        semanticType = $canvas.PSObject.TypeNames[0]
        targetType = $target.GetType().FullName
        published = $published
        producer = $DirectPortPath
        managedRuntimeDependency = 'OPEN: ETS facade and the current DirectPort bootstrap run under hosted PowerShell'
        verdict = 'PASS: the existing DirectPort Windows canvas was consumed as a DirectPort.Canvas object without application platform branching.'
    }
} finally {
    $canvas.Dispose()
}
