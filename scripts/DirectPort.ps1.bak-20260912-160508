#requires -Version 7.0
<#
.SYNOPSIS
    DirectPort.ps1 - Normative Implementation Architecture (DP-ARCH-005 Conforming)
.DESCRIPTION
    Universal graphical application compatibility shim and presentation runtime for PowerShell.
    Implements DP-ARCH-005 specification:
    - Zero C# Add-Type compilation (pure .NET BCL NativeLibrary + cached dynamic delegates)
    - Separated Windows Host, Windows Canvas/Text, and optional D3D12 SysRAM IPC Sharing
    - Normalized portable contracts ($Canvas, $Input, $App)
    - Deduplicated input message decoding
    - Hot-path allocation freeze (cached text metrics, scratch blocks, zero per-frame delegate generation)
    - Built-in self-contained script bundler / linker (Export-DirectPortBundle)
    - Backward-compatible New-DirectPortCanvas & $DirectPort conformance carrier
#>

[CmdletBinding()]
param(
    [switch] $Headless,
    [int] $Width = 960,
    [int] $Height = 540,
    [string] $Title = "DirectPort Unified Canvas Carrier",
    [string] $Bundle = $null,
    [string] $OutFile = $null,
    [switch] $EnableSharing = $false,
    [switch] $SoftwareRendering = $false,
    [string] $AssemblyPath,
    [string] $AtlasPng,
    [string] $MetricsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DirectPortSourcePath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

# ==============================================================================
# SECTION 00: VERSION & DIRECTPORT RUNTIME STATE
# ==============================================================================

$dpVar = Get-Variable -Name DirectPortRuntimeState -Scope Global -ErrorAction SilentlyContinue
$dpRuntime = $null
if ($null -ne $dpVar) {
    $candidate = $dpVar.Value
    if ($null -ne $candidate) {
        $hasMarker = $null -ne $candidate.PSObject.Properties['RuntimeKind']
        $hasAsm    = $null -ne $candidate.PSObject.Properties['NativeAssembly']
        $hasMod    = $null -ne $candidate.PSObject.Properties['NativeModule']

        if ($hasMarker -and $hasAsm -and $hasMod -and $candidate.RuntimeKind -eq 'DirectPort') {
            $dpRuntime = $candidate
        }
    }
}

if ($null -eq $dpRuntime) {
    $dpRuntime = [PSCustomObject]@{
        RuntimeKind    = 'DirectPort'
        Version        = '0.5.0-rehab'
        Spec           = 'DP-ARCH-005'
        Platform       = if ($IsWindows) { 'Windows' } elseif ($IsLinux -and (Test-Path '/system/build.prop')) { 'Android' } else { 'Generic' }
        NativeAssembly = $null
        NativeModule   = $null
        DelegateTypes  = [System.Collections.Concurrent.ConcurrentDictionary[string, Type]]::new()
        NativeStubs    = [System.Collections.Concurrent.ConcurrentDictionary[string, [Delegate]]]::new()
    }
}

if ($null -eq $dpRuntime.NativeAssembly -or $null -eq $dpRuntime.NativeModule) {
    $nativeAssembly = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [System.Reflection.AssemblyName]::new("DirectPort.Native." + [Guid]::NewGuid().ToString('N')),
        [System.Reflection.Emit.AssemblyBuilderAccess]::Run
    )
    $dpRuntime.NativeAssembly = $nativeAssembly
    $dpRuntime.NativeModule   = $nativeAssembly.DefineDynamicModule("DirectPort.NativeModule")
}

$global:DirectPortRuntimeState = $dpRuntime

# ==============================================================================
# SECTION 10: PORTABLE PUBLIC CONTRACTS
# ==============================================================================
<#
    Normative contracts according to DP-ARCH-005 Section 6:
    $Canvas:
      BeginDraw, FillRect, DrawRect, DrawText, MeasureText, DrawBitmap, Present, Width, Height, Alive, Dispose
    $Input:
      Alive, Width, Height, PointerX, PointerY, PrimaryDown, Key, Text, ResizeSerial, RedrawSerial
    $App:
      Close, Minimize, BeginWindowMove, DragWindow, RequestExit, Title
#>

# ==============================================================================
# SECTION 20: INERT BINDING RECORDS (DP-ARCH-005 SECTION 9)
# ==============================================================================

$script:DirectPortBindings = {
    # DP-ARCH-005 Stage 10: Binding records are admitted only after
    # working implementation functions exist and pass tests.
}

# ==============================================================================
# SECTION 30: COMMON HELPERS & DUCK-TYPING SYNTHESIS
# ==============================================================================

function global:Initialize-WindowsGraphicsTypes {
    if ([System.Management.Automation.PSTypeName]::new('Windows.Graphics.Color').Type -ne $null -and
        [System.Management.Automation.PSTypeName]::new('Windows.Graphics.CanvasWindowState').Type -ne $null) {
        return
    }

    $asmName = [System.Reflection.AssemblyName]::new("SMADirect.WindowsGraphics." + [Guid]::NewGuid().ToString('N'))
    $assembly = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($asmName, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module = $assembly.DefineDynamicModule("SMADirectDuckTypes")

    # 1. Windows.Graphics.Color
    if ([System.Management.Automation.PSTypeName]::new('Windows.Graphics.Color').Type -eq $null) {
        $tbColor = $module.DefineType("Windows.Graphics.Color", [System.Reflection.TypeAttributes]'Public,Class')

        $mbRgb = $tbColor.DefineMethod("Rgb", [System.Reflection.MethodAttributes]'Public,Static', [int32], @([int32],[int32],[int32]))
        $il = $mbRgb.GetILGenerator()
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4, [int32]-16777216)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4_S, [byte]16)
        $il.Emit([System.Reflection.Emit.OpCodes]::Shl)
        $il.Emit([System.Reflection.Emit.OpCodes]::Or)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldarg_1)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4_S, [byte]8)
        $il.Emit([System.Reflection.Emit.OpCodes]::Shl)
        $il.Emit([System.Reflection.Emit.OpCodes]::Or)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldarg_2)
        $il.Emit([System.Reflection.Emit.OpCodes]::Or)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ret)

        $mbArgb = $tbColor.DefineMethod("Argb", [System.Reflection.MethodAttributes]'Public,Static', [int32], @([int32],[int32],[int32],[int32]))
        $il = $mbArgb.GetILGenerator()
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldarg_0)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4_S, [byte]24)
        $il.Emit([System.Reflection.Emit.OpCodes]::Shl)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldarg_1)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4_S, [byte]16)
        $il.Emit([System.Reflection.Emit.OpCodes]::Shl)
        $il.Emit([System.Reflection.Emit.OpCodes]::Or)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldarg_2)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4_S, [byte]8)
        $il.Emit([System.Reflection.Emit.OpCodes]::Shl)
        $il.Emit([System.Reflection.Emit.OpCodes]::Or)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ldarg_3)
        $il.Emit([System.Reflection.Emit.OpCodes]::Or)
        $il.Emit([System.Reflection.Emit.OpCodes]::Ret)

        $fields = @{}
        $palette = @{
            'White'       = [int32]-1;
            'Black'       = [int32]-16777216;
            'Transparent' = [int32]0;
            'Red'         = [int32]-65536;
            'Green'       = [int32]-16711936;
            'Blue'        = [int32]-16776961;
            'Yellow'      = [int32]-256;
            'Cyan'        = [int32]-16711681;
            'Magenta'     = [int32]-65281;
            'Gray'        = [int32]-8355712;
            'DarkGray'    = [int32]-12303292;
            'LightGray'   = [int32]-3355444;
        }
        foreach ($p in $palette.GetEnumerator()) {
            $fields[$p.Key] = $tbColor.DefineField($p.Key, [int32], [System.Reflection.FieldAttributes]'Public,Static,InitOnly')
        }

        $cctor = $tbColor.DefineConstructor([System.Reflection.MethodAttributes]'Private,Static,SpecialName,RTSpecialName', [System.Reflection.CallingConventions]::Standard, [Type[]]@())
        $il = $cctor.GetILGenerator()
        foreach ($p in $palette.GetEnumerator()) {
            $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4, [int32]$p.Value)
            $il.Emit([System.Reflection.Emit.OpCodes]::Stsfld, $fields[$p.Key])
        }
        $il.Emit([System.Reflection.Emit.OpCodes]::Ret)
        [void]$tbColor.CreateType()
    }

    # 2. Windows.Graphics.CanvasWindowState
    if ([System.Management.Automation.PSTypeName]::new('Windows.Graphics.CanvasWindowState').Type -eq $null) {
        $tbCws = $module.DefineType("Windows.Graphics.CanvasWindowState", [System.Reflection.TypeAttributes]'Public,Class')
        [void]$tbCws.DefineField("Alive", [bool], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("Width", [int32], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("Height", [int32], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("MouseX", [int32], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("MouseY", [int32], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("LeftDown", [bool], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("RightDown", [bool], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("WheelDelta", [int32], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("KeyCode", [int32], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("CharCode", [char], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("IsDoubleClick", [bool], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("ResizeSerial", [uint64], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.DefineField("RedrawSerial", [uint64], [System.Reflection.FieldAttributes]'Public')
        [void]$tbCws.CreateType()
    }

    # 3. Windows.Graphics.TextMetrics
    if ([System.Management.Automation.PSTypeName]::new('Windows.Graphics.TextMetrics').Type -eq $null) {
        $tbTm = $module.DefineType("Windows.Graphics.TextMetrics", [System.Reflection.TypeAttributes]'Public,Class')
        [void]$tbTm.DefineField("Width", [single], [System.Reflection.FieldAttributes]'Public')
        [void]$tbTm.DefineField("Height", [single], [System.Reflection.FieldAttributes]'Public')
        [void]$tbTm.CreateType()
    }
}

Initialize-WindowsGraphicsTypes

# ==============================================================================
# SECTION 40: NATIVE ABI MATERIALIZATION (ZERO C# ADD-TYPE, CACHED STUBS)
# ==============================================================================

function global:Open-NativeLibrary([string]$Name) {
    if ([System.Runtime.InteropServices.NativeLibrary] -as [type]) {
        return [System.Runtime.InteropServices.NativeLibrary]::Load($Name)
    }
    throw "NativeLibrary BCL API is required on PowerShell 7+."
}

function global:Get-NativeExport([IntPtr]$hModule, [string]$Name) {
    if ([System.Runtime.InteropServices.NativeLibrary] -as [type]) {
        return [System.Runtime.InteropServices.NativeLibrary]::GetExport($hModule, $Name)
    }
    throw "NativeLibrary BCL API is required on PowerShell 7+."
}

function global:New-NativeBlock([int]$Size) {
    $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($Size)
    $bytes = New-Object byte[] $Size
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ptr, $Size)
    return $ptr
}

function global:Remove-NativeBlock([IntPtr]$Ptr) {
    if ($Ptr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($Ptr) }
}

function global:Get-NativeDelegateType([Type]$ReturnType, [Type[]]$ParameterTypes) {
    $paramNames = ($ParameterTypes | ForEach-Object { $_.FullName }) -join ';'
    $sigKey = "$($ReturnType.FullName)::$paramNames"

    $existing = $null
    if ($global:DirectPortRuntimeState.DelegateTypes.TryGetValue($sigKey, [ref]$existing)) {
        return $existing
    }

    $typeName = "DirectPortDelegate_" + [Guid]::NewGuid().ToString('N')
    $tb = $global:DirectPortRuntimeState.NativeModule.DefineType(
        $typeName,
        [System.Reflection.TypeAttributes]'Class,Public,Sealed,AnsiClass,AutoClass',
        [System.MulticastDelegate]
    )
    $ctor = $tb.DefineConstructor(
        [System.Reflection.MethodAttributes]'RTSpecialName,HideBySig,Public',
        [System.Reflection.CallingConventions]::Standard,
        @([object], [IntPtr])
    )
    $ctor.SetImplementationFlags([System.Reflection.MethodImplAttributes]'Runtime,Managed')

    $invoke = $tb.DefineMethod(
        "Invoke",
        [System.Reflection.MethodAttributes]'Public,HideBySig,NewSlot,Virtual',
        $ReturnType,
        $ParameterTypes
    )
    $invoke.SetImplementationFlags([System.Reflection.MethodImplAttributes]'Runtime,Managed')

    $callConv = [System.Runtime.InteropServices.CallingConvention]::StdCall
    $attrCtor = [System.Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(@([System.Runtime.InteropServices.CallingConvention]))
    $attrBldr = [System.Reflection.Emit.CustomAttributeBuilder]::new($attrCtor, @($callConv))
    $tb.SetCustomAttribute($attrBldr)

    $delType = $tb.CreateType()
    $global:DirectPortRuntimeState.DelegateTypes[$sigKey] = $delType
    return $delType
}

function global:Get-NativeCall([IntPtr]$FuncPtr, [Type]$ReturnType, [Type[]]$ParameterTypes) {
    if ($FuncPtr -eq [IntPtr]::Zero) { throw "Cannot bind native call on null function pointer." }
    $paramNames = ($ParameterTypes | ForEach-Object { $_.FullName }) -join ';'
    $stubKey = "$($FuncPtr.ToInt64()):$($ReturnType.FullName)::$paramNames"

    $existing = $null
    if ($global:DirectPortRuntimeState.NativeStubs.TryGetValue($stubKey, [ref]$existing)) {
        return $existing
    }

    $delType = Get-NativeDelegateType -ReturnType $ReturnType -ParameterTypes $ParameterTypes
    $del = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($FuncPtr, $delType)
    $global:DirectPortRuntimeState.NativeStubs[$stubKey] = $del
    return $del
}

function global:Get-ComCall([IntPtr]$ComObj, [int]$VTableIndex, [Type]$ReturnType, [Type[]]$ParameterTypes) {
    if ($ComObj -eq [IntPtr]::Zero) { throw "Cannot bind COM call on null interface pointer." }
    $vtable = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($ComObj)
    if ($vtable -eq [IntPtr]::Zero) { throw "Interface pointer vtable is null." }
    $funcPtr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($vtable, $VTableIndex * [IntPtr]::Size)
    return Get-NativeCall -FuncPtr $funcPtr -ReturnType $ReturnType -ParameterTypes $ParameterTypes
}

# ==============================================================================
# SECTION 50: WINDOWS HOST (HWND & LIFECYCLE MANAGEMENT)
# ==============================================================================

function global:New-WindowsHost {
    [CmdletBinding()]
    param(
        [int] $Width = 960,
        [int] $Height = 540,
        [string] $Title = 'DirectPort Window',
        [switch] $Borderless,
        [switch] $Headless
    )

    if ($Headless) {
        return [PSCustomObject]@{
            Hwnd         = [IntPtr]::Zero
            HModule      = [IntPtr]::Zero
            ClassName    = $null
            Title        = $Title
            Width        = $Width
            Height       = $Height
            Borderless   = [bool]$Borderless
            Headless     = $true
            Alive        = $true
            WindowShown  = $false
        }
    }

    $user32   = Open-NativeLibrary "user32.dll"
    $kernel32 = Open-NativeLibrary "kernel32.dll"
    $dwmapi   = Open-NativeLibrary "dwmapi.dll"

    $fnGetModuleHandleW = Get-NativeCall (Get-NativeExport $kernel32 'GetModuleHandleW') ([IntPtr]) ([Type[]]@([IntPtr]))
    $hModule = $fnGetModuleHandleW.DynamicInvoke([IntPtr]::Zero)
    $pDefWndProc = Get-NativeExport $user32 'DefWindowProcW'

    $className = "DirectPortCanvasClass_" + [Guid]::NewGuid().ToString('N').Substring(0,8)
    $pClassName = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($className)
    $pTitle = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($Title)

    $cbSize = 80
    $pClass = New-NativeBlock $cbSize
    [System.Runtime.InteropServices.Marshal]::WriteInt32($pClass, 0, $cbSize)
    [System.Runtime.InteropServices.Marshal]::WriteInt32($pClass, 4, 3)
    [System.Runtime.InteropServices.Marshal]::WriteIntPtr($pClass, 8, $pDefWndProc)
    [System.Runtime.InteropServices.Marshal]::WriteIntPtr($pClass, 24, $hModule)
    [System.Runtime.InteropServices.Marshal]::WriteIntPtr($pClass, 64, $pClassName)

    $fnRegisterClass = Get-NativeCall (Get-NativeExport $user32 'RegisterClassExW') ([uint16]) ([Type[]]@([IntPtr]))
    $atom = [uint16]$fnRegisterClass.DynamicInvoke($pClass)
    Remove-NativeBlock $pClass

    $fnCreateWindow = Get-NativeCall (Get-NativeExport $user32 'CreateWindowExW') ([IntPtr]) ([Type[]]@(
        [uint32],[IntPtr],[IntPtr],[uint32],[int32],[int32],[int32],[int32],[IntPtr],[IntPtr],[IntPtr],[IntPtr]
    ))

    $winStyle = if ($Borderless) { 0x80000000u } else { 0x00CF0000u }
    $exStyle  = if ($Borderless) { 0x00040000u } else { 0u }
    $hwnd = [IntPtr]$fnCreateWindow.DynamicInvoke(
        $exStyle, $pClassName, $pTitle, $winStyle,
        [int32]150, [int32]150, [int32]$Width, [int32]$Height,
        [IntPtr]::Zero, [IntPtr]::Zero, $hModule, [IntPtr]::Zero
    )

    if ($Borderless -and $hwnd -ne [IntPtr]::Zero) {
        $fnDwmSetWindowAttribute = Get-NativeCall (Get-NativeExport $dwmapi 'DwmSetWindowAttribute') ([int32]) ([Type[]]@([IntPtr], [uint32], [IntPtr], [uint32]))
        $fnDwmExtendFrameIntoClientArea = Get-NativeCall (Get-NativeExport $dwmapi 'DwmExtendFrameIntoClientArea') ([int32]) ([Type[]]@([IntPtr], [IntPtr]))

        $pDark = New-NativeBlock 4; [System.Runtime.InteropServices.Marshal]::WriteInt32($pDark, 0, 1)
        [void]$fnDwmSetWindowAttribute.DynamicInvoke($hwnd, [uint32]20, $pDark, [uint32]4)
        $pCorner = New-NativeBlock 4; [System.Runtime.InteropServices.Marshal]::WriteInt32($pCorner, 0, 2)
        [void]$fnDwmSetWindowAttribute.DynamicInvoke($hwnd, [uint32]33, $pCorner, [uint32]4)
        $pBackdrop = New-NativeBlock 4; [System.Runtime.InteropServices.Marshal]::WriteInt32($pBackdrop, 0, 2)
        $hrB = [int32]$fnDwmSetWindowAttribute.DynamicInvoke($hwnd, [uint32]38, $pBackdrop, [uint32]4)
        if ($hrB -ne 0) { [void]$fnDwmSetWindowAttribute.DynamicInvoke($hwnd, [uint32]1029, $pDark, [uint32]4) }
        $pMargins = New-NativeBlock 16
        [System.Runtime.InteropServices.Marshal]::WriteInt32($pMargins, 0, -1); [System.Runtime.InteropServices.Marshal]::WriteInt32($pMargins, 4, -1); [System.Runtime.InteropServices.Marshal]::WriteInt32($pMargins, 8, -1); [System.Runtime.InteropServices.Marshal]::WriteInt32($pMargins, 12, -1)
        [void]$fnDwmExtendFrameIntoClientArea.DynamicInvoke($hwnd, $pMargins)
        Remove-NativeBlock $pDark; Remove-NativeBlock $pCorner; Remove-NativeBlock $pBackdrop; Remove-NativeBlock $pMargins
    }

    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pClassName)
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pTitle)

    return [PSCustomObject]@{
        Hwnd         = $hwnd
        HModule      = $hModule
        ClassName    = $className
        Title        = $Title
        Width        = $Width
        Height       = $Height
        Borderless   = [bool]$Borderless
        Headless     = $false
        Alive        = $true
        WindowShown  = $false
    }
}

# ==============================================================================
# SECTION 60: WINDOWS INPUT (UNIFIED MESSAGE DECODER)
# ==============================================================================

function global:Decode-WindowsInputMessage {
    param(
        $State,
        [IntPtr] $Hwnd,
        [IntPtr] $ScratchMsg,
        [IntPtr] $ScratchPoint,
        [IntPtr] $ScratchPaint,
        $FnBeginPaint,
        $FnScreenToClient,
        [ref]$PaintActive
    )

    # Event-scoped fields must not leak into the next Windows message.
    # Persistent state (pointer position/buttons, dimensions, Alive) is left intact.
    $State.KeyCode = 0
    $State.CharCode = [char]0
    $State.WheelDelta = 0
    $State.IsDoubleClick = $false

    $msgId = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchMsg, 8)
    switch ($msgId) {
        0x0010 { # WM_CLOSE
            $State.Alive = $false
            return $false
        }
        0x0002 { # WM_DESTROY
            $State.Alive = $false
            return $false
        }
        0x0014 { # WM_ERASEBKGND
            return $true
        }
        0x0005 { # WM_SIZE
            $lParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 24)
            $newWidth  = [int32]($lParam -band 0xFFFF)
            $newHeight = [int32](($lParam -shr 16) -band 0xFFFF)
            if ($newWidth -gt 0 -and $newHeight -gt 0 -and
                ($newWidth -ne $State.Width -or $newHeight -ne $State.Height)) {
                $State.Width = $newWidth
                $State.Height = $newHeight
                $State.ResizeSerial = [uint64]($State.ResizeSerial + 1)
                $State.RedrawSerial = [uint64]($State.RedrawSerial + 1)
            }
            return $true
        }
        0x000F { # WM_PAINT
            # A paint request means the application image must be redrawn, but
            # DirectPort does not start a paint transaction here.  The window's
            # DefWindowProc validates WM_PAINT during DispatchMessage; the
            # application redraws exactly once after WaitEvent returns.
            $State.RedrawSerial = [uint64]($State.RedrawSerial + 1)
            return $true
        }
        0x0200 { # WM_MOUSEMOVE
            $lParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 24)
            $wParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 16)
            $State.MouseX = [int16]($lParam -band 0xFFFF)
            $State.MouseY = [int16](($lParam -shr 16) -band 0xFFFF)
            $State.LeftDown = (($wParam -band 0x0001) -ne 0)
            return $true
        }
        0x0201 { # WM_LBUTTONDOWN
            $lParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 24)
            $State.MouseX = [int16]($lParam -band 0xFFFF)
            $State.MouseY = [int16](($lParam -shr 16) -band 0xFFFF)
            $State.LeftDown = $true
            return $true
        }
        0x0202 { # WM_LBUTTONUP
            $lParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 24)
            $State.MouseX = [int16]($lParam -band 0xFFFF)
            $State.MouseY = [int16](($lParam -shr 16) -band 0xFFFF)
            $State.LeftDown = $false
            return $true
        }
        0x0245 { # WM_POINTERUPDATE
            $lParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 24)
            $wParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 16)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($ScratchPoint, 0, [int16]($lParam -band 0xFFFF))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($ScratchPoint, 4, [int16](($lParam -shr 16) -band 0xFFFF))
            if ($null -ne $FnScreenToClient -and $Hwnd -ne [IntPtr]::Zero) {
                [void]$FnScreenToClient.DynamicInvoke($Hwnd, $ScratchPoint)
                $State.MouseX = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchPoint, 0)
                $State.MouseY = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchPoint, 4)
            }
            $State.LeftDown = ((($wParam -shr 16) -band 0x0004) -ne 0)
            return $true
        }
        0x0246 { # WM_POINTERDOWN
            $lParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 24)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($ScratchPoint, 0, [int16]($lParam -band 0xFFFF))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($ScratchPoint, 4, [int16](($lParam -shr 16) -band 0xFFFF))
            if ($null -ne $FnScreenToClient -and $Hwnd -ne [IntPtr]::Zero) {
                [void]$FnScreenToClient.DynamicInvoke($Hwnd, $ScratchPoint)
                $State.MouseX = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchPoint, 0)
                $State.MouseY = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchPoint, 4)
            }
            $State.LeftDown = $true
            return $true
        }
        0x0247 { # WM_POINTERUP
            $lParam = [System.Runtime.InteropServices.Marshal]::ReadInt64($ScratchMsg, 24)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($ScratchPoint, 0, [int16]($lParam -band 0xFFFF))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($ScratchPoint, 4, [int16](($lParam -shr 16) -band 0xFFFF))
            if ($null -ne $FnScreenToClient -and $Hwnd -ne [IntPtr]::Zero) {
                [void]$FnScreenToClient.DynamicInvoke($Hwnd, $ScratchPoint)
                $State.MouseX = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchPoint, 0)
                $State.MouseY = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchPoint, 4)
            }
            $State.LeftDown = $false
            return $true
        }
        0x0100 { # WM_KEYDOWN
            $State.KeyCode = [System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchMsg, 16)
            return $true
        }
        0x0102 { # WM_CHAR
            $State.CharCode = [char][System.Runtime.InteropServices.Marshal]::ReadInt32($ScratchMsg, 16)
            return $true
        }
    }
    return $true
}

