$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'Apps\ObjectReplica\CapabilityDispatchReceipt.cpp'
$exe = Join-Path $root 'Apps\ObjectReplica\CapabilityDispatchReceipt.exe'
$vcvars = 'C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "Missing C++ build environment: $vcvars" }
$build = "call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /Fe:`"$exe`" `"$source`""
cmd.exe /c $build | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw 'Capability dispatch receipt native build failed.' }
$native = & $exe 2>&1
if ($LASTEXITCODE -ne 0 -or $native -notmatch 'verdict=PASS') { throw "Capability dispatch receipt failed: $native" }
[pscustomobject][ordered]@{
    test='Node-local GrantDomain-gated capability dispatch'
    pass=$true
    native=($native -join "`n")
    proven='Opaque local handle resolution gates generic OperationId dispatch; a resident capability acquires its GrantDomain before mutating a separate resident state object; rundown rejects new invocation while admitted work drains.'
    notProven='No Calculator behavior, SMA semantics, transport, cross-node dispatch, rematerialization, fencing, or CLR independence is implemented.'
    verdict='PASS'
}
