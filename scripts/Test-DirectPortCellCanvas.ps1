#requires -Version 7.0

[CmdletBinding()]
param(
    [string] $AssemblyPath = $env:DIRECTPORT_DLL,
    [string] $AtlasPng = $env:DIRECTPORT_ATLAS,
    [string] $MetricsJson = $env:DIRECTPORT_METRICS
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Conformance\DirectPort.ps1') -Headless

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "ASSERT: $Message" }
}

Assert-True ($null -ne $global:DirectPort.Version) 'Version root member regressed.'
Assert-True ($null -ne $global:DirectPort.NewCanvas) 'NewCanvas root member regressed.'
Assert-True ($null -ne $global:DirectPort.Host) 'Host root member regressed.'
Assert-True ($null -ne $global:DirectPort.Linker) 'Linker root member regressed.'
Assert-True ($null -ne $global:DirectPort.NewRetainedCanvas) 'Retained Canvas factory missing.'
Assert-True ($null -ne $global:DirectPort.Surface) 'DirectPort Surface owner missing.'

$program = $script:DirectPortCanvasProgram.ToString()
Assert-True ($program -match '\[uint32\[\]\]::new') 'Packed uint32 Canvas storage is missing.'
Assert-True (($program | Select-String -Pattern '\.TryPresent\(' -AllMatches).Matches.Count -eq 1) 'Canvas no longer has one coarse TryPresent boundary.'
Assert-True ($program -match '\$wait = if \(\$live\) \{ 0 \} else \{ 1000 \}') 'Animated and static waits regressed.'
Assert-True ($program -match 'GlyphAnimationStep') 'Glyph-local animation progression is missing.'
Assert-True ($program -notmatch '\$script:Frame') 'Generic Canvas frame state returned.'

if (-not $AssemblyPath) { $AssemblyPath = 'C:\Dev\DirectPort\Scripts\DirectPort.PowerShell.dll' }
if (-not $AtlasPng) { $AtlasPng = 'C:\Dev\atlas maps\GLYPHS\cascadia-code-atlas.png' }
if (-not $MetricsJson) { $MetricsJson = 'C:\Dev\atlas maps\GLYPHS\cascadia-code-metrics.json' }

$capability = & $global:DirectPort.NewRetainedCanvas -AssemblyPath $AssemblyPath -AtlasPng $AtlasPng -MetricsJson $MetricsJson
Assert-True (-not $capability.Attached) 'New retained Canvas unexpectedly owns a running lifetime.'
[void]$capability.Attach()
$deadline = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $deadline -and
       -not ($capability.Output -contains 'READY') -and
       $capability.PowerShell.InvocationStateInfo.State -eq [System.Management.Automation.PSInvocationState]::Running) {
    Start-Sleep -Milliseconds 20
}
Assert-True ($capability.Output -contains 'READY') 'Retained Canvas did not reach its first presentation.'
Assert-True $capability.Attached 'DirectPort did not retain the attached Canvas lifetime.'
$capability.Detach()
Assert-True (-not $capability.Attached) 'DirectPort-owned Canvas did not detach.'

'PASS DirectPort retained packed-cell Canvas ownership receipt'