# ==============================================================================
# SECTION 70: WINDOWS CANVAS & TEXT (DIRECT2D, DIRECTWRITE, WIC)
# ==============================================================================

function global:New-DirectPortCanvas {
    [CmdletBinding()]
    param(
        [int] $Width = 960,
        [int] $Height = 540,
        [string] $Title = 'DirectPort Window',
        [switch] $Borderless,
        [switch] $Headless,
        [switch] $SoftwareRendering,
        [switch] $EnableSharing
    )

    # 1. Initialize Windows Host
    $hostState = New-WindowsHost -Width $Width -Height $Height -Title $Title -Borderless:$Borderless -Headless:$Headless
    $hwnd = $hostState.Hwnd

    $user32   = Open-NativeLibrary "user32.dll"
    $kernel32 = Open-NativeLibrary "kernel32.dll"
    $d2d1     = Open-NativeLibrary "d2d1.dll"
    $dwrite   = Open-NativeLibrary "dwrite.dll"
    $ole32    = Open-NativeLibrary "ole32.dll"

    # 2. Native User32 bindings
    $fnGetMessage      = Get-NativeCall (Get-NativeExport $user32 'GetMessageW') ([int32]) ([Type[]]@([IntPtr],[IntPtr],[uint32],[uint32]))
    $fnPeekMessage     = Get-NativeCall (Get-NativeExport $user32 'PeekMessageW') ([bool]) ([Type[]]@([IntPtr],[IntPtr],[uint32],[uint32],[uint32]))
    $fnTranslateMsg    = Get-NativeCall (Get-NativeExport $user32 'TranslateMessage') ([bool]) ([Type[]]@([IntPtr]))
    $fnDispatchMsg     = Get-NativeCall (Get-NativeExport $user32 'DispatchMessageW') ([IntPtr]) ([Type[]]@([IntPtr]))
    $fnScreenToClient  = Get-NativeCall (Get-NativeExport $user32 'ScreenToClient') ([bool]) ([Type[]]@([IntPtr],[IntPtr]))
    $fnDestroyWindow   = Get-NativeCall (Get-NativeExport $user32 'DestroyWindow') ([bool]) ([Type[]]@([IntPtr]))
    $fnBeginPaint      = Get-NativeCall (Get-NativeExport $user32 'BeginPaint') ([IntPtr]) ([Type[]]@([IntPtr],[IntPtr]))
    $fnEndPaint        = Get-NativeCall (Get-NativeExport $user32 'EndPaint') ([bool]) ([Type[]]@([IntPtr],[IntPtr]))
    $fnReleaseCapture  = Get-NativeCall (Get-NativeExport $user32 'ReleaseCapture') ([bool]) ([Type[]]@())
    $fnSendMessageW    = Get-NativeCall (Get-NativeExport $user32 'SendMessageW') ([IntPtr]) ([Type[]]@([IntPtr],[uint32],[IntPtr],[IntPtr]))
    $fnShowWindow      = Get-NativeCall (Get-NativeExport $user32 'ShowWindow') ([bool]) ([Type[]]@([IntPtr],[int32]))

    # 3. Direct2D & DirectWrite Factories
    $pfnD2D1CreateFactory = Get-NativeExport $d2d1 "D2D1CreateFactory"
    $createD2DFactory = Get-NativeCall $pfnD2D1CreateFactory ([int32]) ([Type[]]@([uint32], [IntPtr], [IntPtr], [IntPtr]))
    $iidD2D1 = [Guid]::Parse("06152247-6f50-465a-9245-118bfd3b6007").ToByteArray()
    $pIidD2D1 = New-NativeBlock 16
    [System.Runtime.InteropServices.Marshal]::Copy($iidD2D1, 0, $pIidD2D1, 16)
    $pD2DFactoryOut = New-NativeBlock ([IntPtr]::Size)
    $d2dFactoryHr = [int32]$createD2DFactory.DynamicInvoke([uint32]0, $pIidD2D1, [IntPtr]::Zero, $pD2DFactoryOut)
    $pD2DFactory = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pD2DFactoryOut)
    Remove-NativeBlock $pIidD2D1
    Remove-NativeBlock $pD2DFactoryOut

    $pfnDWriteCreateFactory = Get-NativeExport $dwrite "DWriteCreateFactory"
    $createDWriteFactory = Get-NativeCall $pfnDWriteCreateFactory ([int32]) ([Type[]]@([uint32], [IntPtr], [IntPtr]))
    $iidDWrite = [Guid]::Parse("b859ee5a-d838-4b5b-a2e8-1adc7d93db48").ToByteArray()
    $pIidDWrite = New-NativeBlock 16
    [System.Runtime.InteropServices.Marshal]::Copy($iidDWrite, 0, $pIidDWrite, 16)
    $pDWriteFactoryOut = New-NativeBlock ([IntPtr]::Size)
    $dwriteFactoryHr = [int32]$createDWriteFactory.DynamicInvoke([uint32]0, $pIidDWrite, $pDWriteFactoryOut)
    $pDWriteFactory = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pDWriteFactoryOut)
    Remove-NativeBlock $pIidDWrite
    Remove-NativeBlock $pDWriteFactoryOut

    # 4. Render Target Initialization (Direct HWND RenderTarget or WIC Staging Target)
    $pWicFactory = [IntPtr]::Zero
    $pWicBitmap = [IntPtr]::Zero
    $pTarget = [IntPtr]::Zero
    $pPreviewTarget = [IntPtr]::Zero
    $fnPreviewBeginDraw = $null
    $fnPreviewEndDraw = $null
    $fnPreviewDrawBitmap = $null
    $fnPreviewCreateBitmapFromWic = $null
    $fnPreviewCheckWindowState = $null
    $targetHr = 0
    $previewTargetHr = 0

    $fnCoInitializeEx = Get-NativeCall (Get-NativeExport $ole32 'CoInitializeEx') ([int32]) ([Type[]]@([IntPtr], [uint32]))
    $coInitHr = [int32]$fnCoInitializeEx.DynamicInvoke([IntPtr]::Zero, [uint32]0) # COINIT_MULTITHREADED
    $coInitOwned = ($coInitHr -eq 0 -or $coInitHr -eq 1)

    # If sharing is requested OR in headless mode, create WIC staging bitmap
    if ($EnableSharing -or $Headless) {
        $fnCoCreateInstance = Get-NativeCall (Get-NativeExport $ole32 'CoCreateInstance') ([int32]) ([Type[]]@(
            [IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr]
        ))
        $pClsidWic = New-NativeBlock 16
        $pIidWic = New-NativeBlock 16
        [System.Runtime.InteropServices.Marshal]::Copy(
            [Guid]::Parse('cacaf262-9370-4615-a13b-9f5539da4c0a').ToByteArray(), 0, $pClsidWic, 16)
        [System.Runtime.InteropServices.Marshal]::Copy(
            [Guid]::Parse('ec5ec8a9-c395-4314-9c77-54d7a935ff70').ToByteArray(), 0, $pIidWic, 16)
        $pWicFactoryOut = New-NativeBlock ([IntPtr]::Size)
        $wicFactoryHr = [int32]$fnCoCreateInstance.DynamicInvoke(
            $pClsidWic, [IntPtr]::Zero, [uint32]1, $pIidWic, $pWicFactoryOut)
        $pWicFactory = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pWicFactoryOut)
        Remove-NativeBlock $pClsidWic
        Remove-NativeBlock $pIidWic
        Remove-NativeBlock $pWicFactoryOut

        $pGuidPbgra = New-NativeBlock 16
        [System.Runtime.InteropServices.Marshal]::Copy(
            [Guid]::Parse('6fddc324-4e03-4bfe-b185-3d77768dc910').ToByteArray(), 0, $pGuidPbgra, 16)
        $fnCreateWicBitmap = Get-ComCall $pWicFactory 17 ([int32]) ([Type[]]@(
            [IntPtr], [uint32], [uint32], [IntPtr], [uint32], [IntPtr]
        ))
        $pWicBitmapOut = New-NativeBlock ([IntPtr]::Size)
        $wicBitmapHr = [int32]$fnCreateWicBitmap.DynamicInvoke(
            $pWicFactory, [uint32]$Width, [uint32]$Height, $pGuidPbgra, [uint32]2, $pWicBitmapOut)
        $pWicBitmap = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pWicBitmapOut)
        Remove-NativeBlock $pGuidPbgra
        Remove-NativeBlock $pWicBitmapOut

        $wicRtProps = New-NativeBlock 28
        [System.Runtime.InteropServices.Marshal]::WriteInt32($wicRtProps, 0, $(if ($SoftwareRendering) { 1 } else { 0 }))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($wicRtProps, 4, 87)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($wicRtProps, 8, 1) # PREMULTIPLIED
        $pTargetOut = New-NativeBlock ([IntPtr]::Size)
        $fnCreateWicTarget = Get-ComCall $pD2DFactory 13 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [IntPtr]))
        $targetHr = [int32]$fnCreateWicTarget.DynamicInvoke($pD2DFactory, $pWicBitmap, $wicRtProps, $pTargetOut)
        $pTarget = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pTargetOut)
        Remove-NativeBlock $wicRtProps
        Remove-NativeBlock $pTargetOut

        if (-not $Headless -and $hwnd -ne [IntPtr]::Zero) {
            $previewRtProps = New-NativeBlock 28
            [System.Runtime.InteropServices.Marshal]::WriteInt32($previewRtProps, 0, $(if ($SoftwareRendering) { 1 } else { 0 }))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($previewRtProps, 4, 87)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($previewRtProps, 8, 1)
            $hwndProps = New-NativeBlock 24
            [System.Runtime.InteropServices.Marshal]::WriteIntPtr($hwndProps, 0, $hwnd)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($hwndProps, 8, $Width)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($hwndProps, 12, $Height)
            $pPreviewTargetOut = New-NativeBlock ([IntPtr]::Size)
            $fnCreateHwndTarget = Get-ComCall $pD2DFactory 14 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [IntPtr]))
            $previewTargetHr = [int32]$fnCreateHwndTarget.DynamicInvoke($pD2DFactory, $previewRtProps, $hwndProps, $pPreviewTargetOut)
            $pPreviewTarget = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pPreviewTargetOut)
            Remove-NativeBlock $previewRtProps
            Remove-NativeBlock $hwndProps
            Remove-NativeBlock $pPreviewTargetOut

            $fnPreviewBeginDraw = Get-ComCall $pPreviewTarget 48 ([void]) ([Type[]]@([IntPtr]))
            $fnPreviewEndDraw = Get-ComCall $pPreviewTarget 49 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr]))
            $fnPreviewDrawBitmap = Get-ComCall $pPreviewTarget 26 ([void]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [single], [uint32], [IntPtr]))
            $fnPreviewCreateBitmapFromWic = Get-ComCall $pPreviewTarget 5 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [IntPtr]))
            $fnPreviewCheckWindowState = Get-ComCall $pPreviewTarget 57 ([uint32]) ([Type[]]@([IntPtr]))
        }
    } else {
        # Direct HWND RenderTarget (Hardware-accelerated primary target, zero blit copy!)
        $hwndRtProps = New-NativeBlock 28
        [System.Runtime.InteropServices.Marshal]::WriteInt32($hwndRtProps, 0, $(if ($SoftwareRendering) { 1 } else { 0 }))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($hwndRtProps, 4, 87)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($hwndRtProps, 8, 1) # PREMULTIPLIED
        $hwndProps = New-NativeBlock 24
        [System.Runtime.InteropServices.Marshal]::WriteIntPtr($hwndProps, 0, $hwnd)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($hwndProps, 8, $Width)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($hwndProps, 12, $Height)
        $pTargetOut = New-NativeBlock ([IntPtr]::Size)
        $fnCreateHwndTarget = Get-ComCall $pD2DFactory 14 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [IntPtr]))
        $targetHr = [int32]$fnCreateHwndTarget.DynamicInvoke($pD2DFactory, $hwndRtProps, $hwndProps, $pTargetOut)
        $pTarget = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pTargetOut)
        Remove-NativeBlock $hwndRtProps
        Remove-NativeBlock $hwndProps
        Remove-NativeBlock $pTargetOut
        $pPreviewTarget = $pTarget
    }

    # 5. Direct2D Active Context Function Table
    $ctx = [PSCustomObject]@{
        Ptr              = $pTarget
        BeginDraw        = Get-ComCall $pTarget 48 ([void])  ([Type[]]@([IntPtr]))
        EndDraw          = Get-ComCall $pTarget 49 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr]))
        Clear            = Get-ComCall $pTarget 47 ([void])  ([Type[]]@([IntPtr], [IntPtr]))
        FillRect         = Get-ComCall $pTarget 17 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr]))
        DrawRect         = Get-ComCall $pTarget 16 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [single], [IntPtr]))
        FillRoundedRect  = Get-ComCall $pTarget 19 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr]))
        DrawRoundedRect  = Get-ComCall $pTarget 18 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [single], [IntPtr]))
        DrawText         = Get-ComCall $pTarget 27 ([void])  ([Type[]]@([IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr], [IntPtr], [uint32], [uint32]))
        DrawBitmap       = Get-ComCall $pTarget 26 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [single], [uint32], [IntPtr]))
        CreateSolidBrush = Get-ComCall $pTarget 8  ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [IntPtr]))
    }

    $fnCreateTextFormat  = Get-ComCall $pDWriteFactory 15 ([int32]) ([Type[]]@([IntPtr],[IntPtr],[IntPtr],[uint32],[uint32],[uint32],[single],[IntPtr],[IntPtr]))
    $fnCreateTextLayout  = Get-ComCall $pDWriteFactory 18 ([int32]) ([Type[]]@([IntPtr],[IntPtr],[uint32],[IntPtr],[single],[single],[IntPtr]))
    $fnCreateCompRT      = Get-ComCall $pTarget 12 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [IntPtr], [uint32], [IntPtr]))

    # Persistent Reusable Native Scratch Blocks (Hot-path zero allocations!)
    $scratchColor   = New-NativeBlock 16
    $scratchRect    = New-NativeBlock 16
    $scratchRRect   = New-NativeBlock 24
    $scratchMsg     = New-NativeBlock 48
    $scratchPoint   = New-NativeBlock 8
    $scratchPaint   = New-NativeBlock 72
    $scratchOut     = New-NativeBlock ([IntPtr]::Size)
    $scratchMetrics = New-NativeBlock 64

    $brushCache = [System.Collections.Generic.Dictionary[int32, IntPtr]]::new()
    $textFormatCache = [System.Collections.Generic.Dictionary[string, IntPtr]]::new()
    $strCache = [System.Collections.Generic.Dictionary[string, IntPtr]]::new()
    $metricsCache = [System.Collections.Generic.Dictionary[string, object]]::new()
    $fnGetMetrics = $null

    $windowShown = $false
    $paintActive = $false

    $stateObj = [Windows.Graphics.CanvasWindowState]::new()
    $stateObj.Alive = $true
    $stateObj.Width = $Width
    $stateObj.Height = $Height
    $stateObj.ResizeSerial = [uint64]0
    $stateObj.RedrawSerial = [uint64]0

    # 6. Optional Sharing Subsystem (DP-ARCH-005 Section 20: Detached from default Canvas!)
    $shareHandle = $null
    if ($EnableSharing) {
        $shareHandle = Attach-WindowsCanvasShareProducer -Width $Width -Height $Height -WicBitmap $pWicBitmap
    }

    $diagnostics = [PSCustomObject]@{
        D2DFactoryHResult      = $d2dFactoryHr
        DWriteFactoryHResult   = $dwriteFactoryHr
        D3D12DeviceHResult     = if ($shareHandle) { $shareHandle.DeviceHr } else { [int32]0 }
        D3D12ResourceHResult   = if ($shareHandle) { $shareHandle.ResourceHr } else { [int32]0 }
        RenderTargetHResult    = $targetHr
        PreviewTargetHResult   = $previewTargetHr
        AssociatedHwnd         = $hwnd
        SharedTextureName      = if ($shareHandle) { $shareHandle.TextureName } else { $null }
        SharedFenceName        = if ($shareHandle) { $shareHandle.FenceName } else { $null }
        ProducerManifestName   = if ($shareHandle) { $shareHandle.ManifestName } else { $null }
        AdapterLuid            = if ($shareHandle) { $shareHandle.AdapterLuid } else { [uint64]0 }
        RowPitch               = if ($shareHandle) { $shareHandle.RowPitch } else { [uint32]0 }
        MappedAddress          = if ($shareHandle) { $shareHandle.MappedAddress } else { [IntPtr]::Zero }
        LastPresentHResult     = [int32]0
        LastPreviewHResult     = [int32]0
        PresentCount           = [uint64]0
        WindowState            = [uint32]0
        WindowShown            = $false
        SharingEnabled         = [bool]$EnableSharing
    }

    $canvas = [PSCustomObject]@{
        PSTypeName        = 'Windows.Graphics.Canvas'
        Hwnd              = $hwnd
        Target            = $pTarget
        D2DFactory        = $pD2DFactory
        DWriteFactory     = $pDWriteFactory
        D3D12Device       = if ($shareHandle) { $shareHandle.Device } else { [IntPtr]::Zero }
        SharedResource    = if ($shareHandle) { $shareHandle.Resource } else { [IntPtr]::Zero }
        SharedFence       = if ($shareHandle) { $shareHandle.Fence } else { [IntPtr]::Zero }
        SharedTextureName = if ($shareHandle) { $shareHandle.TextureName } else { $null }
        SharedFenceName   = if ($shareHandle) { $shareHandle.FenceName } else { $null }
        ManifestName      = if ($shareHandle) { $shareHandle.ManifestName } else { $null }
        FrameCount        = [uint64]0
        Alive             = $true
        Width             = $Width
        Height            = $Height
        Diagnostics       = $diagnostics
    }

    $getArgbBytes = {
        param([object] $c)
        if ($c -is [uint32] -or $c -is [uint64]) {
            return [System.BitConverter]::GetBytes([uint32]$c)
        }
        $val = [int64]$c
        return [System.BitConverter]::GetBytes([int32]$val)
    }

    $getBrush = {
        param([object] $argb)
        $bArr = & $getArgbBytes $argb
        $key = [System.BitConverter]::ToInt32($bArr, 0)
        if ($brushCache.ContainsKey($key)) {
            return $brushCache[$key]
        }
        $bByte, $gByte, $rByte, $aByte = $bArr
        $b = [single]($bByte / 255.0)
        $g = [single]($gByte / 255.0)
        $r = [single]($rByte / 255.0)
        $a = [single]($aByte / 255.0)

        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 0,  [System.BitConverter]::SingleToInt32Bits($r))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 4,  [System.BitConverter]::SingleToInt32Bits($g))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 8,  [System.BitConverter]::SingleToInt32Bits($b))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 12, [System.BitConverter]::SingleToInt32Bits($a))

        $null = $ctx.CreateSolidBrush.DynamicInvoke($ctx.Ptr, $scratchColor, [IntPtr]::Zero, $scratchOut)
        $brush = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($scratchOut)
        $brushCache[$key] = $brush
        return $brush
    }.GetNewClosure()

    # --- RETAINED MODE BUFFER API ---

    $canvas | Add-Member -MemberType ScriptMethod -Name 'CreateCompatibleTarget' -Value {
        $pOut = New-NativeBlock ([IntPtr]::Size)
        $hr = [int32]$fnCreateCompRT.DynamicInvoke($pTarget, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, [uint32]0, $pOut)
        $ptr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pOut)
        Remove-NativeBlock $pOut
        if ($hr -ne 0) { throw "CreateCompatibleRenderTarget HRESULT 0x$($hr.ToString('X8'))" }
        return $ptr
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'SetTarget' -Value {
        param([IntPtr]$newTarget)
        $ctx.Ptr = if ($newTarget -eq [IntPtr]::Zero) { $pTarget } else { $newTarget }
        $ctx.BeginDraw         = Get-ComCall $ctx.Ptr 48 ([void])  ([Type[]]@([IntPtr]))
        $ctx.EndDraw           = Get-ComCall $ctx.Ptr 49 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr]))
        $ctx.Clear             = Get-ComCall $ctx.Ptr 47 ([void])  ([Type[]]@([IntPtr], [IntPtr]))
        $ctx.FillRect          = Get-ComCall $ctx.Ptr 17 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr]))
        $ctx.DrawRect          = Get-ComCall $ctx.Ptr 16 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [single], [IntPtr]))
        $ctx.FillRoundedRect   = Get-ComCall $ctx.Ptr 19 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr]))
        $ctx.DrawRoundedRect   = Get-ComCall $ctx.Ptr 18 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [single], [IntPtr]))
        $ctx.DrawText          = Get-ComCall $ctx.Ptr 27 ([void])  ([Type[]]@([IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr], [IntPtr], [uint32], [uint32]))
        $ctx.DrawBitmap        = Get-ComCall $ctx.Ptr 26 ([void])  ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [single], [uint32], [IntPtr]))
        $ctx.CreateSolidBrush  = Get-ComCall $ctx.Ptr 8  ([int32]) ([Type[]]@([IntPtr], [IntPtr], [IntPtr], [IntPtr]))
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'GetBitmap' -Value {
        param([IntPtr]$compTarget)
        $fnGet = Get-ComCall $compTarget 57 ([int32]) ([Type[]]@([IntPtr], [IntPtr]))
        $pOut = New-NativeBlock ([IntPtr]::Size)
        $hr = [int32]$fnGet.DynamicInvoke($compTarget, $pOut)
        $ptr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pOut)
        Remove-NativeBlock $pOut
        if ($hr -ne 0) { throw "GetBitmap HRESULT 0x$($hr.ToString('X8'))" }
        return $ptr
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'DrawBitmap' -Value {
        param([IntPtr]$bitmap, [single]$opacity = 1.0, [uint32]$interpolationMode = 1)
        [void]$ctx.DrawBitmap.DynamicInvoke($ctx.Ptr, $bitmap, [IntPtr]::Zero, $opacity, $interpolationMode, [IntPtr]::Zero)
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'ReleaseResource' -Value {
        param([IntPtr]$ptr)
        if ($ptr -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($ptr) }
    }.GetNewClosure()

    # --- GEOMETRY API ---

    $canvas | Add-Member -MemberType ScriptMethod -Name 'BeginDraw' -Value {
        param([object] $clearArgb = 0xFF000000)
        $bArr = & $getArgbBytes $clearArgb
        $bByte, $gByte, $rByte, $aByte = $bArr
        $b = [single]($bByte / 255.0)
        $g = [single]($gByte / 255.0)
        $r = [single]($rByte / 255.0)
        $a = [single]($aByte / 255.0)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 0,  [System.BitConverter]::SingleToInt32Bits($r))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 4,  [System.BitConverter]::SingleToInt32Bits($g))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 8,  [System.BitConverter]::SingleToInt32Bits($b))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchColor, 12, [System.BitConverter]::SingleToInt32Bits($a))

        [void]$ctx.BeginDraw.DynamicInvoke($ctx.Ptr)
        [void]$ctx.Clear.DynamicInvoke($ctx.Ptr, $scratchColor)
        return $true
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'EndDraw' -Value {
        $hr = [int32]$ctx.EndDraw.DynamicInvoke($ctx.Ptr, [IntPtr]::Zero, [IntPtr]::Zero)
        $diagnostics.LastPresentHResult = $hr
        if ($paintActive) {
            [void]$fnEndPaint.DynamicInvoke($hwnd, $scratchPaint)
            $paintActive = $false
        }
        return ($hr -eq 0)
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'Present' -Value {
        if (-not $this.EndDraw()) { return $false }

        # If WIC staging target was used and HWND preview target is present
        if ($pWicBitmap -ne [IntPtr]::Zero -and $pPreviewTarget -ne [IntPtr]::Zero -and -not $Headless) {
            $pPreviewBitmapOut = New-NativeBlock ([IntPtr]::Size)
            $previewBitmapHr = [int32]$fnPreviewCreateBitmapFromWic.DynamicInvoke(
                $pPreviewTarget, $pWicBitmap, [IntPtr]::Zero, $pPreviewBitmapOut)
            $pPreviewBitmap = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pPreviewBitmapOut)
            Remove-NativeBlock $pPreviewBitmapOut
            if ($previewBitmapHr -eq 0 -and $pPreviewBitmap -ne [IntPtr]::Zero) {
                [void]$fnPreviewBeginDraw.DynamicInvoke($pPreviewTarget)
                [void]$fnPreviewDrawBitmap.DynamicInvoke(
                    $pPreviewTarget, $pPreviewBitmap, [IntPtr]::Zero, [single]1.0, [uint32]1, [IntPtr]::Zero)
                $previewEndHr = [int32]$fnPreviewEndDraw.DynamicInvoke($pPreviewTarget, [IntPtr]::Zero, [IntPtr]::Zero)
                $diagnostics.LastPreviewHResult = $previewEndHr
                [void][System.Runtime.InteropServices.Marshal]::Release($pPreviewBitmap)
            }
        }

        if (-not $Headless -and -not $windowShown -and $hwnd -ne [IntPtr]::Zero) {
            [void]$fnShowWindow.DynamicInvoke($hwnd, [int32]1)
            $windowShown = $true
            $diagnostics.WindowShown = $true
        }

        # If D3D12 IPC sharing is active, update texture and signal fence
        if ($null -ne $shareHandle) {
            $copyHr = [int32]$shareHandle.CopyPixels($pWicBitmap)
            if ($copyHr -ne 0) {
                $diagnostics.LastPresentHResult = $copyHr
                return $false
            }
            $this.FrameCount = [uint64]($this.FrameCount + 1)
            $signalHr = [int32]$shareHandle.SignalFence($this.FrameCount)
            if ($signalHr -ne 0) {
                $diagnostics.LastPresentHResult = $signalHr
                return $false
            }
        }

        $diagnostics.PresentCount = [uint64]($diagnostics.PresentCount + 1)
        return $true
    }.GetNewClosure()

    # Normative DP-ARCH-005 Stage 6: Publish is compatibility alias for Present
    $canvas | Add-Member -MemberType ScriptMethod -Name 'Publish' -Value {
        return $this.Present()
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'FillRect' -Value {
        param([single]$x, [single]$y, [single]$w, [single]$h, [object]$argb, [single]$radius = 0.0)
        $brush = & $getBrush $argb
        if ($radius -gt 0.0) {
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 0,  [System.BitConverter]::SingleToInt32Bits($x))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 4,  [System.BitConverter]::SingleToInt32Bits($y))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 8,  [System.BitConverter]::SingleToInt32Bits([single]($x + $w)))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 12, [System.BitConverter]::SingleToInt32Bits([single]($y + $h)))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 16, [System.BitConverter]::SingleToInt32Bits($radius))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 20, [System.BitConverter]::SingleToInt32Bits($radius))
            $ctx.FillRoundedRect.DynamicInvoke($ctx.Ptr, $scratchRRect, $brush)
        } else {
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 0,  [System.BitConverter]::SingleToInt32Bits($x))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 4,  [System.BitConverter]::SingleToInt32Bits($y))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 8,  [System.BitConverter]::SingleToInt32Bits([single]($x + $w)))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 12, [System.BitConverter]::SingleToInt32Bits([single]($y + $h)))
            $ctx.FillRect.DynamicInvoke($ctx.Ptr, $scratchRect, $brush)
        }
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'DrawRect' -Value {
        param([single]$x, [single]$y, [single]$w, [single]$h, [object]$argb, [single]$strokeWidth = 1.0, [single]$radius = 0.0)
        $brush = & $getBrush $argb
        if ($radius -gt 0.0) {
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 0,  [System.BitConverter]::SingleToInt32Bits($x))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 4,  [System.BitConverter]::SingleToInt32Bits($y))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 8,  [System.BitConverter]::SingleToInt32Bits([single]($x + $w)))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 12, [System.BitConverter]::SingleToInt32Bits([single]($y + $h)))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 16, [System.BitConverter]::SingleToInt32Bits($radius))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRRect, 20, [System.BitConverter]::SingleToInt32Bits($radius))
            $ctx.DrawRoundedRect.DynamicInvoke($ctx.Ptr, $scratchRRect, $brush, $strokeWidth, [IntPtr]::Zero)
        } else {
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 0,  [System.BitConverter]::SingleToInt32Bits($x))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 4,  [System.BitConverter]::SingleToInt32Bits($y))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 8,  [System.BitConverter]::SingleToInt32Bits([single]($x + $w)))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 12, [System.BitConverter]::SingleToInt32Bits([single]($y + $h)))
            $ctx.DrawRect.DynamicInvoke($ctx.Ptr, $scratchRect, $brush, $strokeWidth, [IntPtr]::Zero)
        }
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'DrawText' -Value {
        param([string]$text, [single]$x, [single]$y, [single]$maxWidth, [single]$maxHeight, [object]$argb, [single]$fontSize = 14.0, [string]$fontFamily = "Segoe UI", [bool]$bold = $false, [object]$alignment = 0)
        if ([string]::IsNullOrEmpty($text)) { return }
        $brush = & $getBrush $argb

        $weight = if ($bold) { [uint32]700 } else { [uint32]400 }
        $fmtKey = "$fontFamily-$fontSize-$bold"
        if ($textFormatCache.ContainsKey($fmtKey)) {
            $pFormat = $textFormatCache[$fmtKey]
        } else {
            if (-not $strCache.ContainsKey($fontFamily)) {
                $strCache[$fontFamily] = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($fontFamily)
            }
            $pFont = $strCache[$fontFamily]
            $locKey = "en-us"
            if (-not $strCache.ContainsKey($locKey)) {
                $strCache[$locKey] = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($locKey)
            }
            $pLoc = $strCache[$locKey]

            $null = $fnCreateTextFormat.DynamicInvoke($pDWriteFactory, $pFont, [IntPtr]::Zero, $weight, [uint32]0, [uint32]5, $fontSize, $pLoc, $scratchOut)
            $pFormat = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($scratchOut)
            $textFormatCache[$fmtKey] = $pFormat
        }

        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 0,  [System.BitConverter]::SingleToInt32Bits($x))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 4,  [System.BitConverter]::SingleToInt32Bits($y))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 8,  [System.BitConverter]::SingleToInt32Bits([single]($x + $maxWidth)))
        [System.Runtime.InteropServices.Marshal]::WriteInt32($scratchRect, 12, [System.BitConverter]::SingleToInt32Bits([single]($y + $maxHeight)))

        if (-not $strCache.ContainsKey($text)) {
            $strCache[$text] = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($text)
        }
        $pStr = $strCache[$text]
        $ctx.DrawText.DynamicInvoke($ctx.Ptr, $pStr, [uint32]$text.Length, $pFormat, $scratchRect, $brush, [uint32]0, [uint32]0)
    }.GetNewClosure()

    # DP-ARCH-005 Stage 8: Reusable scratch metrics & cached delegate stub
    $canvas | Add-Member -MemberType ScriptMethod -Name 'MeasureText' -Value {
        param([string]$text, [single]$fontSize = 14.0, [string]$fontFamily = "Segoe UI", [bool]$bold = $false)
        $m = [Windows.Graphics.TextMetrics]::new()
        if ([string]::IsNullOrEmpty($text)) {
            $m.Width = 0.0; $m.Height = $fontSize * 1.2
            return $m
        }

        $weight = if ($bold) { [uint32]700 } else { [uint32]400 }
        $fmtKey = "$fontFamily-$fontSize-$bold"
        $cacheKey = "$fmtKey|$text"
        if ($metricsCache.ContainsKey($cacheKey)) {
            $cached = $metricsCache[$cacheKey]
            $m.Width = $cached.Width
            $m.Height = $cached.Height
            return $m
        }

        if ($textFormatCache.ContainsKey($fmtKey)) {
            $pFormat = $textFormatCache[$fmtKey]
        } else {
            if (-not $strCache.ContainsKey($fontFamily)) {
                $strCache[$fontFamily] = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($fontFamily)
            }
            $pFont = $strCache[$fontFamily]
            $locKey = "en-us"
            if (-not $strCache.ContainsKey($locKey)) {
                $strCache[$locKey] = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($locKey)
            }
            $pLoc = $strCache[$locKey]

            $null = $fnCreateTextFormat.DynamicInvoke($pDWriteFactory, $pFont, [IntPtr]::Zero, $weight, [uint32]0, [uint32]5, $fontSize, $pLoc, $scratchOut)
            $pFormat = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($scratchOut)
            $textFormatCache[$fmtKey] = $pFormat
        }

        if (-not $strCache.ContainsKey($text)) {
            $strCache[$text] = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($text)
        }
        $pStr = $strCache[$text]

        $null = $fnCreateTextLayout.DynamicInvoke($pDWriteFactory, $pStr, [uint32]$text.Length, $pFormat, [single]10000.0, [single]10000.0, $scratchOut)
        $layout = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($scratchOut)

        if ($null -eq $fnGetMetrics) {
            $fnGetMetrics = Get-ComCall $layout 60 ([int32]) ([Type[]]@([IntPtr], [IntPtr]))
        }
        $null = $fnGetMetrics.DynamicInvoke($layout, $scratchMetrics)

        $w1 = [System.BitConverter]::ToSingle([System.BitConverter]::GetBytes([System.Runtime.InteropServices.Marshal]::ReadInt32($scratchMetrics, 8)), 0)
        $w2 = [System.BitConverter]::ToSingle([System.BitConverter]::GetBytes([System.Runtime.InteropServices.Marshal]::ReadInt32($scratchMetrics, 12)), 0)
        $h  = [System.BitConverter]::ToSingle([System.BitConverter]::GetBytes([System.Runtime.InteropServices.Marshal]::ReadInt32($scratchMetrics, 16)), 0)

        if ($layout -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($layout) }

        $m.Width = [Math]::Max($w1, $w2)
        $m.Height = if ($h -gt 0.0) { $h } else { $fontSize * 1.2 }
        $metricsCache[$cacheKey] = @{ Width = $m.Width; Height = $m.Height }
        return $m
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'Minimize' -Value {
        if ($hwnd -ne [IntPtr]::Zero) {
            [void]$fnShowWindow.DynamicInvoke($hwnd, [int32]6)
        }
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'DragWindow' -Value {
        if ($hwnd -ne [IntPtr]::Zero) {
            [void]$fnReleaseCapture.DynamicInvoke()
            [void]$fnSendMessageW.DynamicInvoke($hwnd, [uint32]0x00A1, [IntPtr]2, [IntPtr]::Zero)
        }
    }.GetNewClosure()

    # DP-ARCH-005 Stage 7: Unified message decoder calls
    $canvas | Add-Member -MemberType ScriptMethod -Name 'WaitEvent' -Value {
        if ($hwnd -eq [IntPtr]::Zero) {
            $stateObj.Alive = $false
            $this.Alive = $false
            return $null
        }

        $ret = [int32]$fnGetMessage.DynamicInvoke($scratchMsg, [IntPtr]::Zero, [uint32]0, [uint32]0)
        if ($ret -le 0) {
            $stateObj.Alive = $false
            $this.Alive = $false
            return $null
        }

        $continue = Decode-WindowsInputMessage -State $stateObj -Hwnd $hwnd -ScratchMsg $scratchMsg -ScratchPoint $scratchPoint -ScratchPaint $scratchPaint -FnBeginPaint $fnBeginPaint -FnScreenToClient $fnScreenToClient -PaintActive ([ref]$paintActive)
        if (-not $continue) {
            $this.Alive = $false
            return $null
        }

        [void]$fnTranslateMsg.DynamicInvoke($scratchMsg)
        [void]$fnDispatchMsg.DynamicInvoke($scratchMsg)
        return $stateObj
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'Pump' -Value {
        param([uint32] $waitMilliseconds = 0)
        if ($hwnd -eq [IntPtr]::Zero) { return $stateObj }

        while ([bool]$fnPeekMessage.DynamicInvoke($scratchMsg, [IntPtr]::Zero, [uint32]0, [uint32]0, [uint32]1)) {
            $continue = Decode-WindowsInputMessage -State $stateObj -Hwnd $hwnd -ScratchMsg $scratchMsg -ScratchPoint $scratchPoint -ScratchPaint $scratchPaint -FnBeginPaint $fnBeginPaint -FnScreenToClient $fnScreenToClient -PaintActive ([ref]$paintActive)
            if (-not $continue) {
                $this.Alive = $false
                break
            }
            [void]$fnTranslateMsg.DynamicInvoke($scratchMsg)
            [void]$fnDispatchMsg.DynamicInvoke($scratchMsg)
        }
        return $stateObj
    }.GetNewClosure()

    $canvas | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
        if (-not $this.Alive) { return }
        $this.Alive = $false
        $stateObj.Alive = $false

        if ($brushCache) {
            foreach ($b in $brushCache.Values) {
                if ($b -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($b) }
            }
            $brushCache.Clear()
        }
        if ($textFormatCache) {
            foreach ($f in $textFormatCache.Values) {
                if ($f -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($f) }
            }
            $textFormatCache.Clear()
        }
        if ($strCache) {
            foreach ($s in $strCache.Values) {
                if ($s -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($s) }
            }
            $strCache.Clear()
        }

        if ($paintActive -and $hwnd -ne [IntPtr]::Zero) {
            [void]$fnEndPaint.DynamicInvoke($hwnd, $scratchPaint)
            $paintActive = $false
        }
        if ($hwnd -ne [IntPtr]::Zero) { [void]$fnDestroyWindow.DynamicInvoke($hwnd) }

        if ($pPreviewTarget -ne [IntPtr]::Zero -and $pPreviewTarget -ne $pTarget) { [void][System.Runtime.InteropServices.Marshal]::Release($pPreviewTarget) }
        if ($pTarget -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pTarget) }
        if ($pWicBitmap -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pWicBitmap) }
        if ($pWicFactory -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pWicFactory) }
        if ($pD2DFactory -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pD2DFactory) }
        if ($pDWriteFactory -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pDWriteFactory) }

        if ($null -ne $shareHandle) { $shareHandle.Dispose() }

        if ($scratchColor -ne [IntPtr]::Zero)   { Remove-NativeBlock $scratchColor }
        if ($scratchRect -ne [IntPtr]::Zero)    { Remove-NativeBlock $scratchRect }
        if ($scratchRRect -ne [IntPtr]::Zero)   { Remove-NativeBlock $scratchRRect }
        if ($scratchMsg -ne [IntPtr]::Zero)     { Remove-NativeBlock $scratchMsg }
        if ($scratchPoint -ne [IntPtr]::Zero)   { Remove-NativeBlock $scratchPoint }
        if ($scratchPaint -ne [IntPtr]::Zero)   { Remove-NativeBlock $scratchPaint }
        if ($scratchOut -ne [IntPtr]::Zero)     { Remove-NativeBlock $scratchOut }
        if ($scratchMetrics -ne [IntPtr]::Zero) { Remove-NativeBlock $scratchMetrics }

        if ($coInitOwned) {
            $fnCoUninitialize = Get-NativeCall (Get-NativeExport $ole32 'CoUninitialize') ([void]) ([Type[]]@())
            [void]$fnCoUninitialize.DynamicInvoke()
        }
    }.GetNewClosure()

    return $canvas
}

