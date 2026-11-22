param(
    [Parameter(Mandatory)][string]$InstallDirectory,
    [Parameter(Mandatory)][string]$Binary,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$PlatformDirectory,
    [string]$LegacySettingsKey,
    [string]$ProgramName = 'rea.exe',
    [int]$StartSeconds = 60
)

$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([string]$Path)
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

$Platform = 'offscreen'
$RefusedExitCode = 2
$ErrorMode = 0x8007
$FixedSettingsKey = 'HKCU:\Software\Cutter\Cutter'
$InstallDirectory = Get-FullPath $InstallDirectory
$Binary = Get-FullPath $Binary
$OutputDirectory = Get-FullPath $OutputDirectory
$PlatformDirectory = if ($PlatformDirectory) { Get-FullPath $PlatformDirectory } else { Join-Path $InstallDirectory 'qtplugins\platforms' }
$Program = Join-Path $InstallDirectory $ProgramName
$PlatformFile = Join-Path $PlatformDirectory "q$Platform.dll"
$ProfileDirectory = Join-Path $OutputDirectory 'profile'
$RoamingDirectory = Join-Path $ProfileDirectory 'AppData\Roaming'
$LocalDirectory = Join-Path $ProfileDirectory 'AppData\Local'
$CallerDirectory = (Get-Location).ProviderPath
$PowerShellProgram = (Get-Process -Id $PID).Path
$ChildEnvironment = [ordered]@{
    QT_QPA_PLATFORM             = $Platform
    QT_QPA_PLATFORM_PLUGIN_PATH = $PlatformDirectory
    USERPROFILE                 = $ProfileDirectory
    APPDATA                     = $RoamingDirectory
    LOCALAPPDATA                = $LocalDirectory
    SLEIGHHOME                  = Join-Path $InstallDirectory 'lib\rizin\plugins\rz_ghidra_sleigh'
}
$RemovedVariables = @('REA_MCP_DIR')

function Stop-Refused {
    param([string]$Reason)
    Write-Host "The program was not started. $Reason"
    Write-Host "exit=$RefusedExitCode"
    exit $RefusedExitCode
}

function Get-Stamp {
    param([string]$Path)
    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return "$Path sha256=$Hash mtime=$($Item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff zzz')) size=$($Item.Length)"
}

function Start-Child {
    param([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory)
    $Start = [Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($Argument in $Arguments) {
        $Start.ArgumentList.Add($Argument)
    }
    $Start.WorkingDirectory = $WorkingDirectory
    $Start.UseShellExecute = $false
    $Start.CreateNoWindow = $true
    $Start.RedirectStandardOutput = $true
    $Start.RedirectStandardError = $true
    foreach ($Name in $ChildEnvironment.Keys) {
        $Start.Environment[$Name] = $ChildEnvironment[$Name]
    }
    foreach ($Name in $RemovedVariables) {
        [void]$Start.Environment.Remove($Name)
    }
    $Process = [Diagnostics.Process]::Start($Start)
    return [pscustomobject]@{
        Process = $Process
        Output  = $Process.StandardOutput.ReadToEndAsync()
        Error   = $Process.StandardError.ReadToEndAsync()
    }
}

function Save-Output {
    param($Child, [string]$OutputFile, [string]$ErrorFile)
    [IO.File]::WriteAllText($OutputFile, $Child.Output.Result)
    [IO.File]::WriteAllText($ErrorFile, $Child.Error.Result)
}

function Invoke-Check {
    param([string]$Label, [string[]]$Arguments)
    $Log = Join-Path $OutputDirectory "$Label.log"
    $Check = Start-Child $PowerShellProgram (@('-NoProfile', '-File') + $Arguments) $CallerDirectory
    $Check.Process.WaitForExit()
    Save-Output $Check $Log (Join-Path $OutputDirectory "$Label.err.log")
    Add-Content -Encoding utf8 -LiteralPath $Log "exit=$($Check.Process.ExitCode)"
    Write-Host "== $Label exit=$($Check.Process.ExitCode) log=$Log"
    return $Check.Process.ExitCode
}

foreach ($Required in $Program, $PlatformFile, $Binary) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Refused "This file is missing: $Required"
    }
}
$SettingsKeys = foreach ($KeyPath in @($FixedSettingsKey, $LegacySettingsKey) | Where-Object { $_ }) {
    $Key = if (Test-Path -LiteralPath $KeyPath) { Get-Item -LiteralPath $KeyPath }
    [pscustomobject]@{
        Path    = $KeyPath
        Exists  = [bool]$Key
        NotAKey = $Key -and $Key -isnot [Microsoft.Win32.RegistryKey]
        Values  = [int]$Key.ValueCount
        SubKeys = [int]$Key.SubKeyCount
    }
}
$SettingsLines = @($SettingsKeys | ForEach-Object { "settings key $($_.Path) exists=$($_.Exists) values=$($_.Values) subkeys=$($_.SubKeys)" })
$SettingsLines | Write-Host
$WrongPaths = @($SettingsKeys | Where-Object { $_.NotAKey })
if ($WrongPaths.Count -gt 0) {
    Stop-Refused "These paths are not registry keys: $($WrongPaths.Path -join ', ')"
}
$FilledKeys = @($SettingsKeys | Where-Object { $_.Values -gt 0 -or $_.SubKeys -gt 0 })
if ($FilledKeys.Count -gt 0) {
    Stop-Refused ("These registry keys contain values or keys: $($FilledKeys.Path -join ', '). " +
        'With an empty profile, the program moves the old settings of Cutter into the profile and deletes them from the registry.')
}

