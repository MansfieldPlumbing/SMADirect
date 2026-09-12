Set-StrictMode -Version Latest

function global:Get-ComMethodAddress {
    param(
        [Parameter(Mandatory)][IntPtr] $Object,
        [Parameter(Mandatory)][ValidateRange(0, 4095)][int] $Slot
    )
    if ($Object -eq [IntPtr]::Zero) { throw 'COM object handle is zero.' }
    $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($Object)
    if ($vtable -eq [IntPtr]::Zero) { throw 'COM object vtable is zero.' }
    $method = [Runtime.InteropServices.Marshal]::ReadIntPtr($vtable, $Slot * [IntPtr]::Size)
    if ($method -eq [IntPtr]::Zero) { throw "COM method slot $Slot is zero." }
    $method
}

function global:Get-ComCall {
    param(
        [Parameter(Mandatory)][IntPtr] $Object,
        [Parameter(Mandatory)][int] $Slot,
        [Parameter(Mandatory)][Type] $ReturnType,
        [Parameter(Mandatory)][AllowEmptyCollection()][Type[]] $ParameterTypes
    )
    Get-NativeCall (Get-ComMethodAddress $Object $Slot) $ReturnType $ParameterTypes
}
