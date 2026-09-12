Set-StrictMode -Version Latest

function ConvertTo-HResultUInt32 {
    param([Parameter(Mandatory)][int32] $Value)
    [BitConverter]::ToUInt32([BitConverter]::GetBytes($Value), 0)
}

function ConvertTo-HResultInt32 {
    param([Parameter(Mandatory)][uint32] $Value)
    [BitConverter]::ToInt32([BitConverter]::GetBytes($Value), 0)
}

function Test-HResultSucceeded {
    param([Parameter(Mandatory)][int32] $Value)
    $Value -ge 0
}

function Test-HResultFailed {
    param([Parameter(Mandatory)][int32] $Value)
    $Value -lt 0
}

function Get-HResultDescription {
    param([Parameter(Mandatory)][int32] $Value)
    $bits = ConvertTo-HResultUInt32 $Value
    [pscustomobject][ordered]@{
        Value = $Value
        Bits = $bits
        Hex = '0x{0:X8}' -f $bits
        Failed = $Value -lt 0
        Severity = ($bits -shr 31) -band 1
        Customer = ($bits -shr 29) -band 1
        Facility = ($bits -shr 16) -band 0x7FF
        Code = $bits -band 0xFFFF
    }
}

function Assert-HResult {
    param(
        [Parameter(Mandatory)][int32] $Value,
        [Parameter(Mandatory)][string] $Operation
    )
    if ($Value -lt 0) {
        $description = Get-HResultDescription $Value
        throw "$Operation failed with $($description.Hex) (facility $($description.Facility), code $($description.Code))."
    }
    $Value
}
