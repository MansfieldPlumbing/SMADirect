Set-StrictMode -Version Latest

function global:Open-NativeLibrary {
    param([Parameter(Mandatory)][string] $Name)
    [Runtime.InteropServices.NativeLibrary]::Load($Name)
}

function global:Get-NativeExport {
    param(
        [Parameter(Mandatory)][IntPtr] $Library,
        [Parameter(Mandatory)][string] $Name
    )
    [Runtime.InteropServices.NativeLibrary]::GetExport($Library, $Name)
}

function global:Close-NativeLibrary {
    param([Parameter(Mandatory)][IntPtr] $Library)
    if ($Library -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.NativeLibrary]::Free($Library)
    }
}
