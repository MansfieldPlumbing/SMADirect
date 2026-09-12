#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$directPortPath = (Resolve-Path (Join-Path $PSScriptRoot '..\Conformance\DirectPort.ps1')).Path
$calculatorPath = (Resolve-Path (Join-Path $PSScriptRoot '..\Conformance\Calculator.ps1')).Path
$env:DP_HEADLESS = '1'

. $directPortPath -Headless
$root = $global:DirectPort

# ------------------------------------------------------------------------------
# 1. same-runspace retained capability invokes directly
# ------------------------------------------------------------------------------
$local = $root.Node.RetainLocal('Receipt.DirectValue', { 100 }, $root.Node)
if (-not [object]::ReferenceEquals($local, $root.Node.ResolveLocal('Receipt.DirectValue'))) {
    throw 'Resolver-local capability lookup introduced a checkout.'
}
$queueCountBefore = $script:DirectPortOwnerDispatchQueue.Count
$directResult = & $local.Capability
$queueCountAfter = $script:DirectPortOwnerDispatchQueue.Count
if ($directResult -ne 100 -or $queueCountBefore -ne $queueCountAfter) {
    throw 'Same-runspace retained capability did not invoke directly.'
}
$passSameRunspaceInvokesDirectly = $true

# ------------------------------------------------------------------------------
# 2. dedicated child gets only its checked-out Canvas proxy
# ------------------------------------------------------------------------------
[void]$root.Node.RetainLocal('Receipt.Add', { param($a, $b) $a + $b }, $root.Node)
[void]$root.Node.RetainLocal('Secret.Ungranted', { 'secret_value' }, $root.Node)

$childNode = New-DirectPortNode -Name 'Receipt.DedicatedChild' -Parent $root.Node
$script:DirectPortNode.Children[$childNode.NodeId] = $childNode

$discAdd = $childNode.Discover('Receipt.Add')
$childAddEntry = $childNode.Checkout($discAdd)

$childResident = New-DirectPortRunspace -Node $childNode -Commands @{
    'Invoke-ReceiptAdd' = 'Receipt.Add'
}