# ==============================================================================
# SECTION 80: WINDOWS OPTIONAL SHARING / D3D12 PRODUCER (DETACHED FROM CANVAS)
# ==============================================================================

function global:Attach-WindowsCanvasShareProducer {
    [CmdletBinding()]
    param(
        [int] $Width,
        [int] $Height,
        [IntPtr] $WicBitmap
    )

    $d3d12    = Open-NativeLibrary "d3d12.dll"
    $kernel32 = Open-NativeLibrary "kernel32.dll"

    # D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, IID_ID3D12Device, &device)
    $fnD3D12CreateDevice = Get-NativeCall (Get-NativeExport $d3d12 'D3D12CreateDevice') ([int32]) ([Type[]]@([IntPtr], [int32], [IntPtr], [IntPtr]))
    $pIidD3D12Device = New-NativeBlock 16
    [System.Runtime.InteropServices.Marshal]::Copy(
        [Guid]::Parse('189819f1-1db6-4b57-be54-1821339b85f7').ToByteArray(), 0, $pIidD3D12Device, 16)
    $pDeviceOut = New-NativeBlock ([IntPtr]::Size)
    $d3d12DeviceHr = [int32]$fnD3D12CreateDevice.DynamicInvoke([IntPtr]::Zero, [int32]0xB000, $pIidD3D12Device, $pDeviceOut)
    $pD3D12Device = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pDeviceOut)
    Remove-NativeBlock $pIidD3D12Device
    Remove-NativeBlock $pDeviceOut
    if ($d3d12DeviceHr -ne 0 -or $pD3D12Device -eq [IntPtr]::Zero) {
        throw ("D3D12CreateDevice failed: 0x{0:X8}" -f [uint32]$d3d12DeviceHr)
    }

    # D3D12_HEAP_PROPERTIES
    $heapProps = New-NativeBlock 32
    [System.Runtime.InteropServices.Marshal]::WriteInt32($heapProps, 0, 4)  # CUSTOM
    [System.Runtime.InteropServices.Marshal]::WriteInt32($heapProps, 4, 2)  # WRITE_COMBINE
    [System.Runtime.InteropServices.Marshal]::WriteInt32($heapProps, 8, 1)  # L0
    [System.Runtime.InteropServices.Marshal]::WriteInt32($heapProps, 12, 0)
    [System.Runtime.InteropServices.Marshal]::WriteInt32($heapProps, 16, 0)

    # D3D12_RESOURCE_DESC
    $resDesc = New-NativeBlock 56
    [System.Runtime.InteropServices.Marshal]::WriteInt32($resDesc, 0, 2)                 # TEXTURE2D
    [System.Runtime.InteropServices.Marshal]::WriteInt64($resDesc, 8, 0)                 # Alignment = default
    [System.Runtime.InteropServices.Marshal]::WriteInt64($resDesc, 16, [int64]$Width)
    [System.Runtime.InteropServices.Marshal]::WriteInt32($resDesc, 24, $Height)
    [System.Runtime.InteropServices.Marshal]::WriteInt16($resDesc, 28, 1)
    [System.Runtime.InteropServices.Marshal]::WriteInt16($resDesc, 30, 1)
    [System.Runtime.InteropServices.Marshal]::WriteInt32($resDesc, 32, 87)                # B8G8R8A8_UNORM
    [System.Runtime.InteropServices.Marshal]::WriteInt32($resDesc, 36, 1)
    [System.Runtime.InteropServices.Marshal]::WriteInt32($resDesc, 40, 0)
    [System.Runtime.InteropServices.Marshal]::WriteInt32($resDesc, 44, 1)                 # ROW_MAJOR
    [System.Runtime.InteropServices.Marshal]::WriteInt32($resDesc, 48, 0x10)              # ALLOW_CROSS_ADAPTER

    $pIidResource = New-NativeBlock 16
    [System.Runtime.InteropServices.Marshal]::Copy(
        [Guid]::Parse('696442be-a72e-4059-bc79-5b5c98040fad').ToByteArray(), 0, $pIidResource, 16)
    $pResourceOut = New-NativeBlock ([IntPtr]::Size)
    $fnCreateCommitted = Get-ComCall $pD3D12Device 27 ([int32]) ([Type[]]@(
        [IntPtr], [IntPtr], [int32], [IntPtr], [int32], [IntPtr], [IntPtr], [IntPtr]
    ))
    $d3d12ResourceHr = [int32]$fnCreateCommitted.DynamicInvoke(
        $pD3D12Device,
        $heapProps,
        [int32]0x21,             # SHARED | SHARED_CROSS_ADAPTER
        $resDesc,
        [int32]0,                # COMMON
        [IntPtr]::Zero,
        $pIidResource,
        $pResourceOut
    )
    $pResource = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pResourceOut)
    Remove-NativeBlock $pIidResource
    Remove-NativeBlock $pResourceOut
    Remove-NativeBlock $heapProps
    Remove-NativeBlock $resDesc
    if ($d3d12ResourceHr -ne 0 -or $pResource -eq [IntPtr]::Zero) {
        throw ("D3D12 shared SysRAM CreateCommittedResource failed: 0x{0:X8}" -f [uint32]$d3d12ResourceHr)
    }

    # Persistent CPU map
    $fnResourceMap = Get-ComCall $pResource 8 ([int32]) ([Type[]]@([IntPtr], [uint32], [IntPtr], [IntPtr]))
    $fnResourceUnmap = Get-ComCall $pResource 9 ([void]) ([Type[]]@([IntPtr], [uint32], [IntPtr]))
    $pMappedDataOut = New-NativeBlock ([IntPtr]::Size)
    $mapHr = [int32]$fnResourceMap.DynamicInvoke($pResource, [uint32]0, [IntPtr]::Zero, $pMappedDataOut)
    $pMappedData = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pMappedDataOut)
    Remove-NativeBlock $pMappedDataOut
    if ($mapHr -ne 0 -or $pMappedData -eq [IntPtr]::Zero) {
        throw ("ID3D12Resource::Map failed: 0x{0:X8}" -f [uint32]$mapHr)
    }
    $rowPitch = [uint32]((($Width * 4) + 255) -band (-bnot 255))
    $bufferSize = [uint32]([uint64]$rowPitch * [uint64]$Height)

    # Publish named NT handles
    $pidNum = [uint32]$PID
    $texName = "Global\DirectPortTexture_$pidNum"
    $fenceName = "Global\DirectPortFence_$pidNum"

    $fnCreateSharedHandle = Get-ComCall $pD3D12Device 31 ([int32]) ([Type[]]@(
        [IntPtr], [IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr]
    ))
    $pTexName = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($texName)
    $pSharedTexHandleOut = New-NativeBlock ([IntPtr]::Size)
    $shareTextureHr = [int32]$fnCreateSharedHandle.DynamicInvoke(
        $pD3D12Device, $pResource, [IntPtr]::Zero, [uint32]0x10000000, $pTexName, $pSharedTexHandleOut)
    $hSharedTexture = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pSharedTexHandleOut)
    Remove-NativeBlock $pSharedTexHandleOut
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pTexName)

    # Shared cross-adapter fence
    $pIidFence = New-NativeBlock 16
    [System.Runtime.InteropServices.Marshal]::Copy(
        [Guid]::Parse('0a753dcf-c4d8-4b91-adf6-be5a60d95a76').ToByteArray(), 0, $pIidFence, 16)
    $pFenceOut = New-NativeBlock ([IntPtr]::Size)
    $fnCreateFence = Get-ComCall $pD3D12Device 36 ([int32]) ([Type[]]@(
        [IntPtr], [uint64], [int32], [IntPtr], [IntPtr]
    ))
    $createFenceHr = [int32]$fnCreateFence.DynamicInvoke($pD3D12Device, [uint64]0, [int32]0x3, $pIidFence, $pFenceOut)
    $pFence = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pFenceOut)
    Remove-NativeBlock $pIidFence
    Remove-NativeBlock $pFenceOut

    $pFenceName = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($fenceName)
    $pSharedFenceHandleOut = New-NativeBlock ([IntPtr]::Size)
    $shareFenceHr = [int32]$fnCreateSharedHandle.DynamicInvoke(
        $pD3D12Device, $pFence, [IntPtr]::Zero, [uint32]0x10000000, $pFenceName, $pSharedFenceHandleOut)
    $hSharedFence = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pSharedFenceHandleOut)
    Remove-NativeBlock $pSharedFenceHandleOut
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pFenceName)

    $fnFenceSignal = Get-ComCall $pFence 10 ([int32]) ([Type[]]@([IntPtr], [uint64]))
    $fnGetAdapterLuid = Get-ComCall $pD3D12Device 43 ([uint64]) ([Type[]]@([IntPtr]))
    $adapterLuidBits = [uint64]$fnGetAdapterLuid.DynamicInvoke($pD3D12Device)

    # MMF Manifest
    $manifestName = "DirectPort_Producer_Manifest_$pidNum"
    $mmf = [System.IO.MemoryMappedFiles.MemoryMappedFile]::CreateNew(
        $manifestName, [int64]1056, [System.IO.MemoryMappedFiles.MemoryMappedFileAccess]::ReadWrite)
    $acc = $mmf.CreateViewAccessor(0, 1056, [System.IO.MemoryMappedFiles.MemoryMappedFileAccess]::ReadWrite)
    $acc.Write(0, [uint64]0)
    $acc.Write(8, [uint32]$Width)
    $acc.Write(12, [uint32]$Height)
    $acc.Write(16, [int32]87)
    $luidBytes = [System.BitConverter]::GetBytes([uint64]$adapterLuidBits)
    $acc.WriteArray(20, $luidBytes, 0, 8)
    $enc = [System.Text.Encoding]::Unicode
    $texNameBytes = $enc.GetBytes($texName + [char]0)
    $fenceNameBytes = $enc.GetBytes($fenceName + [char]0)
    $acc.WriteArray(28, $texNameBytes, 0, $texNameBytes.Length)
    $acc.WriteArray(540, $fenceNameBytes, 0, $fenceNameBytes.Length)

    $fnWicCopyPixels = if ($WicBitmap -ne [IntPtr]::Zero) {
        Get-ComCall $WicBitmap 7 ([int32]) ([Type[]]@([IntPtr], [IntPtr], [uint32], [uint32], [IntPtr]))
    } else { $null }

    $shareObj = [PSCustomObject]@{
        Device         = $pD3D12Device
        Resource       = $pResource
        Fence          = $pFence
        SharedTexture  = $hSharedTexture
        SharedFence    = $hSharedFence
        TextureName    = $texName
        FenceName      = $fenceName
        ManifestName   = $manifestName
        AdapterLuid    = $adapterLuidBits
        RowPitch       = $rowPitch
        MappedAddress  = $pMappedData
        DeviceHr       = $d3d12DeviceHr
        ResourceHr     = $d3d12ResourceHr
    }

    $shareObj | Add-Member -MemberType ScriptMethod -Name 'CopyPixels' -Value {
        param([IntPtr]$pBitmap)
        if ($pBitmap -eq [IntPtr]::Zero -or $null -eq $fnWicCopyPixels) { return 0 }
        return [int32]$fnWicCopyPixels.DynamicInvoke($pBitmap, [IntPtr]::Zero, $rowPitch, $bufferSize, $pMappedData)
    }.GetNewClosure()

    $shareObj | Add-Member -MemberType ScriptMethod -Name 'SignalFence' -Value {
        param([uint64]$frameVal)
        [System.Threading.Thread]::MemoryBarrier()
        $hr = [int32]$fnFenceSignal.DynamicInvoke($pFence, $frameVal)
        $acc.Write(0, $frameVal)
        return $hr
    }.GetNewClosure()

    $shareObj | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
        if ($pResource -ne [IntPtr]::Zero -and $pMappedData -ne [IntPtr]::Zero) {
            [void]$fnResourceUnmap.DynamicInvoke($pResource, [uint32]0, [IntPtr]::Zero)
        }
        if ($pFence -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pFence) }
        if ($pResource -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pResource) }
        if ($pD3D12Device -ne [IntPtr]::Zero) { [void][System.Runtime.InteropServices.Marshal]::Release($pD3D12Device) }
        if ($acc) { $acc.Dispose() }
        if ($mmf) { $mmf.Dispose() }
        $fnCloseHandle = Get-NativeCall (Get-NativeExport $kernel32 'CloseHandle') ([bool]) ([Type[]]@([IntPtr]))
        if ($hSharedFence -ne [IntPtr]::Zero) { [void]$fnCloseHandle.DynamicInvoke($hSharedFence) }
        if ($hSharedTexture -ne [IntPtr]::Zero) { [void]$fnCloseHandle.DynamicInvoke($hSharedTexture) }
    }.GetNewClosure()

    return $shareObj
}

