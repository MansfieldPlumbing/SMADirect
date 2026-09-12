# Import-WindowsHeader.ps1
# Authoritative PowerShell loader for Vendor/windows.h
# Eliminates all hardcoded magic numbers, offsets, and flags across build scripts.

function Import-WindowsHeader {
    param(
    [string]$HeaderPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Vendor\windows.h')
    )

    if (-not (Test-Path $HeaderPath)) {
        throw "Authoritative header not found at $HeaderPath"
    }

    $raw = Get-Content $HeaderPath -Raw

    $defines = [ordered]@{}
    $comments = @{}

    # 1. Parse #define macros with cryptographic donor comments
    $regexDef = '(?m)(?:\/\*\s*DONOR:\s*([^|]+)\|\s*SHA256:\s*([A-Fa-f0-9]+)\s*\*\/[\r\n\s]*)?#define\s+([A-Za-z0-9_]+)\s+([^\r\n\/]+)'
    $matches = [regex]::Matches($raw, $regexDef)

    foreach ($m in $matches) {
        $donor = if ($m.Groups[1].Success) { $m.Groups[1].Value.Trim() } else { "inline" }
        $sha   = if ($m.Groups[2].Success) { $m.Groups[2].Value.Trim() } else { "" }
        $name  = $m.Groups[3].Value.Trim()
        $valRaw = $m.Groups[4].Value.Trim().Trim('()')

        $comments[$name] = @{ Donor = $donor; Sha256 = $sha; Raw = $valRaw }

        # Resolve numerical value
        if ($valRaw -match '^0x[0-9A-Fa-f]+[LUlu]*$') {
            $hexStr = $valRaw -replace '[LUlu]', ''
            $defines[$name] = [Convert]::ToUInt64($hexStr, 16)
        }
        elseif ($valRaw -match '^\d+$') {
            $defines[$name] = [uint64]::Parse($valRaw)
        }
        else {
            # Expression or symbolic reference
            $defines[$name] = $valRaw
        }
    }

    # 1b. Parse C enum declarations from windows.h
    $regexEnum = '(?s)enum\s+(?:class\s+)?([A-Za-z0-9_]+)?\s*\{([^}]+)\}'
    $enumMatches = [regex]::Matches($raw, $regexEnum)
    foreach ($em in $enumMatches) {
        $body = $em.Groups[2].Value
        $lines = $body -split "[\r\n]+"
        $currentVal = [uint64]0
        foreach ($line in $lines) {
            $lineClean = ($line -replace '//.*$', '' -replace '/\*.*?\*/', '').Trim()
            if ($lineClean -match '^([A-Za-z0-9_]+)\s*(?:=\s*([^,]+))?') {
                $eName = $Matches[1]
                $eValStr = $Matches[2]
                if ($eValStr) {
                    $eValStr = $eValStr.Trim()
                    if ($eValStr -match '^0x[0-9A-Fa-f]+') {
                        $currentVal = [Convert]::ToUInt64(($eValStr -replace '[LUlu]', ''), 16)
                    }
                    elseif ($eValStr -match '^\d+') {
                        $currentVal = [uint64]::Parse($Matches[0])
                    }
                }
                $defines[$eName] = $currentVal
                $currentVal++
            }
        }
    }

    # Second pass: resolve symbolic references and bitwise OR expressions
    foreach ($k in @($defines.Keys)) {
        if ($defines[$k] -is [string]) {
            $expr = $defines[$k]
            # Strip C integer literal suffixes (e.g. 0x00040000L -> 0x00040000)
            $expr = $expr -replace '(?i)(0x[0-9a-f]+)[lu]+', '$1'
            # Replace defined tokens
            foreach ($subK in $defines.Keys) {
                if ($expr -match "\b$subK\b") {
                    $val = $defines[$subK]
                    if ($val -is [uint64]) {
                        $expr = $expr -replace "\b$subK\b", "0x$($val.ToString('X'))"
                    }
                }
            }
            # Replace C bitwise OR with PowerShell -bor
            $psExpr = $expr -replace '\|', '-bor'
            try {
                $eval = Invoke-Expression $psExpr
                $defines[$k] = [uint64]$eval
            }
            catch {
                # Keep as string if unresolvable
            }
        }
    }

    # 2. Dynamic type system — all sizes introspected from the runtime or parsed from windows.h
    #
    # Sources of truth:
    #   - [System.Runtime.InteropServices.Marshal]::SizeOf() → runtime reports native sizes
    #   - [System.IntPtr]::Size → runtime reports pointer width for target architecture
    #   - typedef chains in windows.h → resolve Windows type aliases
    #   - DECLSPEC_UUID / DX_DECLARE_INTERFACE in SDK donor headers → COM interface GUIDs
    #
    $targetPtrSize = [System.IntPtr]::Size
    $defaultPack = $targetPtrSize

    # C99 stdint.h primitives: map to .NET types, get sizes from the runtime
    $Marshal = [System.Runtime.InteropServices.Marshal]
    $typeMap = @{
        'uint8_t'  = @{ Size = $Marshal::SizeOf([type][byte]);   Type = [byte]   }
        'int8_t'   = @{ Size = $Marshal::SizeOf([type][sbyte]);  Type = [byte]   }
        'uint16_t' = @{ Size = $Marshal::SizeOf([type][uint16]); Type = [uint16] }
        'int16_t'  = @{ Size = $Marshal::SizeOf([type][int16]);  Type = [int16]  }
        'uint32_t' = @{ Size = $Marshal::SizeOf([type][uint32]); Type = [uint32] }
        'int32_t'  = @{ Size = $Marshal::SizeOf([type][int32]);  Type = [int32]  }
        'uint64_t' = @{ Size = $Marshal::SizeOf([type][uint64]); Type = [uint64] }
        'int64_t'  = @{ Size = $Marshal::SizeOf([type][int64]);  Type = [int64]  }
        'float'    = @{ Size = $Marshal::SizeOf([type][single]); Type = [single] }
        'double'   = @{ Size = $Marshal::SizeOf([type][double]); Type = [double] }
        'wchar_t'  = @{ Size = $Marshal::SizeOf([type][char]);   Type = [uint16] }
        'int'      = @{ Size = $Marshal::SizeOf([type][int32]);  Type = [int32]  }
        'void'     = @{ Size = $targetPtrSize;                   Type = [uint64] }
    }

    # Parse typedef aliases from windows.h to resolve Windows types (WORD, DWORD, HWND, etc.)
    $regexTypedef = '(?m)^typedef\s+(?:const\s+)?([A-Za-z0-9_]+)\s*(\*?)\s+([A-Za-z0-9_]+)\s*;'
    $typedefMatches = [regex]::Matches($raw, $regexTypedef)
    # Also match function pointer typedefs (WNDPROC etc.) as pointer-sized
    $regexFnPtr = '(?m)^typedef\s+[A-Za-z0-9_]+\s+\(\*([A-Za-z0-9_]+)\)'
    $fnPtrMatches = [regex]::Matches($raw, $regexFnPtr)

    foreach ($fp in $fnPtrMatches) {
        $fpName = $fp.Groups[1].Value
        $typeMap[$fpName] = @{ Size = $targetPtrSize; Type = [uint64] }
    }

    # Resolve typedef chains: typedef BaseType AliasName;
    # Repeat until stable (handles chains like WCHAR → wchar_t → 2 bytes)
    $resolved = $true
    for ($pass = 0; $pass -lt 4 -and $resolved; $pass++) {
        $resolved = $false
        foreach ($td in $typedefMatches) {
            $baseType = $td.Groups[1].Value
            $isPtr = $td.Groups[2].Value -eq '*'
            $aliasName = $td.Groups[3].Value
            if ($typeMap.ContainsKey($aliasName)) { continue }

            if ($isPtr) {
                $typeMap[$aliasName] = @{ Size = $targetPtrSize; Type = [uint64] }
                $resolved = $true
            }
            elseif ($typeMap.ContainsKey($baseType)) {
                $typeMap[$aliasName] = @{ Size = $typeMap[$baseType].Size; Type = $typeMap[$baseType].Type }
                $resolved = $true
            }
        }
    }

    # Parse pragma pack push/pop ranges in the header
    $packRanges = [Collections.Generic.List[object]]::new()
    foreach ($pm in [regex]::Matches($raw, '(?s)#pragma\s+pack\(push,\s*(\d+)\)(.*?)#pragma\s+pack\(pop\)')) {
        $packRanges.Add(@{ Start = $pm.Index; End = $pm.Index + $pm.Length; Pack = [int]$pm.Groups[1].Value })
    }

    # 3. Dynamic C struct parser from windows.h (supports nested braces for unions)
    $regexStruct = '(?s)typedef\s+struct\s+(?:_?[A-Za-z0-9_]+)?\s*\{((?:[^{}]|\{[^{}]*\})*)\}\s*([A-Za-z0-9_]+)\s*;'
    $structMatches = [regex]::Matches($raw, $regexStruct)

    # First pass: register struct names so they can be referenced as field types
    foreach ($sm in $structMatches) {
        $sName = $sm.Groups[2].Value
        if (-not $typeMap.ContainsKey($sName)) {
            $typeMap[$sName] = @{ Size = 0; Type = [byte[]] }
        }
    }

    $structs = @{}
    foreach ($sm in $structMatches) {
        $packVal = $defaultPack
        foreach ($pr in $packRanges) {
            if ($sm.Index -ge $pr.Start -and $sm.Index -le $pr.End) {
                $packVal = $pr.Pack
                break
            }
        }
        $sName = $sm.Groups[2].Value
        $body = $sm.Groups[1].Value
        $fields = [ordered]@{}
        $currentOffset = 0
        $inUnion = $false
        $unionStart = 0
        $unionMax = 0
        
        $lines = $body -split "[\r\n]+"
        foreach ($line in $lines) {
            $clean = ($line -replace '//.*$', '' -replace '/\*.*?\*/', '').Trim()
            if ($clean -match '^\bunion\b\s*\{?') {
                $inUnion = $true
                $unionStart = $currentOffset
                $unionMax = 0
                continue
            }
            if ($inUnion -and $clean -match '^\}\s*([A-Za-z0-9_]+)?\s*;') {
                $currentOffset = $unionStart + $unionMax
                $inUnion = $false
                continue
            }
            if ($clean -match '^([A-Za-z0-9_]+(?:\s*\*|\b))\s*([A-Za-z0-9_]+)(?:\[(\d+)\])?\s*;') {
                $tName = $Matches[1].Trim().TrimEnd('*').Trim()
                $isPtr = $Matches[1].Contains('*')
                $fName = $Matches[2].Trim()
                $arrLen = if ($Matches[3]) { [int]$Matches[3] } else { 1 }
                
                $entry = if ($isPtr) { @{ Size = $targetPtrSize; Type = [uint64] } } else { $typeMap[$tName] }
                if ($entry -and $entry.Size -gt 0) {
                    $fSize = $entry.Size * $arrLen
                    $align = [Math]::Min($entry.Size, $packVal)
                    if ($inUnion) {
                        $fields[$fName] = @{
                            Offset = $unionStart
                            Size   = $fSize
                            Type   = if ($arrLen -gt 1) { [byte[]] } else { $entry.Type }
                        }
                        if ($fSize -gt $unionMax) { $unionMax = $fSize }
                    } else {
                        if ($currentOffset % $align -ne 0) {
                            $currentOffset += ($align - ($currentOffset % $align))
                        }
                        $fields[$fName] = @{
                            Offset = $currentOffset
                            Size   = $fSize
                            Type   = if ($arrLen -gt 1) { [byte[]] } else { $entry.Type }
                        }
                        $currentOffset += $fSize
                    }
                }
            }
        }
        if ($currentOffset % $packVal -ne 0 -and $currentOffset -gt $packVal) {
            $currentOffset += ($packVal - ($currentOffset % $packVal))
        }
        if ($fields.Count -gt 0) {
            $structs[$sName] = @{ Size = $currentOffset; Fields = $fields }
            $typeMap[$sName] = @{ Size = $currentOffset; Type = [byte[]] }
        }
    }

    $structSizes = @{}
    foreach ($k in $structs.Keys) { $structSizes[$k] = $structs[$k].Size }

    $packFunc = {
        param([string]$structName, [hashtable]$values)
        $def = $structs[$structName]
        if (-not $def) { throw "Unknown struct '$structName' in Windows header specifications." }
        $buf = [byte[]]::new($def.Size)
        $ms = [System.IO.MemoryStream]::new($buf)
        $bw = [System.IO.BinaryWriter]::new($ms)

        foreach ($entry in $def.Fields.GetEnumerator()) {
            $fName = $entry.Key
            $fInfo = $entry.Value
            if ($values.ContainsKey($fName)) {
                $val = $values[$fName]
                $ms.Position = $fInfo.Offset
                if ($fInfo.Type -eq [byte]) {
                    $bw.Write([byte]$val)
                }
                elseif ($fInfo.Type -eq [uint16]) {
                    $bw.Write([uint16]$val)
                }
                elseif ($fInfo.Type -eq [int16]) {
                    $bw.Write([int16]$val)
                }
                elseif ($fInfo.Type -eq [uint32]) {
                    $bw.Write([uint32]$val)
                }
                elseif ($fInfo.Type -eq [int32]) {
                    $bw.Write([int32]$val)
                }
                elseif ($fInfo.Type -eq [uint64]) {
                    $bw.Write([uint64]$val)
                }
                elseif ($fInfo.Type -eq [int64]) {
                    $bw.Write([int64]$val)
                }
                else {
                    if ($val -is [byte[]]) {
                        $bw.Write($val, 0, [Math]::Min($val.Length, $fInfo.Size))
                    }
                }
            }
        }
        return ,$buf
    }.GetNewClosure()

    $res = [PSCustomObject]@{
        Defines     = $defines
        Provenance  = $comments
        Structs     = $structs
        StructSizes = $structSizes
    }
    $res | Add-Member -MemberType ScriptMethod -Name SizeOf -Value ({ param([string]$s) $structs[$s].Size }.GetNewClosure())
    $res | Add-Member -MemberType ScriptMethod -Name OffsetOf -Value ({ param([string]$s, [string]$f) $structs[$s].Fields[$f].Offset }.GetNewClosure())
    $res | Add-Member -MemberType ScriptMethod -Name Pack -Value $packFunc
    return $res
}
