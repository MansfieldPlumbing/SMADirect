Set-StrictMode -Version Latest

function global:New-NativeBlock {
    param([Parameter(Mandatory)][ValidateRange(1, 2147483647)][int] $Bytes)
    $address = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
    for ($offset = 0; $offset -lt $Bytes; $offset++) {
        [Runtime.InteropServices.Marshal]::WriteByte($address, $offset, 0)
    }
    $address
}

function global:Remove-NativeBlock {
    param([Parameter(Mandatory)][IntPtr] $Address)
    if ($Address -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($Address)
    }
}

function global:New-NativeGuidBlock {
    param([Parameter(Mandatory)][Guid] $Value)
    $address = New-NativeBlock 16
    [Runtime.InteropServices.Marshal]::Copy($Value.ToByteArray(), 0, $address, 16)
    $address
}