# ==============================================================================
# SECTION 90-120: ANDROID & ADDITIONAL PLATFORM ADAPTERS
# ==============================================================================

function global:Invoke-AndroidCanvasBeginDraw { param($State, [object]$ClearColor) return $true }
function global:Invoke-AndroidCanvasFillRect  { param($State, [single]$X, [single]$Y, [single]$W, [single]$H, [object]$Color, [single]$Radius) }
function global:Invoke-AndroidCanvasDrawRect  { param($State, [single]$X, [single]$Y, [single]$W, [single]$H, [object]$Color, [single]$StrokeWidth, [single]$Radius) }
function global:Invoke-AndroidCanvasDrawText  { param($State, [string]$Text, [single]$X, [single]$Y, [single]$W, [single]$H, [object]$Color, [single]$Size, [string]$Font, [bool]$Bold, [int]$Align) }
function global:Invoke-AndroidCanvasMeasureText {
    param($State, [string]$Text, [single]$Size, [string]$Font, [bool]$Bold)
    return [PSCustomObject]@{ Width = ($Text.Length * $Size * 0.6); Height = ($Size * 1.2) }
}
function global:Invoke-AndroidCanvasPresent   { param($State) return $true }
function global:Invoke-AndroidCanvasDrawBitmap{ param($State, $Bitmap, [single]$Opacity, [uint32]$Interp) }

