$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'Apps\ObjectReplica\ObjectYardHandleReceipt.cpp'
$exe = Join-Path $root 'Apps\ObjectReplica\ObjectYardHandleReceipt.exe'
$vcvars = 'C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "Missing C++ build environment: $vcvars" }

$build = "call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /Fe:`"$exe`" `"$source`""
cmd.exe /c $build | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw 'Object-yard handle receipt native build failed.' }

$native = & $exe 2>&1
if ($LASTEXITCODE -ne 0 -or $native -notmatch 'verdict=PASS') { throw "Object-yard handle receipt failed: $native" }

[pscustomobject][ordered]@{
    test = 'ObjectYard node-local opaque handle safety'
    pass = $true
    native = ($native -join "`n")
    proven = 'ObjectId, ObjectHandle, and NodeId remain distinct; each node resolves only its own grants; revocation advances generation; a stale handle cannot resolve to a reused slot.'
    notProven = 'No DirectPort traffic, distributed ownership policy, capability execution, or Calculator behavior is implemented.'
    verdict = 'PASS'
}
