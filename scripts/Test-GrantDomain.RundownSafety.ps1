$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'Apps\ObjectReplica\GrantDomainRundownReceipt.cpp'
$exe = Join-Path $root 'Apps\ObjectReplica\GrantDomainRundownReceipt.exe'
$vcvars = 'C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "Missing C++ build environment: $vcvars" }
$build = "call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /Fe:`"$exe`" `"$source`""
cmd.exe /c $build | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw 'GrantDomain rundown receipt native build failed.' }
$native = & $exe 2>&1
if ($LASTEXITCODE -ne 0 -or $native -notmatch 'verdict=PASS') { throw "GrantDomain rundown receipt failed: $native" }
[pscustomobject][ordered]@{
    test='GrantDomain linearizable Acquire-vs-Rundown'
    pass=$true
    native=($native -join "`n")
    proven='Local GrantDomain admission has one ordering point; rundown rejects later acquisitions, drains admitted acquisitions, retires only after drain, and stale handles stay stale after slot reuse.'
    notProven='No distributed rundown, transport, ownership transfer, fencing, or capability execution is implemented.'
    verdict='PASS'
}