# ==============================================================================
# SECTION 130: REFERENCE-OBJECT ASSEMBLY & CONFORMANCE CARRIER
# ==============================================================================
# ==============================================================================
# SECTION 125: RETAINED PACKED-CELL CANVAS CAPABILITY
# ==============================================================================

# Mechanically retained Canvas program: packed storage, Build-Cells, stress
# behavior, telemetry, and the one-call TryPresent boundary stay together.
$script:DirectPortCanvasProgram = {
    param(
        [Parameter(Mandatory)][string] $AssemblyPath,
        [Parameter(Mandatory)][string] $AtlasPng,
        [Parameter(Mandatory)][string] $MetricsJson
    )

    enum CanvasMode { Touch; Pan; Colors; Charset; Grid; Noise }

    [Reflection.Assembly]::LoadFrom($AssemblyPath) | Out-Null
    $gpu = $null
    $script:Cells = [uint32[]]::new(1)
    $script:Columns = 1
    $script:Rows = 1
    $script:Mode = [CanvasMode]::Touch
    $script:GlyphAnimationStep = [uint64]0
    $script:Scale = 1
    $script:PanX = 0.0
    $script:PanY = 0.0
    $script:Dirty = $true
    $script:WasAnimating = $false
    $script:Ready = $false
    $script:Rng = [Random]::new()
    $script:NoiseBytes = [byte[]]::new(2)
    $script:TouchX = [Collections.Generic.List[int]]::new()
    $script:TouchY = [Collections.Generic.List[int]]::new()
    $script:TouchAt = [Collections.Generic.List[long]]::new()
    $script:LastTouchCell = -1
    $script:LastResizeSerial = [uint64]::MaxValue
    $script:LastFps = 0.0
    $script:LastBuild = 0.0
    $script:LastDropped = [uint64]0
    $script:EmitSample = $true

    $labels = @(
        @{ Text = ' 1 TOUCH '; Mode = [CanvasMode]::Touch },
        @{ Text = ' 2 PAN '; Mode = [CanvasMode]::Pan },
        @{ Text = ' 3 COLORS '; Mode = [CanvasMode]::Colors },
        @{ Text = ' 4 GLYPHS '; Mode = [CanvasMode]::Charset },
        @{ Text = ' 5 GRID '; Mode = [CanvasMode]::Grid },
        @{ Text = ' 6 NOISE '; Mode = [CanvasMode]::Noise }
    )

    function Set-Mode([CanvasMode] $Mode) {
        $wasAnimated = $script:Mode -in @([CanvasMode]::Charset, [CanvasMode]::Noise)
        $script:Mode = $Mode
        $isAnimated = $Mode -in @([CanvasMode]::Charset, [CanvasMode]::Noise)
        if ($wasAnimated -and -not $isAnimated) { $script:WasAnimating = $true }
        $script:Dirty = $true
        $script:EmitSample = $true
    }

    function Add-TouchCell([int] $X, [int] $Y) {
        if ($X -lt 0 -or $X -ge $script:Columns -or $Y -lt 1 -or $Y -ge $script:Rows) { return }
        $cell = $Y * $script:Columns + $X
        if ($cell -eq $script:LastTouchCell) { return }
        $script:LastTouchCell = $cell
        $script:TouchX.Add($X)
        $script:TouchY.Add($Y)
        $script:TouchAt.Add([Environment]::TickCount64)
        $script:Dirty = $true
    }

    function Put-Text([uint32[]] $Cells, [int] $Columns, [int] $Rows, [int] $X, [int] $Y,
                      [string] $Text, [int] $Foreground, [int] $Background) {
        if ($Y -lt 0 -or $Y -ge $Rows) { return }
        for ($i = 0; $i -lt $Text.Length -and ($X + $i) -lt $Columns; $i++) {
            if (($X + $i) -ge 0) {
                $Cells[$Y * $Columns + $X + $i] = [uint32](($Background -shl 24) -bor ($Foreground -shl 16) -bor [int]$Text[$i])
            }
        }
    }

    function Build-Cells([int] $ViewWidth, [int] $ViewHeight) {
        $cellWidth = 9 * $script:Scale
        $cellHeight = 18 * $script:Scale
        $columns = [Math]::Clamp([int][Math]::Floor($ViewWidth / $cellWidth), 1, 512)
        $rows = [Math]::Clamp([int][Math]::Floor($ViewHeight / $cellHeight), 2, 512)
        while (($columns * $rows) -gt 262144) { $rows-- }
        $shape = $columns -ne $script:Columns -or $rows -ne $script:Rows
        if ($shape) {
            $script:Columns = $columns
            $script:Rows = $rows
            $script:Cells = [uint32[]]::new($columns * $rows)
            $script:NoiseBytes = [byte[]]::new(2 * $columns * $rows)
        }
        else { [Array]::Clear($script:Cells, 0, $script:Cells.Length) }

        $cells = $script:Cells
        $mode = $script:Mode
        $px = [int][Math]::Floor($script:PanX)
        $py = [int][Math]::Floor($script:PanY)
        $centerX = [int]($columns / 2)
        $centerY = [int]($rows / 2)
        $band = [Math]::Max(1.0, $columns / 16.0)

        # Select the producer once per frame, never once per cell.
        if ($mode -eq [CanvasMode]::Grid) {
            for ($y = 1; $y -lt $rows; $y++) {
                $rowAt = $y * $columns
                for ($x = 0; $x -lt $columns; $x++) {
                    $cp = 32; $fg = 15; $bg = if ((($x + $y) -band 1) -eq 0) { 8 } else { 0 }
                    if ($x -eq 0 -or $y -eq 1 -or $x -eq ($columns - 1) -or $y -eq ($rows - 1)) { $bg = 1; $cp = 35 }
                    if (($x % 10) -eq 0 -and (($y - 1) % 5) -eq 0) { $bg = 4; $cp = 79 }
                    $cells[$rowAt + $x] = [uint32](($bg -shl 24) -bor ($fg -shl 16) -bor $cp)
                }
            }
        }
        elseif ($mode -eq [CanvasMode]::Colors) {
            for ($y = 1; $y -lt $rows; $y++) {
                $rowAt = $y * $columns; $cp = 65 + ($y % 26)
                for ($x = 0; $x -lt $columns; $x++) {
                    $bg = [int][Math]::Floor($x / $band) % 16; $fg = ($bg + 8) % 16
                    $cells[$rowAt + $x] = [uint32](($bg -shl 24) -bor ($fg -shl 16) -bor $cp)
                }
            }
        }
        elseif ($mode -eq [CanvasMode]::Charset) {
            for ($y = 1; $y -lt $rows; $y++) {
                $rowAt = $y * $columns; $fg = ($y % 15) + 1
                for ($x = 0; $x -lt $columns; $x++) {
                    $cp = 33 + (($rowAt + $x + $script:GlyphAnimationStep) % 94)
                    $cells[$rowAt + $x] = [uint32](($fg -shl 16) -bor $cp)
                }
            }
        }
        elseif ($mode -eq [CanvasMode]::Noise) {
            # Entropy generation stays in one native call; PowerShell only packs cells.
            $script:Rng.NextBytes($script:NoiseBytes)
            for ($y = 1; $y -lt $rows; $y++) {
                $rowAt = $y * $columns
                for ($x = 0; $x -lt $columns; $x++) {
                    $at = $rowAt + $x; $v = $script:NoiseBytes[2 * $at]
                    if (($v -band 15) -eq 0) {
                        $cp = 33 + ($v % 90); $fg = $script:NoiseBytes[2 * $at + 1] -band 15
                        $cells[$at] = [uint32](($fg -shl 16) -bor $cp)
                    }
                }
            }
        }
        elseif ($mode -eq [CanvasMode]::Pan) {
            for ($y = 1; $y -lt $rows; $y++) {
                $rowAt = $y * $columns; $wy = ($y - 1) - $py
                for ($x = 0; $x -lt $columns; $x++) {
                    $cp = 32; $fg = 15; $bg = 0; $wx = $x - $px
                    if ((([Math]::Abs($wx) -band 1) -eq 0) -eq (([Math]::Abs($wy) -band 1) -eq 0)) { $bg = 8 }
                    if ($wx -eq 0 -and $wy -eq 0) { $bg = 4; $cp = 88 }
                    elseif (($wx % 10) -eq 0 -and ($wy % 10) -eq 0) { $cp = 43 }
                    if ($x -eq $centerX -and $y -eq $centerY) { $bg = 1; $cp = 64 }
                    $cells[$rowAt + $x] = [uint32](($bg -shl 24) -bor ($fg -shl 16) -bor $cp)
                }
            }
        }

        # Oldest -> newest: normal last-write-wins makes the newest touch authoritative.
        $now = [Environment]::TickCount64
        for ($i = $script:TouchAt.Count - 1; $i -ge 0; $i--) {
            if (($now - $script:TouchAt[$i]) -ge 500) {
                $script:TouchAt.RemoveAt($i); $script:TouchX.RemoveAt($i); $script:TouchY.RemoveAt($i)
            }
        }
        for ($i = 0; $i -lt $script:TouchAt.Count; $i++) {
            $age = $now - $script:TouchAt[$i]
            if ($age -lt 100) { $bg = 14; $fg = 0; $cp = 88 }
            elseif ($age -lt 300) { $bg = 6; $fg = 15; $cp = 120 }
            else { $bg = 8; $fg = 15; $cp = 46 }
            $at = $script:TouchY[$i] * $columns + $script:TouchX[$i]
            if ($at -ge 0 -and $at -lt $cells.Length) { $cells[$at] = [uint32](($bg -shl 24) -bor ($fg -shl 16) -bor $cp) }
        }

        if ($mode -eq [CanvasMode]::Touch) {
            Put-Text $cells $columns $rows 3 3 ' CANVAS HOST: DIRECTPORT D3D12 ' 15 4
            $status = if ($script:TouchX.Count) {
                ' COORDS: [X:{0:D3} Y:{1:D3}] ' -f $script:TouchX[$script:TouchX.Count - 1], $script:TouchY[$script:TouchY.Count - 1]
            } else { ' WAITING FOR INPUT... ' }
            Put-Text $cells $columns $rows 3 5 $status 10 0
        }

        # Toolbar is itself cells; click ranges are reconstructed from these labels.
        $toolbarX = 0
        foreach ($button in $labels) {
            $selected = $button.Mode -eq $mode
            Put-Text $cells $columns $rows $toolbarX 0 $button.Text $(if ($selected) { 15 } else { 7 }) $(if ($selected) { 4 } else { 8 })
            $toolbarX += $button.Text.Length
        }
        if ($toolbarX -lt $columns) {
            $telemetry = ' {0}x{1} {2:0}fps {3:0.0}ms D{4} ' -f $columns, $rows, $script:LastFps, $script:LastBuild, $script:LastDropped
            Put-Text $cells $columns $rows $toolbarX 0 $telemetry 8 0
        }
        return $shape
    }

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $frequency = [double][System.Diagnostics.Stopwatch]::Frequency
    $targetTicks = [long]($frequency / 120.0)
    $nextFrame = [System.Diagnostics.Stopwatch]::GetTimestamp()
    $sampleAt = $nextFrame
    $sampleFrames = 0
    $buildTotal = 0.0
    $publishValue = [uint64]0
    $previousLeft = $false
    $previousX = 0
    $previousY = 0

    try {
        $suffix = "${PID}_debugcanvas"
        $gpu = [DirectPort.PowerShell.GpuConsole]::new(
            1280, 720, 262144,
            "Global\D3D12_Texture_$suffix", "Global\D3D12_Fence_$suffix",
            $AtlasPng, $MetricsJson)
        $gpu.EnableManifest("D3D12_Producer_Manifest_$PID")
        $gpu.Show('DirectPort Debug Canvas r6', 1000, 650)

        while ($true) {
            $animated = $script:Mode -in @([CanvasMode]::Charset, [CanvasMode]::Noise)
            $live = $script:Dirty -or $animated -or ($script:TouchAt.Count -gt 0)
            # Animated stress owns its cadence. A nonzero millisecond wait is
            # scheduler-quantized when no input arrives and throttles untouched
            # Glyphs/Noise despite the dirty transaction taking only a few ms.
            $wait = if ($live) { 0 } else { 1000 }
            $state = $gpu.Pump([uint32]$wait)
            if (-not $state.Alive) { break }

            if ($state.ResizeSerial -ne $script:LastResizeSerial) {
                $script:LastResizeSerial = $state.ResizeSerial
                $script:Dirty = $true
                if ($script:Ready) { "RESIZE $($state.Width)x$($state.Height)" }
            }
            if ($state.KeyCode -ge 49 -and $state.KeyCode -le 54) { Set-Mode ([CanvasMode]($state.KeyCode - 49)) }
            elseif ($state.KeyCode -eq 27) { break }
            elseif ($state.KeyCode -eq 187 -or $state.KeyCode -eq 107) { $script:Scale = [Math]::Min(8, $script:Scale + 1); $script:Dirty = $true }
            elseif ($state.KeyCode -eq 189 -or $state.KeyCode -eq 109) { $script:Scale = [Math]::Max(1, $script:Scale - 1); $script:Dirty = $true }

            $columns = [Math]::Max(1, $script:Columns); $rows = [Math]::Max(2, $script:Rows)
            $cellX = [Math]::Clamp([int][Math]::Floor($state.MouseX / [Math]::Max(1.0, $state.Width / $columns)), 0, $columns - 1)
            $cellY = [Math]::Clamp([int][Math]::Floor($state.MouseY / [Math]::Max(1.0, $state.Height / $rows)), 0, $rows - 1)
            if ($state.LeftDown -and -not $previousLeft -and $cellY -eq 0) {
                $hitX = 0
                foreach ($button in $labels) {
                    if ($cellX -ge $hitX -and $cellX -lt ($hitX + $button.Text.Length)) { Set-Mode $button.Mode; break }
                    $hitX += $button.Text.Length
                }
            }
            elseif ($state.LeftDown -and $cellY -gt 0) {
                if ($script:Mode -eq [CanvasMode]::Pan -and $previousLeft) {
                    $script:PanX -= ($state.MouseX - $previousX) / [Math]::Max(1.0, $state.Width / $columns)
                    $script:PanY -= ($state.MouseY - $previousY) / [Math]::Max(1.0, $state.Height / $rows)
                    $script:Dirty = $true
                }
                Add-TouchCell $cellX $cellY
            }
            if (-not $state.LeftDown) { $script:LastTouchCell = -1 }
            if ($state.WheelDelta -and $script:Mode -eq [CanvasMode]::Pan) {
                $script:PanY -= $state.WheelDelta / 120.0
                $script:Dirty = $true
            }
            $previousLeft = $state.LeftDown; $previousX = $state.MouseX; $previousY = $state.MouseY

            $nowTicks = [System.Diagnostics.Stopwatch]::GetTimestamp()
            $animated = $script:Mode -in @([CanvasMode]::Charset, [CanvasMode]::Noise)
            $live = $script:Dirty -or $animated -or ($script:TouchAt.Count -gt 0)
            if (-not $live -or $nowTicks -lt $nextFrame) { continue }
            $buildAt = $nowTicks
            $shape = Build-Cells $state.Width $state.Height
            if ($shape -and $script:Ready) { "RESIZE $($script:Columns)x$($script:Rows)" }
            $publishValue++
            $submitted = $gpu.TryPresent($script:Cells, $script:Columns, $script:Rows, [single]$clock.Elapsed.TotalSeconds, $publishValue)
            $builtAt = [System.Diagnostics.Stopwatch]::GetTimestamp()
            if ($submitted) {
                if (-not $script:Ready) { 'READY'; $script:Ready = $true }
                if ($script:Mode -eq [CanvasMode]::Charset) { $script:GlyphAnimationStep++ }
                $script:Dirty = $false
                $sampleFrames++
                $buildTotal += 1000.0 * ($builtAt - $buildAt) / $frequency
                if ($script:WasAnimating -and -not $animated) { 'IDLE'; $script:WasAnimating = $false }
                if ($animated) { $script:WasAnimating = $true }
            }
            if (($builtAt - $sampleAt) -ge $frequency) {
                $elapsed = ($builtAt - $sampleAt) / $frequency
                $script:LastFps = $sampleFrames / $elapsed
                $script:LastBuild = $buildTotal / [Math]::Max(1, $sampleFrames)
                $script:LastDropped = $gpu.DroppedFrames
                if ($script:EmitSample) {
                    'FPS={0:0} BUILD={1:0.0}ms' -f $script:LastFps, $script:LastBuild
                    $script:EmitSample = $false
                }
                $sampleAt = $builtAt; $sampleFrames = 0; $buildTotal = 0.0
            }
            $nextFrame = [Math]::Max($nextFrame + $targetTicks, $builtAt)
        }
    }
    finally {
        if ($null -ne $gpu) { $gpu.Dispose() }
        'CLOSED'
    }

}