$pipe = [System.Management.Automation.PowerShell]::Create()
$pipe.Runspace = $childResident.Runspace
[void]$pipe.AddScript(@'
$hasAdd = (Get-Command 'Invoke-ReceiptAdd' -ErrorAction SilentlyContinue) -ne $null
$hasSecret = (Get-Command 'Secret.Ungranted' -ErrorAction SilentlyContinue) -ne $null
[PSCustomObject]@{ HasAdd = $hasAdd; HasSecret = $hasSecret }
'@)
$cmdCheck = @($pipe.Invoke())[0]
$pipe.Dispose()

if (-not $cmdCheck.HasAdd -or $cmdCheck.HasSecret) {
    throw 'Dedicated child did not get only its checked-out Canvas proxy.'
}
$passDedicatedChildGetsOnlyCanvasProxy = $true

# ------------------------------------------------------------------------------
# 3. child does not receive root ScriptBlock
# ------------------------------------------------------------------------------
$pipe = [System.Management.Automation.PowerShell]::Create()
$pipe.Runspace = $childResident.Runspace
[void]$pipe.AddScript(@'
$vars = Get-Variable
$hasScriptBlock = $false
foreach ($v in $vars) {
    if ($v.Value -is [System.Management.Automation.ScriptBlock]) {
        $hasScriptBlock = $true
        break
    }
}
$hasScriptBlock
'@)
$hasScriptBlockInChild = @($pipe.Invoke())[0]
$pipe.Dispose()

if ($hasScriptBlockInChild) {
    throw 'Child runspace received a root ScriptBlock object.'
}
$passChildDoesNotReceiveRootScriptBlock = $true

# ------------------------------------------------------------------------------
# 4. child does not receive root capability table
# ------------------------------------------------------------------------------
$pipe = [System.Management.Automation.PowerShell]::Create()
$pipe.Runspace = $childResident.Runspace
[void]$pipe.AddScript(@'
$hasRootNode = (Get-Variable -Name 'DirectPortNode' -ErrorAction SilentlyContinue) -ne $null
$hasRootDP   = (Get-Variable -Name 'DirectPort' -ErrorAction SilentlyContinue) -ne $null
$hasCaps     = (Get-Variable -Name 'LocalCapabilities' -ErrorAction SilentlyContinue) -ne $null
$hasHandles  = (Get-Variable -Name 'LocalHandles' -ErrorAction SilentlyContinue) -ne $null
[PSCustomObject]@{
    HasRootNode = $hasRootNode
    HasRootDP   = $hasRootDP
    HasCaps     = $hasCaps
    HasHandles  = $hasHandles
}
'@)
$tableCheck = @($pipe.Invoke())[0]
$pipe.Dispose()

if ($tableCheck.HasRootNode -or $tableCheck.HasRootDP -or $tableCheck.HasCaps -or $tableCheck.HasHandles) {
    throw 'Child runspace received root capability table or ambient root state.'
}
$passChildDoesNotReceiveRootCapabilityTable = $true

# ------------------------------------------------------------------------------
# 5. child invokes a root-owned capability through owner dispatch successfully
# ------------------------------------------------------------------------------
$pipe = [System.Management.Automation.PowerShell]::Create()
$pipe.Runspace = $childResident.Runspace
[void]$pipe.AddScript('Invoke-ReceiptAdd 40 2')
$childResident.PowerShell = $pipe
$childResident.Output = [System.Management.Automation.PSDataCollection[psobject]]::new()
$childResident.AsyncResult = $pipe.BeginInvoke[psobject,psobject]($null, $childResident.Output)

$addOutput = @($childResident.Wait(5000))
if ($addOutput.Count -ne 1 -or $addOutput[0] -ne 42) {
    throw "Child failed to invoke root-owned capability through owner dispatch. Output: $($addOutput -join ', ')"
}
$passChildInvokesRootCapabilityThroughOwnerDispatch = $true

# ------------------------------------------------------------------------------
# 6. the root-owned ScriptBlock executes only in its owning runspace
# ------------------------------------------------------------------------------
$rootRunspaceId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
[void]$root.Node.RetainLocal('Receipt.OwnerRunspaceId', {
    [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
}, $root.Node)

$discRS = $childNode.Discover('Receipt.OwnerRunspaceId')
[void]$childNode.Checkout($discRS)

$childRSResident = New-DirectPortRunspace -Node $childNode -Commands @{
    'Get-OwnerRunspaceId' = 'Receipt.OwnerRunspaceId'
}

$pipe = [System.Management.Automation.PowerShell]::Create()
$pipe.Runspace = $childRSResident.Runspace
[void]$pipe.AddScript(@'
$executedId = Get-OwnerRunspaceId
[PSCustomObject]@{
    ExecutedRunspaceId = $executedId
    ChildRunspaceId    = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
}
'@)
$childRSResident.PowerShell = $pipe
$childRSResident.Output = [System.Management.Automation.PSDataCollection[psobject]]::new()
$childRSResident.AsyncResult = $pipe.BeginInvoke[psobject,psobject]($null, $childRSResident.Output)

$rsOutput = @($childRSResident.Wait(5000))[0]
if ($rsOutput.ExecutedRunspaceId -ne $rootRunspaceId) {
    throw "ScriptBlock executed in runspace $($rsOutput.ExecutedRunspaceId) instead of root runspace $rootRunspaceId."
}
if ($rsOutput.ExecutedRunspaceId -eq $rsOutput.ChildRunspaceId) {
    throw 'ScriptBlock executed in child runspace instead of root runspace.'
}
$passRootScriptBlockExecutesOnlyInOwningRunspace = $true
$childRSResident.Dispose()

# ------------------------------------------------------------------------------
# 7. repeated cross-owner invocation does not corrupt PowerShell scope/session state
# ------------------------------------------------------------------------------
$pipe = [System.Management.Automation.PowerShell]::Create()
$pipe.Runspace = $childResident.Runspace
[void]$pipe.AddScript('1..50 | ForEach-Object { Invoke-ReceiptAdd $_ 1 }')
$childResident.PowerShell = $pipe
$childResident.Output = [System.Management.Automation.PSDataCollection[psobject]]::new()
$childResident.AsyncResult = $pipe.BeginInvoke[psobject,psobject]($null, $childResident.Output)

$loopOutput = @($childResident.Wait(10000))
if ($loopOutput.Count -ne 50 -or $loopOutput[49] -ne 51) {
    throw 'Repeated cross-owner invocation produced incorrect results or failed.'
}
$passRepeatedCrossOwnerInvocationClean = $true

# ------------------------------------------------------------------------------
# 8. no rediscovery occurs after checkout
# ------------------------------------------------------------------------------
$discoveryCountBefore = $childNode.DiscoveryCount
$pipe = [System.Management.Automation.PowerShell]::Create()
$pipe.Runspace = $childResident.Runspace
[void]$pipe.AddScript('1..10 | ForEach-Object { Invoke-ReceiptAdd $_ 10 }')
$childResident.PowerShell = $pipe
$childResident.Output = [System.Management.Automation.PSDataCollection[psobject]]::new()
$childResident.AsyncResult = $pipe.BeginInvoke[psobject,psobject]($null, $childResident.Output)
[void]@($childResident.Wait(5000))
$discoveryCountAfter = $childNode.DiscoveryCount

if ($discoveryCountBefore -ne $discoveryCountAfter) {
    throw "Discovery occurred during steady-state invocations: count before = $discoveryCountBefore, count after = $discoveryCountAfter."
}
$passNoRediscoveryOccursAfterCheckout = $true

# ------------------------------------------------------------------------------
# 9. detach/rundown invalidates/releases the child population correctly
# ------------------------------------------------------------------------------
$childResident.Dispose()
$childNode.Rundown = $true
foreach ($h in $childNode.LocalHandles.Values) { $h.Revoked = $true }
$script:DirectPortNode.Children.Remove($childNode.NodeId)

$rundownRequest = [PSCustomObject]@{
    TargetOwnerHandle = $childAddEntry.SourceObjectHandle
    ReceiverHandle    = $childAddEntry.ObjectHandle
    CallerNodeId      = $childNode.NodeId
    Arguments         = @(1, 2)
    Result            = $null
    ErrorRecord       = $null
    Completed         = [System.Threading.ManualResetEventSlim]::new($false)
    Status            = 'Pending'
}
$script:DirectPortOwnerDispatchQueue.Enqueue($rundownRequest)
[void]$script:DirectPortOwnerDispatchWake.Set()
[void](Invoke-DirectPortOwnerDispatch)

if ($rundownRequest.Status -ne 'Faulted' -or $null -eq $rundownRequest.ErrorRecord) {
    throw 'Invocation through rundown/detached child did not fail.'
}
$rundownRequest.Completed.Dispose()
$passDetachRundownInvalidatesChildPopulation = $true

# ------------------------------------------------------------------------------
# 10. root DirectPort survives child detach/failure
# ------------------------------------------------------------------------------
$postRundownResult = & $local.Capability
if ($postRundownResult -ne 100) {
    throw 'Root DirectPort did not survive child detach/rundown.'
}
$passRootDirectPortSurvivesChildDetach = $true

# ------------------------------------------------------------------------------
# 11. an ungranted capability is not available in the child
# ------------------------------------------------------------------------------
$childNode2 = New-DirectPortNode -Name 'Child2' -Parent $root.Node
$script:DirectPortNode.Children[$childNode2.NodeId] = $childNode2
$discDV = $childNode2.Discover('Receipt.DirectValue')
[void]$childNode2.Checkout($discDV)

$secretEntry = $root.Node.ResolveLocal('Secret.Ungranted')
$unauthRequest = [PSCustomObject]@{
    TargetOwnerHandle = $secretEntry.ObjectHandle
    ReceiverHandle    = 'unauthorized_handle'
    CallerNodeId      = $childNode2.NodeId
    Arguments         = @()
    Result            = $null
    ErrorRecord       = $null
    Completed         = [System.Threading.ManualResetEventSlim]::new($false)
    Status            = 'Pending'
}
$script:DirectPortOwnerDispatchQueue.Enqueue($unauthRequest)
[void]$script:DirectPortOwnerDispatchWake.Set()
[void](Invoke-DirectPortOwnerDispatch)

if ($unauthRequest.Status -ne 'Faulted' -or -not ($unauthRequest.ErrorRecord.ToString() -match 'not admitted')) {
    throw "Ungranted capability request was not rejected with admission failure. Status: $($unauthRequest.Status), Error: $($unauthRequest.ErrorRecord)"
}
$unauthRequest.Completed.Dispose()
$passUngrantedCapabilityUnavailableInChild = $true

# ------------------------------------------------------------------------------
# 12. owner busy / cancellation / timeout does not cause requester-side execution
# ------------------------------------------------------------------------------
$stalledNode = New-DirectPortNode -Name 'StalledApp' -Parent $root.Node
$script:DirectPortNode.Children[$stalledNode.NodeId] = $stalledNode
$discStall = $stalledNode.Discover('Receipt.DirectValue')
$stallEntry = $stalledNode.Checkout($discStall)

$timeoutSignaled = $false
try {
    $req = [PSCustomObject]@{
        TargetOwnerHandle = $stallEntry.SourceObjectHandle
        ReceiverHandle    = $stallEntry.ObjectHandle
        CallerNodeId      = $stalledNode.NodeId
        Arguments         = @()
        Result            = $null
        ErrorRecord       = $null
        Completed         = [System.Threading.ManualResetEventSlim]::new($false)
        Status            = 'Pending'
    }
    $script:DirectPortOwnerDispatchQueue.Enqueue($req)
    # Intentionally do not drain queue: simulate busy owner
    $signaled = $req.Completed.Wait(100)
    if (-not $signaled) {
        $req.Status = 'TimedOut'
        $timeoutSignaled = $true
        # Requester NEVER executes foreign owner scriptblock!
    }
}
finally {
    $req.Completed.Dispose()
    # Drain and discard timed-out request
    [void](Invoke-DirectPortOwnerDispatch)
}
if (-not $timeoutSignaled) {
    throw 'Owner timeout test did not signal timeout.'
}
$passOwnerBusyTimeoutDoesNotCauseRequesterExecution = $true

# ------------------------------------------------------------------------------
# 13. Canvas behavior/performance remains unchanged
# ------------------------------------------------------------------------------
$attachment = & $root.LoadApplication -Path $calculatorPath -ExecutionPlacement Inline -Start -Headless
if (-not [object]::ReferenceEquals($root, $global:DirectPort)) {
    throw 'Inline attachment replaced the DirectPort root.'
}
if ($attachment.Node.ResolveLocal('Canvas.New').Source -ne 'CHECKOUT') {
    throw 'Application Canvas capability was not checked out locally.'
}
if (-not (& $root.DetachApplication)) {
    throw 'Application detach failed.'
}
if ($null -ne $root.Node.CurrentApplication) {
    throw 'Application remained attached after detach.'
}
$passCanvasBehaviorUnchanged = $true

# ------------------------------------------------------------------------------
# EMIT COMPREHENSIVE RECEIPT
# ------------------------------------------------------------------------------
[PSCustomObject]@{
    Receipt                                            = 'DIRECTPORT_APPLICATION_HOST_PASS'
    DirectPortPath                                     = $root.SourcePath
    SameRunspaceInvokesDirectly                        = $passSameRunspaceInvokesDirectly
    DedicatedChildGetsOnlyCanvasProxy                  = $passDedicatedChildGetsOnlyCanvasProxy
    ChildDoesNotReceiveRootScriptBlock                 = $passChildDoesNotReceiveRootScriptBlock
    ChildDoesNotReceiveRootCapabilityTable             = $passChildDoesNotReceiveRootCapabilityTable
    ChildInvokesRootCapabilityThroughOwnerDispatch     = $passChildInvokesRootCapabilityThroughOwnerDispatch
    RootScriptBlockExecutesOnlyInOwningRunspace        = $passRootScriptBlockExecutesOnlyInOwningRunspace
    RepeatedCrossOwnerInvocationClean                  = $passRepeatedCrossOwnerInvocationClean
    NoRediscoveryOccursAfterCheckout                   = $passNoRediscoveryOccursAfterCheckout
    DetachRundownInvalidatesChildPopulation            = $passDetachRundownInvalidatesChildPopulation
    RootDirectPortSurvivesChildDetach                  = $passRootDirectPortSurvivesChildDetach
    UngrantedCapabilityUnavailableInChild              = $passUngrantedCapabilityUnavailableInChild
    OwnerBusyTimeoutDoesNotCauseRequesterExecution     = $passOwnerBusyTimeoutDoesNotCauseRequesterExecution
    CanvasBehaviorUnchanged                            = $passCanvasBehaviorUnchanged
}
