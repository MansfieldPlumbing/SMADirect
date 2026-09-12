[CmdletBinding()]
param(
    [string] $InputScript = (Join-Path $PSScriptRoot 'Test-SmaRyuJitSpine.ps1'),
    [string[]] $ScriptArguments = @(),
    [string] $JitFilter = '*',
    [string] $OutputDirectory,
    [ValidateRange(1, 300)] [int] $TimeoutSeconds = 60,
    [switch] $Headless
)

# Capture the shipped JIT's own output. This is not a SuperPMI MethodContext:
# allocMem, relocations, GC records and callback counts remain unknown here.
# Official mechanism: dotnet/runtime docs/design/coreclr/jit/viewing-jit-dumps.md
# and src/coreclr/jit/jitconfigvalues.h (release JitDisasm options).
if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference = 'Stop'
$ownedDirectory = -not $OutputDirectory
$captureDirectory = if ($ownedDirectory) {
    Join-Path ([IO.Path]::GetTempPath()) ('sma-jit-capture-' + [guid]::NewGuid().ToString('N'))
} else {
    [IO.Path]::GetFullPath($OutputDirectory)
}
$process = $null
try {
    $inputPath = [IO.Path]::GetFullPath($InputScript)
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "MISSING_PREREQUISITE: SMA spine verifier not found: $inputPath. Supply -InputScript with the authentic SMA-to-RyuJIT verifier."
    }
    $null = New-Item -ItemType Directory -Path $captureDirectory -Force
    $disasmPath = Join-Path $captureDirectory 'native-disasm.txt'
    $manifestPath = Join-Path $captureDirectory 'capture.json'
    if ((Test-Path -LiteralPath $disasmPath) -or (Test-Path -LiteralPath $manifestPath)) {
        throw "OUTPUT_ALREADY_EXISTS: Use an empty -OutputDirectory: $captureDirectory"
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Join-Path $PSHOME 'pwsh.exe'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $inputPath) + $ScriptArguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $captureEnvironment = [ordered]@{
        DOTNET_JitDump = $JitFilter
        DOTNET_JitDisasmTesting = '1'
        DOTNET_JitDisasmWithCodeBytes = '1'
        DOTNET_JitStdOutFile = $disasmPath
        DOTNET_TieredCompilation = '0'
    }
    foreach ($setting in $captureEnvironment.GetEnumerator()) {
        $startInfo.Environment[$setting.Key] = $setting.Value
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw "CAPTURE_TIMEOUT: Bounded headless verifier exceeded $TimeoutSeconds seconds."
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $disasmExists = Test-Path -LiteralPath $disasmPath -PathType Leaf
    $disasmBytes = if ($disasmExists) { (Get-Item -LiteralPath $disasmPath).Length } else { 0 }
    $runtimeIdentity = [object].Assembly.GetCustomAttributesData() |
        Where-Object { $_.AttributeType.FullName -eq 'System.Reflection.AssemblyInformationalVersionAttribute' } |
        ForEach-Object { $_.ConstructorArguments[0].Value }
    $collectorPath = Join-Path $PSHOME 'superpmi-shim-collector.dll'
    $result = [pscustomobject][ordered]@{
        CaptureMechanism = 'RyuJIT_JitDisasm'
        CapturePass = ($process.ExitCode -eq 0 -and $disasmBytes -gt 0)
        SuperPmiCapture = 'NOT_CAPTURED'
        CollectorPresentBesideRuntime = (Test-Path -LiteralPath $collectorPath -PathType Leaf)
        RuntimeIdentity = $runtimeIdentity
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PowerShellPath = $startInfo.FileName
        JitPath = (Join-Path $PSHOME 'clrjit.dll')
        JitSha256 = (Get-FileHash -LiteralPath (Join-Path $PSHOME 'clrjit.dll') -Algorithm SHA256).Hash
        InputScript = $inputPath
        InputSha256 = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash
        ScriptArguments = $ScriptArguments
        Environment = $captureEnvironment
        ChildExitCode = $process.ExitCode
        StandardOutput = $stdout
        StandardError = $stderr
        DisassemblyPath = $(if (-not $ownedDirectory) { $disasmPath } else { $null })
        DisassemblyBytes = $disasmBytes
        AllocationBoundaries = 'UNKNOWN'
        Relocations = 'UNKNOWN'
        CallbackInventory = 'UNKNOWN'
        GcInfoBytes = 'UNKNOWN'
        UnwindRecords = 'UNKNOWN'
        EhRecords = 'UNKNOWN'
    }
    if (-not $ownedDirectory) {
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    }
    if (-not $result.CapturePass) {
        throw "CAPTURE_FAIL: child exit=$($process.ExitCode), disassembly bytes=$disasmBytes. $stderr $stdout"
    }
    $result
} finally {
    if ($process) { $process.Dispose() }
    if ($ownedDirectory -and (Test-Path -LiteralPath $captureDirectory -PathType Container)) {
        # Only this invocation's validated, uniquely created temporary directory.
        $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        $actualParent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($captureDirectory)).TrimEnd('\')
        if ($actualParent -ne $expectedParent -or [IO.Path]::GetFileName($captureDirectory) -notmatch '^sma-jit-capture-[0-9a-f]{32}$') {
            throw 'TEMP_CLEANUP_REFUSED: Capture directory is outside the owned temporary location.'
        }
        Remove-Item -LiteralPath $captureDirectory -Recurse -Force
    }
}