function global:New-DirectPortRetainedCanvas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $AssemblyPath,
        [Parameter(Mandatory)][string] $AtlasPng,
        [Parameter(Mandatory)][string] $MetricsJson
    )

    foreach ($requiredPath in @($AssemblyPath, $AtlasPng, $MetricsJson)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Retained Canvas dependency not found: $requiredPath"
        }
    }

    $owner = [PSCustomObject]@{
        PSTypeName  = 'DirectPort.Capability.Canvas'
        Program     = $script:DirectPortCanvasProgram
        Runspace    = $null
        PowerShell  = $null
        AsyncResult = $null
        Output      = $null
        Attached    = $false
    }

    $owner | Add-Member -MemberType ScriptMethod -Name 'Attach' -Value {
        if ($this.Attached) { return $this }
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
        $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $runspace.Open()
        $powerShell = [System.Management.Automation.PowerShell]::Create()
        $powerShell.Runspace = $runspace
        # Parse the retained PowerShell program in the owned runspace so its
        # script scope and Canvas state belong to that runspace, not the caller.
        [void]$powerShell.AddScript($this.Program.ToString()).AddParameter('AssemblyPath', $AssemblyPath).AddParameter('AtlasPng', $AtlasPng).AddParameter('MetricsJson', $MetricsJson)
        $output = [System.Management.Automation.PSDataCollection[psobject]]::new()
        $this.Runspace = $runspace
        $this.PowerShell = $powerShell
        $this.Output = $output
        $this.AsyncResult = $powerShell.BeginInvoke[psobject,psobject]($null, $output)
        $this.Attached = $true
        return $this
    }.GetNewClosure()

    $owner | Add-Member -MemberType ScriptMethod -Name 'Wait' -Value {
        if (-not $this.Attached) { return @() }
        [void]$this.AsyncResult.AsyncWaitHandle.WaitOne()
        try {
            [void]$this.PowerShell.EndInvoke($this.AsyncResult)
            if ($this.PowerShell.Streams.Error.Count) { throw $this.PowerShell.Streams.Error[0] }
            return @($this.Output)
        }
        finally { $this.Detach() }
    }

    $owner | Add-Member -MemberType ScriptMethod -Name 'Detach' -Value {
        if (-not $this.Attached) { return }
        try {
            if ($null -ne $this.PowerShell -and
                $this.PowerShell.InvocationStateInfo.State -eq [System.Management.Automation.PSInvocationState]::Running) {
                $this.PowerShell.Stop()
            }
        }
        finally {
            if ($null -ne $this.PowerShell) { $this.PowerShell.Dispose() }
            if ($null -ne $this.Runspace) { $this.Runspace.Dispose() }
            $this.PowerShell = $null
            $this.Runspace = $null
            $this.AsyncResult = $null
            $this.Attached = $false
        }
    }

    $owner | Add-Member -MemberType ScriptMethod -Name 'Run' -Value {
        [void]$this.Attach()
        return $this.Wait()
    }
    return $owner
}