New-Item -ItemType Directory -Force $RoamingDirectory, $LocalDirectory | Out-Null

$Stamp = @("time=$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))", (Get-Stamp $Program), (Get-Stamp $PlatformFile))
$Stamp += Get-ChildItem -LiteralPath (Join-Path $InstallDirectory 'plugins\native') -Filter '*.dll' -File |
    ForEach-Object { Get-Stamp $_.FullName }
$Stamp += "binary=$Binary"
$Stamp += $ChildEnvironment.Keys | ForEach-Object { "$_=$($ChildEnvironment[$_])" }
$Stamp += "profile=$ProfileDirectory"
$Stamp += $SettingsLines

Add-Type -Namespace ReaCheck -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);'
$PreviousErrorMode = [ReaCheck.Native]::SetErrorMode($ErrorMode)
$Run = $null
$ExitCodes = @()

try {
    $Run = Start-Child $Program @('-A', '1', $Binary) $InstallDirectory
    $Process = $Run.Process
    $Stamp += "pid=$($Process.Id)"
    $ConnectionFile = $null
    $Deadline = (Get-Date).AddSeconds($StartSeconds)
    while (-not $ConnectionFile -and -not $Process.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 500
        $ConnectionFile = [IO.Directory]::GetFiles($LocalDirectory, "server-$($Process.Id).json", 'AllDirectories') |
            Select-Object -First 1
    }
    $Stamp += "connection=$ConnectionFile"
    if ($Process.HasExited) {
        throw "The program ended before the checks, with the exit code $($Process.ExitCode) (0x$($Process.ExitCode.ToString('X8')))."
    }
    $Process.Refresh()
    $PlatformModules = @($Process.Modules | Where-Object { $_.ModuleName -in 'qoffscreen.dll', 'qwindows.dll' })
    $ModuleNames = @($PlatformModules | ForEach-Object { $_.ModuleName.ToLowerInvariant() })
    $Stamp += "window handle=$($Process.MainWindowHandle)"
    $Stamp += "platform modules=$($ModuleNames -join ',')"
    $Stamp += "platform module files=$(($PlatformModules | ForEach-Object { $_.FileName }) -join ',')"
    if ($Process.MainWindowHandle -ne [IntPtr]::Zero -or $ModuleNames -contains 'qwindows.dll' -or $ModuleNames -notcontains "q$Platform.dll") {
        throw "The program does not use the Qt platform $Platform."
    }
    if (-not $ConnectionFile) {
        throw "The connection file did not appear in $StartSeconds seconds."
    }
    $ExitCodes += Invoke-Check 'check-server' @(
        (Join-Path $PSScriptRoot 'CheckServer.ps1'),
        '-ConnectionFile', $ConnectionFile,
        '-OutputDirectory', (Join-Path $OutputDirectory 'check-server'))
    $ExitCodes += Invoke-Check 'check-relay' @(
        (Join-Path $PSScriptRoot 'CheckRelay.ps1'),
        '-OutputDirectory', (Join-Path $OutputDirectory 'check-relay'),
        '-ConnectionDirectory', (Split-Path $ConnectionFile),
        '-DefaultSession')
}
catch {
    Write-Host "FAIL  $($_.Exception.Message)"
    $ExitCodes += 1
}
finally {
    [void][ReaCheck.Native]::SetErrorMode($PreviousErrorMode)
    if ($Run) {
        if ($Run.Process.HasExited) {
            $Stamp += "the program ended with the exit code $($Run.Process.ExitCode)"
        }
        else {
            $Run.Process.Kill()
            $Run.Process.WaitForExit()
            $Stamp += "stopped process $($Run.Process.Id)"
        }
        Save-Output $Run (Join-Path $OutputDirectory 'program.stdout.txt') (Join-Path $OutputDirectory 'program.stderr.txt')
    }
    $Stamp | Set-Content -Encoding utf8 -LiteralPath (Join-Path $OutputDirectory 'stamp.txt')
    $Stamp | Write-Host
}

$Failed = @($ExitCodes | Where-Object { $_ -ne 0 }).Count
Write-Host "exit=$Failed"
exit $Failed
