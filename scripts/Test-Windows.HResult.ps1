Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Compiler\Win32.HResult.ps1')

if (-not (Test-HResultSucceeded 0)) { throw 'S_OK was not successful.' }
if (-not (Test-HResultSucceeded 1)) { throw 'S_FALSE was not successful.' }
$accessDeniedBits = [uint32]::Parse('80070005', [Globalization.NumberStyles]::HexNumber)
$accessDenied = ConvertTo-HResultInt32 $accessDeniedBits
if (-not (Test-HResultFailed $accessDenied)) { throw 'E_ACCESSDENIED was not failed.' }
$description = Get-HResultDescription $accessDenied
if ($description.Hex -cne '0x80070005' -or $description.Facility -ne 7 -or $description.Code -ne 5) {
    throw 'HRESULT decomposition was incorrect.'
}
$caught = $false
try { [void](Assert-HResult $accessDenied 'Open surface') } catch {
    $caught = $_.Exception.Message -ceq 'Open surface failed with 0x80070005 (facility 7, code 5).'
}
if (-not $caught) { throw 'Assert-HResult did not produce the expected diagnostic.' }

[pscustomobject]@{
    Status = 'PASS'
    SucceededCases = 2
    FailedCases = 1
    Example = $description.Hex
    Facility = $description.Facility
    Code = $description.Code
    AuthoredCSharp = 0
}