function global:Resolve-DirectPortCanvasDependencies {
    [CmdletBinding()]
    param(
        [string] $AssemblyPath,
        [string] $AtlasPng,
        [string] $MetricsJson
    )

    $sourceRoot = if ($script:DirectPortSourcePath) {
        Split-Path -Parent $script:DirectPortSourcePath
    } else { [Environment]::CurrentDirectory }

    if (-not $AssemblyPath -or -not (Test-Path -LiteralPath $AssemblyPath)) {
        foreach ($candidate in @(
            $AssemblyPath,
            $env:DIRECTPORT_DLL,
            $(if ($env:DIRECTPORT) { Join-Path $env:DIRECTPORT 'DirectPort.PowerShell.dll' }),
            'C:\Dev\DirectPort\Scripts\DirectPort.PowerShell.dll',
            (Join-Path $sourceRoot 'DirectPort.PowerShell.dll'),
            (Join-Path $sourceRoot 'bin\DirectPort.PowerShell.dll'),
            (Join-Path $PSHOME 'DirectPort.PowerShell.dll')
        )) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) { $AssemblyPath = $candidate; break }
        }
    }
    if (-not $AtlasPng -or -not (Test-Path -LiteralPath $AtlasPng)) {
        foreach ($candidate in @(
            $AtlasPng, $env:DIRECTPORT_ATLAS,
            'C:\Dev\atlas maps\GLYPHS\cascadia-code-atlas.png',
            (Join-Path $sourceRoot 'cascadia-code-atlas.png'),
            (Join-Path $sourceRoot 'assets\cascadia-code-atlas.png'),
            (Join-Path $PSHOME 'cascadia-code-atlas.png')
        )) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) { $AtlasPng = $candidate; break }
        }
    }
    if (-not $MetricsJson -or -not (Test-Path -LiteralPath $MetricsJson)) {
        foreach ($candidate in @(
            $MetricsJson, $env:DIRECTPORT_METRICS,
            'C:\Dev\atlas maps\GLYPHS\cascadia-code-metrics.json',
            (Join-Path $sourceRoot 'cascadia-code-metrics.json'),
            (Join-Path $sourceRoot 'assets\cascadia-code-metrics.json'),
            (Join-Path $PSHOME 'cascadia-code-metrics.json')
        )) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) { $MetricsJson = $candidate; break }
        }
    }

    foreach ($dependency in @($AssemblyPath, $AtlasPng, $MetricsJson)) {
        if (-not $dependency -or -not (Test-Path -LiteralPath $dependency)) {
            throw 'DirectPort retained Canvas dependencies were not found. Pass -AssemblyPath, -AtlasPng, and -MetricsJson.'
        }
    }
    return [PSCustomObject]@{ AssemblyPath = $AssemblyPath; AtlasPng = $AtlasPng; MetricsJson = $MetricsJson }
}

$script:DirectPortSurface = [PSCustomObject]@{
    PSTypeName = 'DirectPort.Surface'
    Canvas     = $null
}
$script:DirectPortSurface | Add-Member -MemberType ScriptMethod -Name 'AttachCanvas' -Value {
    param(
        [Parameter(Mandatory)][string] $AssemblyPath,
        [Parameter(Mandatory)][string] $AtlasPng,
        [Parameter(Mandatory)][string] $MetricsJson
    )
    if ($null -ne $this.Canvas -and $this.Canvas.Attached) { return $this.Canvas }
    $this.Canvas = New-DirectPortRetainedCanvas -AssemblyPath $AssemblyPath -AtlasPng $AtlasPng -MetricsJson $MetricsJson
    [void]$this.Canvas.Attach()
    return $this.Canvas
}
$script:DirectPortSurface | Add-Member -MemberType ScriptMethod -Name 'DetachCanvas' -Value {
    if ($null -eq $this.Canvas) { return }
    $this.Canvas.Detach()
    $this.Canvas = $null
}

# ==============================================================================
# SECTION 127: DIRECTPORT NODE AND SINGLE APPLICATION ATTACHMENT
# ==============================================================================

function global:New-DirectPortGrantDomain {
    [CmdletBinding()]
    param([string] $Name = 'GrantDomain')
    $domain = [PSCustomObject]@{
        PSTypeName  = 'DirectPort.GrantDomain'
        Name        = $Name
        Live        = $true
        ActiveCount = 0
        Lock        = [object]::new()
        Epoch       = 1
    }
    $domain | Add-Member ScriptMethod Acquire {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            if (-not $this.Live) { return $false }
            $this.ActiveCount++
            return $true
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    $domain | Add-Member ScriptMethod Release {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            if ($this.ActiveCount -gt 0) { $this.ActiveCount-- }
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    $domain | Add-Member ScriptMethod BeginRundown {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            if (-not $this.Live) { return $false }
            $this.Live = $false
            $this.Epoch++
            return $true
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    return $domain
}

function global:New-DirectPortNode {
    [CmdletBinding()]
    param([string] $Name = 'DirectPort', $Parent = $null, $ExecutionOwner = $null)

    $node = [PSCustomObject]@{
        PSTypeName             = 'DirectPort.Node'
        NodeId                 = [Guid]::NewGuid().ToString('N')
        ResolverIncarnation    = [Guid]::NewGuid().ToString('N')
        SemanticIdentityDomain = [Guid]::NewGuid().ToString('N')
        Name                   = $Name
        Parent                 = $Parent
        ExecutionOwner         = $ExecutionOwner
        LocalCapabilities      = @{}
        LocalHandles           = @{}
        Children               = @{}
        CurrentApplication     = $null
        LastReceipt            = $null
        DiscoveryCount         = 0
        Rundown                = $false
    }
    $node | Add-Member ScriptMethod RetainLocal {
        param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)] $Capability, $ExecutionOwner = $null)
        $entry = [PSCustomObject]@{
            PSTypeName          = 'DirectPort.LocalCapability'
            Name                = $Name
            ObjectHandle        = [Guid]::NewGuid().ToString('N')
            ResolverIncarnation = $this.ResolverIncarnation
            Capability          = $Capability
            ExecutionOwner      = $ExecutionOwner
            OwnerRunspaceId     = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
            Source              = 'LOCAL'
            Revoked             = $false
            Grants              = @{}
            GrantDomain         = (New-DirectPortGrantDomain -Name $Name)
        }
        $this.LocalCapabilities[$Name] = $entry
        $this.LocalHandles[$entry.ObjectHandle] = $entry
        return $entry
    }
    $node | Add-Member ScriptMethod ResolveLocal {
        param([Parameter(Mandatory)][string] $Name)
        if ($this.LocalCapabilities.ContainsKey($Name)) { return $this.LocalCapabilities[$Name] }
        return $null
    }
    $node | Add-Member ScriptMethod ResolveLocalHandle {
        param([Parameter(Mandatory)][string] $ObjectHandle)
        if ($this.LocalHandles.ContainsKey($ObjectHandle)) { return $this.LocalHandles[$ObjectHandle] }
        return $null
    }
    $node | Add-Member ScriptMethod Discover {
        param([Parameter(Mandatory)][string] $Name, $Context = $null)
        $this.DiscoveryCount++
        if ($null -eq $Context) {
            $Context = [PSCustomObject]@{ AttemptId = [Guid]::NewGuid(); RemainingDepth = 16; Visited = @{} }
        }
        if ($Context.RemainingDepth -le 0 -or $Context.Visited.ContainsKey($this.NodeId)) { return $null }
        $Context.Visited[$this.NodeId] = $true
        $Context.RemainingDepth--
        if ($this.LocalCapabilities.ContainsKey($Name)) {
            return [PSCustomObject]@{ SourceNode = $this; Name = $Name; AttemptId = $Context.AttemptId }
        }
        if ($null -ne $this.Parent) { return $this.Parent.Discover($Name, $Context) }
        return $null
    }
    $node | Add-Member ScriptMethod Checkout {
        param([Parameter(Mandatory)] $Discovered)
        $sourceEntry = $Discovered.SourceNode.ResolveLocal([string]$Discovered.Name)
        if ($null -eq $sourceEntry -or $sourceEntry.Revoked) { throw "Capability is no longer available: $($Discovered.Name)" }
        if ($sourceEntry.ResolverIncarnation -eq $this.ResolverIncarnation) { return $sourceEntry }

        $receiverHandle = [Guid]::NewGuid().ToString('N')
        $targetOwnerHandle = $sourceEntry.ObjectHandle
        $callerNodeId = $this.NodeId
        $sourceEntry.Grants[$callerNodeId] = [PSCustomObject]@{
            ReceiverHandle = $receiverHandle
            AdmittedAt     = [DateTimeOffset]::UtcNow
        }

        $sourceOwnerRunspaceId = $sourceEntry.OwnerRunspaceId
        $sourceOwner = $sourceEntry.ExecutionOwner
        $sourceCapability = $sourceEntry.Capability
        $currentRunspaceId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId

        $isSameOwner = ($this.ExecutionOwner -eq $sourceOwner -or ($null -ne $sourceOwnerRunspaceId -and $currentRunspaceId -eq $sourceOwnerRunspaceId))
        $callable = if ($isSameOwner) {
            $sourceCapability
        } else {
            $queue = $script:DirectPortOwnerDispatchQueue
            $wake = $script:DirectPortOwnerDispatchWake
            {
                $callArgs = if ($PSBoundParameters.Count -gt 0) {
                    $PSBoundParameters
                } elseif ($null -ne $args -and $args.Count -gt 0) {
                    @($args)
                } else {
                    $null
                }
                $request = [PSCustomObject]@{
                    TargetOwnerHandle = $targetOwnerHandle
                    ReceiverHandle    = $receiverHandle
                    CallerNodeId      = $callerNodeId
                    Arguments         = $callArgs
                    Result            = $null
                    ErrorRecord       = $null
                    Completed         = [System.Threading.ManualResetEventSlim]::new($false)
                    Status            = 'Pending'
                }
                $queue.Enqueue($request)
                [void]$wake.Set()
                $signaled = $request.Completed.Wait(30000)
                if (-not $signaled) {
                    $request.Status = 'TimedOut'
                    throw 'Owner dispatch request timed out waiting for owning execution context.'
                }
                try {
                    if ($null -ne $request.ErrorRecord) { throw $request.ErrorRecord }
                    return $request.Result
                }
                finally {
                    $request.Completed.Dispose()
                }
            }.GetNewClosure()
        }

        $entry = [PSCustomObject]@{
            PSTypeName                = 'DirectPort.LocalCapability'
            Name                      = $sourceEntry.Name
            ObjectHandle              = $receiverHandle
            TargetOwnerHandle         = $targetOwnerHandle
            SourceObjectHandle        = $targetOwnerHandle
            ResolverIncarnation       = $this.ResolverIncarnation
            SourceResolverIncarnation = $sourceEntry.ResolverIncarnation
            Capability                = $callable
            ExecutionOwner            = $sourceOwner
            OwnerRunspaceId           = $sourceOwnerRunspaceId
            Source                    = 'CHECKOUT'
            Revoked                   = $false
        }
        $this.LocalCapabilities[$entry.Name] = $entry
        $this.LocalHandles[$entry.ObjectHandle] = $entry
        return $entry
    }
    return $node
}

$applicationContextVariable = Get-Variable -Name DirectPortApplicationContext -Scope Global -ErrorAction SilentlyContinue
$script:DirectPortNode = if ($null -ne $applicationContextVariable -and $null -ne $applicationContextVariable.Value.Node) {
    $applicationContextVariable.Value.Node
} else {
    New-DirectPortNode -Name 'DirectPort.Root'
}

$script:DirectPortOwnerDispatchQueue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:DirectPortOwnerDispatchWake = [Threading.AutoResetEvent]::new($false)
$script:DirectPortOwnerGateway = [PSCustomObject]@{
    Queue = $script:DirectPortOwnerDispatchQueue
    Wake  = $script:DirectPortOwnerDispatchWake
}

function global:Invoke-DirectPortOwnerDispatch {
    [CmdletBinding()]
    param([int] $Maximum = 64)

    $completed = 0
    $request = $null
    while ($completed -lt $Maximum -and $script:DirectPortOwnerDispatchQueue.TryDequeue([ref]$request)) {
        if ($null -eq $request -or $request.Status -ne 'Pending') {
            continue
        }
        $request.Status = 'Executing'
        try {
            $callerNodeId = [string]$request.CallerNodeId
            $targetHandle = [string]$request.TargetOwnerHandle

            $callerNode = if ($callerNodeId -eq $script:DirectPortNode.NodeId) {
                $script:DirectPortNode
            } else {
                $script:DirectPortNode.Children[$callerNodeId]
            }
            if ($null -eq $callerNode -or $callerNode.Rundown) {
                throw "Caller node '$callerNodeId' is not attached or has been rundown."
            }

            $entry = $script:DirectPortNode.ResolveLocalHandle($targetHandle)
            if ($null -eq $entry -or $entry.Revoked) {
                throw "Owner-local capability handle is invalid or revoked: $targetHandle"
            }

            if ($callerNodeId -ne $script:DirectPortNode.NodeId) {
                if (-not $entry.Grants.ContainsKey($callerNodeId)) {
                    throw "Caller node '$callerNodeId' is not admitted for capability '$($entry.Name)'."
                }
            }

            if ($null -ne $entry.GrantDomain) {
                if (-not $entry.GrantDomain.Acquire()) {
                    throw "Capability '$($entry.Name)' is in rundown."
                }
            }

            try {
                $capArgs = $request.Arguments
                if ($null -ne $capArgs) {
                    if ($capArgs -is [System.Collections.IDictionary]) {
                        $request.Result = & $entry.Capability @capArgs
                    } elseif ($capArgs -is [System.Collections.IEnumerable] -and $capArgs.Count -gt 0) {
                        $arr = @($capArgs)
                        $request.Result = & $entry.Capability @arr
                    } else {
                        $request.Result = & $entry.Capability
                    }
                } else {
                    $request.Result = & $entry.Capability
                }
                $request.Status = 'Completed'
            }
            finally {
                if ($null -ne $entry.GrantDomain) {
                    $entry.GrantDomain.Release()
                }
            }
        }
        catch {
            $request.ErrorRecord = $_
            $request.Status = 'Faulted'
        }
        finally {
            $request.Completed.Set()
            $completed++
        }
        $request = $null
    }
    return $completed
}

