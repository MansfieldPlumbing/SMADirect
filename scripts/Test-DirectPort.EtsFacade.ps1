$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Apps\DirectPort.ETS.psm1') -Force

$calls = [Collections.Generic.List[string]]::new()
$target = [pscustomobject]@{ Width = [single]340; Height = [single]520 }
foreach ($name in @('BeginDraw','EndDraw','FillRect','DrawRect','DrawText','MeasureText','Publish','Pump','WaitEvent','Dispose')) {
    $methodName = $name
    $target | Add-Member -MemberType ScriptMethod -Name $methodName -Value {
        $calls.Add("$methodName/$($args.Count)")
        if ($methodName -eq 'MeasureText') { return [pscustomobject]@{ Width=[single]19; Height=[single]11 } }
        if ($methodName -eq 'Publish') { return $true }
    }.GetNewClosure()
}

$canvas = New-DirectPortCanvasFacade -Target $target
$null = $canvas.BeginDraw([uint32]0)
$null = $canvas.FillRect([single]1,[single]2,[single]3,[single]4,[uint32]::MaxValue,[single]0)
$metrics = $canvas.MeasureText('42',[single]12,'Segoe UI',$true)
$published = $canvas.Publish()

$expected = @('BeginDraw/1','FillRect/6','MeasureText/4','Publish/0')
if ($canvas.PSObject.TypeNames[0] -ne 'DirectPort.Canvas') { throw 'Facade did not publish the DirectPort.Canvas identity.' }
if ($canvas.Width -ne [single]340 -or $canvas.Height -ne [single]520) { throw 'Facade properties did not forward to the target.' }
if (($calls -join ',') -cne ($expected -join ',')) { throw "Unexpected forwarded calls: $($calls -join ',')" }
if ($metrics.Width -ne [single]19 -or -not $published) { throw 'Facade did not preserve returned target values.' }

[pscustomobject][ordered]@{
    test = 'DirectPort ETS canvas facade'
    pass = $true
    semanticType = $canvas.PSObject.TypeNames[0]
    targetType = $target.GetType().FullName
    forwardedCalls = @($calls)
    dimensions = "$($canvas.Width)x$($canvas.Height)"
    managedRuntimeDependency = 'OPEN: ETS ScriptMethod dispatch requires SMA/PowerShell at runtime'
    verdict = 'PASS: ordinary Canvas object vocabulary forwards through an ETS facade; no platform branch entered the consumer.'
}
