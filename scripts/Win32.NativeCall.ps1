Set-StrictMode -Version Latest

$script:NativeCallAssembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('SMADirect.Windows.NativeCall.' + [Guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$script:NativeCallModule = $script:NativeCallAssembly.DefineDynamicModule('NativeCall')
$script:NativeCallOrdinal = 0

function global:New-NativeCallType {
    param(
        [Parameter(Mandatory)][Type] $ReturnType,
        [Parameter(Mandatory)][AllowEmptyCollection()][Type[]] $ParameterTypes
    )
    $script:NativeCallOrdinal++
    $type = $script:NativeCallModule.DefineType(
        "Call$script:NativeCallOrdinal",
        [Reflection.TypeAttributes]'Class,Public,Sealed',
        [MulticastDelegate])
    $constructor = $type.DefineConstructor(
        [Reflection.MethodAttributes]'RTSpecialName,HideBySig,Public',
        [Reflection.CallingConventions]::Standard,
        [Type[]]@([object],[IntPtr]))
    $constructor.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $invoke = $type.DefineMethod(
        'Invoke',
        [Reflection.MethodAttributes]'Public,HideBySig,NewSlot,Virtual',
        $ReturnType,
        $ParameterTypes)
    $invoke.SetImplementationFlags([Reflection.MethodImplAttributes]'Runtime,Managed')
    $type.CreateType()
}

function global:Get-NativeCall {
    param(
        [Parameter(Mandatory)][IntPtr] $Address,
        [Parameter(Mandatory)][Type] $ReturnType,
        [Parameter(Mandatory)][AllowEmptyCollection()][Type[]] $ParameterTypes
    )
    $shape = New-NativeCallType $ReturnType $ParameterTypes
    [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($Address, $shape)
}