function global:New-DirectPortRunspace {
    [CmdletBinding()]
    param(
        [System.Threading.ApartmentState] $ApartmentState = [System.Threading.ApartmentState]::STA,
        $Node = $null,
        $Commands = @{}
    )
    $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $grantedCapabilities = @()
    $commandMap = @{}
    if ($null -ne $Node) {
        $initialState.Variables.Add([System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
            'DirectPortGateway', $script:DirectPortOwnerGateway, 'DirectPort owner-dispatch ingress'))

        if ($Commands -is [System.Collections.IDictionary]) {
            foreach ($k in $Commands.Keys) { $commandMap[[string]$k] = [string]$Commands[$k] }
        } elseif ($Commands -is [System.Collections.IEnumerable]) {
            foreach ($c in $Commands) { $commandMap[[string]$c] = [string]$c }
        }

        foreach ($commandName in $commandMap.Keys) {
            $capName = $commandMap[$commandName]
            $entry = $Node.ResolveLocal($capName)
            if ($null -eq $entry -or $entry.Revoked) {
                throw "Runspace command capability is not local or granted for receiver: $capName"
            }
            $grantedCapabilities += $entry

            $targetOwnerHandle = [string]$entry.SourceObjectHandle
            $receiverHandle = [string]$entry.ObjectHandle
            $callerNodeId = [string]$Node.NodeId

            $definition = @"
`$request = [PSCustomObject]@{
    TargetOwnerHandle = '$targetOwnerHandle'
    ReceiverHandle    = '$receiverHandle'
    CallerNodeId      = '$callerNodeId'
    Arguments         = @(`$args)
    Result            = `$null
    ErrorRecord       = `$null
    Completed         = [System.Threading.ManualResetEventSlim]::new(`$false)
    Status            = 'Pending'
}
`$DirectPortGateway.Queue.Enqueue(`$request)
[void]`$DirectPortGateway.Wake.Set()
`$signaled = `$request.Completed.Wait(30000)
if (-not `$signaled) {
    `$request.Status = 'TimedOut'
    throw 'Owner dispatch request timed out waiting for owning execution context.'
}
try {
    if (`$null -ne `$request.ErrorRecord) { throw `$request.ErrorRecord }
    return `$request.Result
}
finally {
    `$request.Completed.Dispose()
}
"@
            $initialState.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
                [string]$commandName, $definition))
        }
    }

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
    $runspace.ApartmentState = $ApartmentState
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $runspace.Open()

    $residentId = [Guid]::NewGuid().ToString('N')
    $resolverIncarnation = if ($null -ne $Node) { $Node.ResolverIncarnation } else { [Guid]::NewGuid().ToString('N') }

    $resident = [PSCustomObject]@{
        PSTypeName           = 'DirectPort.Resident.Runspace'
        ObjectId             = [Guid]::NewGuid().ToString('N')
        ResidentId           = $residentId
        ResolverIncarnation  = $resolverIncarnation
        Runspace             = $runspace
        Node                 = $Node
        GrantedCapabilities  = $grantedCapabilities
        Commands             = if ($null -ne $commandMap) { $commandMap } else { @{} }
        PowerShell           = $null
        AsyncResult          = $null
        Output               = $null
        Live                 = $true
        Rundown              = $false
    }
    $resident | Add-Member ScriptMethod StartFile {
        param([string] $Path, [hashtable] $Parameters = @{}, $ApplicationContext = $null)
        if ($this.Rundown) { throw 'Runspace resident is in rundown.' }
        if ($null -ne $this.PowerShell -and $this.PowerShell.InvocationStateInfo.State -eq 'Running') {
            throw 'The retained runspace is already executing an application.'
        }
        if ($null -ne $this.PowerShell) {
            $this.PowerShell.Dispose()
            $this.PowerShell = $null
            $this.AsyncResult = $null
            $this.Output = $null
        }
        if ($null -ne $ApplicationContext) {
            $this.Runspace.SessionStateProxy.SetVariable('DirectPortApplicationContext', $ApplicationContext)
            $this.Runspace.SessionStateProxy.SetVariable('DIRECTPORT_PATH', $ApplicationContext.DirectPortPath)
        }
        $pipeline = [System.Management.Automation.PowerShell]::Create()
        $pipeline.Runspace = $this.Runspace
        [void]$pipeline.AddScript('param($path,$parameters) & $path @parameters').AddArgument($Path).AddArgument($Parameters)
        $this.PowerShell = $pipeline
        $this.Output = [System.Management.Automation.PSDataCollection[psobject]]::new()
        $this.AsyncResult = $pipeline.BeginInvoke[psobject,psobject]($null, $this.Output)
        return $this.AsyncResult
    }
    $resident | Add-Member ScriptMethod Wait {
        param([int] $TimeoutMilliseconds = -1)
        if ($null -eq $this.PowerShell -or $null -eq $this.AsyncResult) { return @() }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $waitHandles = @($this.AsyncResult.AsyncWaitHandle, $script:DirectPortOwnerDispatchWake)
        while (-not $this.AsyncResult.IsCompleted) {
            $remaining = if ($TimeoutMilliseconds -lt 0) {
                [System.Threading.Timeout]::Infinite
            } else {
                $rem = $TimeoutMilliseconds - [int]$sw.ElapsedMilliseconds
                if ($rem -le 0) { break }
                $rem
            }
            $signaledIndex = [System.Threading.WaitHandle]::WaitAny($waitHandles, $remaining)
            if ($signaledIndex -eq 1) {
                [void](Invoke-DirectPortOwnerDispatch)
            }
            elseif ($signaledIndex -eq 0) {
                break
            }
            elseif ($signaledIndex -eq [System.Threading.WaitHandle]::WaitTimeout) {
                break
            }
        }
        [void](Invoke-DirectPortOwnerDispatch)
        if ($this.AsyncResult.IsCompleted) {
            [void]$this.PowerShell.EndInvoke($this.AsyncResult)
            if ($this.PowerShell.Streams.Error.Count) { throw $this.PowerShell.Streams.Error[0] }
            return @($this.Output)
        }
        return @()
    }
    $resident | Add-Member ScriptMethod Stop {
        if ($null -ne $this.PowerShell -and $this.PowerShell.InvocationStateInfo.State -eq 'Running') {
            $this.PowerShell.Stop()
        }
    }
    $resident | Add-Member ScriptMethod Dispose {
        $this.Rundown = $true
        $this.Live = $false
        $this.Stop()
        if ($null -ne $this.PowerShell) { $this.PowerShell.Dispose(); $this.PowerShell = $null }
        if ($null -ne $this.Runspace) { $this.Runspace.Dispose(); $this.Runspace = $null }
    }
    return $resident
}

function global:Detach-DirectPortApplication {
    $attachment = $script:DirectPortNode.CurrentApplication
    if ($null -eq $attachment) { return $false }
    try {
        if ($null -ne $attachment.Execution) { $attachment.Execution.Dispose() }
        if ($null -ne $attachment.Node) {
            $attachment.Node.Rundown = $true
            foreach ($entry in $attachment.Node.LocalHandles.Values) {
                $entry.Revoked = $true
            }
        }
    }
    finally {
        $script:DirectPortNode.Children.Remove($attachment.Node.NodeId)
        $script:DirectPortNode.CurrentApplication = $null
        $script:DirectPortNode.LastReceipt = [PSCustomObject]@{
            Event = 'APPLICATION_DETACHED'; Path = $attachment.Path; At = [DateTimeOffset]::UtcNow
        }
    }
    return $true
}

function global:Add-DirectPortApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [ValidateSet('None','Inline','Dedicated','Supplied')][string] $ExecutionPlacement = 'None',
        $ExecutionOwner = $null,
        [switch] $Start,
        [switch] $Headless
    )

    $applicationPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) { throw "Application script not found: $applicationPath" }
    if ([IO.Path]::GetExtension($applicationPath) -ine '.ps1') { throw "DirectPort loads .ps1 applications only: $applicationPath" }
    if ($null -ne $script:DirectPortNode.CurrentApplication) { [void](Detach-DirectPortApplication) }

    $applicationNode = New-DirectPortNode -Name ([IO.Path]::GetFileNameWithoutExtension($applicationPath)) -Parent $script:DirectPortNode
    foreach ($capabilityName in @('Canvas.New', 'Runspace.New')) {
        $discovered = $applicationNode.Discover($capabilityName)
        if ($null -ne $discovered) { [void]$applicationNode.Checkout($discovered) }
    }
    if ($ExecutionPlacement -eq 'Supplied' -and $null -eq $ExecutionOwner) { throw 'Supplied execution requires ExecutionOwner.' }
    $execution = switch ($ExecutionPlacement) {
        'Dedicated' {
            New-DirectPortRunspace -Node $applicationNode -Commands @{
                'New-DirectPortCanvas' = 'Canvas.New'
            }
        }
        'Supplied' { $ExecutionOwner }
        default { $null }
    }
    $attachment = [PSCustomObject]@{
        PSTypeName         = 'DirectPort.ApplicationAttachment'
        Path               = $applicationPath
        Node               = $applicationNode
        Execution          = $execution
        ExecutionPlacement = $ExecutionPlacement
        AttachedAt         = [DateTimeOffset]::UtcNow
    }
    $script:DirectPortNode.Children[$applicationNode.NodeId] = $applicationNode
    $script:DirectPortNode.CurrentApplication = $attachment
    $script:DirectPortNode.LastReceipt = [PSCustomObject]@{
        Event = 'APPLICATION_ATTACHED'; Path = $applicationPath; NodeId = $applicationNode.NodeId; At = $attachment.AttachedAt
    }
    if ($Start) {
        $parameters = if ($Headless) { @{ Headless = $true } } else { @{} }
        $context = [PSCustomObject]@{
            DirectPort                   = if ($ExecutionPlacement -eq 'Inline') { $global:DirectPort } else { $null }
            Node                         = if ($ExecutionPlacement -eq 'Inline') { $applicationNode } else { $null }
            DirectPortPath               = $script:DirectPortSourcePath
            AttachedToExistingDirectPort = $true
            ExecutionPlacement           = $ExecutionPlacement
        }
        switch ($ExecutionPlacement) {
            'None' { throw 'Start requires Inline, Dedicated, or Supplied execution placement.' }
            'Inline' {
                $priorContext = Get-Variable -Name DirectPortApplicationContext -Scope Global -ErrorAction SilentlyContinue
                try {
                    Set-Variable -Name DirectPortApplicationContext -Scope Global -Value $context
                    & $applicationPath @parameters
                }
                finally {
                    if ($null -ne $priorContext) {
                        Set-Variable -Name DirectPortApplicationContext -Scope Global -Value $priorContext.Value
                    } else {
                        Remove-Variable -Name DirectPortApplicationContext -Scope Global -ErrorAction SilentlyContinue
                    }
                }
            }
            default { [void]$execution.StartFile($applicationPath, $parameters, $context) }
        }
    }
    return $attachment
}



$global:DirectPort = [PSCustomObject]@{
    Version           = '0.5.0-rehab'
    SourcePath        = [IO.Path]::GetFullPath($script:DirectPortSourcePath)
    Node              = $script:DirectPortNode
    NewCanvas         = ${function:New-DirectPortCanvas}
    NewRetainedCanvas = ${function:New-DirectPortRetainedCanvas}
    NewRunspace       = ${function:New-DirectPortRunspace}
    LoadApplication   = ${function:Add-DirectPortApplication}
    DetachApplication = ${function:Detach-DirectPortApplication}
    Surface           = $script:DirectPortSurface
    Host              = ${function:New-WindowsHost}
    Linker            = ${function:Export-DirectPortBundle}
}

# These are resolver-local retained capabilities. Application nodes explicitly
# checkout the entries they consume once; subsequent calls use their local entry.
[void]$script:DirectPortNode.RetainLocal('Canvas.New', $global:DirectPort.NewCanvas, $script:DirectPortNode)
[void]$script:DirectPortNode.RetainLocal('Runspace.New', $global:DirectPort.NewRunspace, $script:DirectPortNode)
[void]$script:DirectPortNode.RetainLocal('Application.Load', $global:DirectPort.LoadApplication, $script:DirectPortNode)

# ==============================================================================
# SECTION 150: PACKAGING & LINKER ENGINE (ALL-IN-ONE BUILDER)
# ==============================================================================

function global:Export-DirectPortBundle {
    <#
    .SYNOPSIS
        Bundles an application script and DirectPort.ps1 into a standalone All-In-One .ps1 file.
    .DESCRIPTION
        Conforms to DP-ARCH-005 Section 26:
        Builds a self-contained portable PowerShell script by embedding the required DirectPort
        presentation engine and replacing external dot-sourcing logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string] $ScriptPath,

        [Parameter(Mandatory=$false, Position=1)]
        [string] $OutputPath = $null,

        [switch] $StripDevNotes = $true
    )

    $resolvedScript = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)
    if (-not (Test-Path $resolvedScript)) {
        throw "Target application script not found: $ScriptPath"
    }

    if ([string]::IsNullOrEmpty($OutputPath)) {
        $dir = Split-Path $resolvedScript -Parent
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedScript)
        $OutputPath = Join-Path $dir "$baseName.AllInOne.ps1"
    }
    $resolvedOut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

    $dpSourcePath = if ($script:DirectPortSourcePath -and (Test-Path $script:DirectPortSourcePath)) {
        $script:DirectPortSourcePath
    } else {
        Join-Path $PSScriptRoot "DirectPort.ps1"
    }

    if (-not (Test-Path $dpSourcePath)) {
        throw "DirectPort source file not found at $dpSourcePath"
    }

    Write-Host "[DirectPort Linker] Reading application: $resolvedScript" -ForegroundColor Cyan
    Write-Host "[DirectPort Linker] Reading DirectPort:   $dpSourcePath" -ForegroundColor Cyan

    $appLines = Get-Content -Path $resolvedScript
    $dpLines  = Get-Content -Path $dpSourcePath

    # Filter DirectPort lines: strip the direct execution guard at the end
    $cleanDpLines = [System.Collections.Generic.List[string]]::new()
    $inDirectGuard = $false
    foreach ($line in $dpLines) {
        if ($line -match '^\s*#\s*SECTION 160:\s*DIRECT EXECUTION GUARD' -or
            $line -match '^\s*\$isDirectExecution\s*=') {
            $inDirectGuard = $true
            continue
        }
        if ($inDirectGuard) {
            # Check if guard has ended or reached EOF
            continue
        }
        $cleanDpLines.Add($line)
    }

    # Filter Application lines: replace external dot-sourcing of DirectPort
    $cleanAppLines = [System.Collections.Generic.List[string]]::new()
    $skipDotSourceBlock = $false
    foreach ($line in $appLines) {
        if ($line -match '^\s*#requires -Version 7.0') {
            # Preserved at top of bundle
            continue
        }
        if ($line -match '\$dpPath\s*=\s*Join-Path\s+\$PSScriptRoot\s+"DirectPort\.ps1"') {
            $skipDotSourceBlock = $true
            $cleanAppLines.Add("    # [DirectPort Linker: Inlined Runtime Carrier]")
            continue
        }
        if ($skipDotSourceBlock) {
            if ($line -match '^\s*\}\s*$') {
                $skipDotSourceBlock = $false
            }
            continue
        }
        $cleanAppLines.Add($line)
    }

    # Assemble bundle
    $bundleSb = [System.Text.StringBuilder]::new()
    [void]$bundleSb.AppendLine("#requires -Version 7.0")
    [void]$bundleSb.AppendLine("<#")
    [void]$bundleSb.AppendLine("  ==========================================================================")
    [void]$bundleSb.AppendLine("  DirectPort Self-Contained Standalone Application Bundle")
    [void]$bundleSb.AppendLine("  Target Application : $(Split-Path $resolvedScript -Leaf)")
    [void]$bundleSb.AppendLine("  Engine Specification: DP-ARCH-005 Conforming")
    [void]$bundleSb.AppendLine("  Architecture       : Unified Inlined DirectPort + Application Presentation")
    [void]$bundleSb.AppendLine("  ==========================================================================")
    [void]$bundleSb.AppendLine("#>")
    [void]$bundleSb.AppendLine("")
    [void]$bundleSb.AppendLine("# ==============================================================================")
    [void]$bundleSb.AppendLine("# INLINED DIRECTPORT RUNTIME ENGINE")
    [void]$bundleSb.AppendLine("# ==============================================================================")
    [void]$bundleSb.AppendLine($cleanDpLines -join [Environment]::NewLine)
    [void]$bundleSb.AppendLine("")
    [void]$bundleSb.AppendLine("# ==============================================================================")
    [void]$bundleSb.AppendLine("# APPLICATION SOURCE LOGIC: $(Split-Path $resolvedScript -Leaf)")
    [void]$bundleSb.AppendLine("# ==============================================================================")
    [void]$bundleSb.AppendLine($cleanAppLines -join [Environment]::NewLine)

    [System.IO.File]::WriteAllText($resolvedOut, $bundleSb.ToString(), [System.Text.Encoding]::UTF8)
    Write-Host "[DirectPort Linker] Successfully generated All-In-One bundle:" -ForegroundColor Green
    Write-Host "  Destination: $resolvedOut" -ForegroundColor White
    Write-Host "  Lines      : $($bundleSb.ToString().Split("`n").Length)" -ForegroundColor Gray
    Write-Host "  Bytes      : $((Get-Item $resolvedOut).Length)" -ForegroundColor Gray

    return $resolvedOut
}

# Export-DirectPortBundle is declared after the retained root is assembled.
$global:DirectPort.Linker = ${function:Export-DirectPortBundle}

# ==============================================================================
# SECTION 160: DIRECT EXECUTION GUARD & CLI BUNDLE DISPATCH
# ==============================================================================

if ($Bundle) {
    $out = Export-DirectPortBundle -ScriptPath $Bundle -OutputPath $OutFile
    exit 0
}

$isDirectExecution = [string]::IsNullOrEmpty($MyInvocation.ScriptName) -and
                     ($MyInvocation.InvocationName -ne '.')

if ($isDirectExecution) {
    if ($Headless) { exit 0 }
    $resolvedCanvas = Resolve-DirectPortCanvasDependencies -AssemblyPath $AssemblyPath -AtlasPng $AtlasPng -MetricsJson $MetricsJson
    $retainedCanvas = $global:DirectPort.Surface.AttachCanvas(
        $resolvedCanvas.AssemblyPath, $resolvedCanvas.AtlasPng, $resolvedCanvas.MetricsJson)
    try { $retainedCanvas.Wait() }
    finally { $global:DirectPort.Surface.DetachCanvas() }
}
