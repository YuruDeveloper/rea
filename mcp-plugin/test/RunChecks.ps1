param(
    [Parameter(Mandatory)][string]$InstallDirectory,
    [Parameter(Mandatory)][string]$Binary,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$PlatformDirectory = (Join-Path $InstallDirectory 'qtplugins\platforms'),
    [string]$ProgramName = 'rea.exe',
    [int]$StartSeconds = 60
)

$ErrorActionPreference = 'Stop'

$Platform = 'offscreen'
$RefusedExitCode = 2
$Program = Join-Path $InstallDirectory $ProgramName
$PlatformFile = Join-Path $PlatformDirectory "q$Platform.dll"
$ProgramArguments = @('-A', '1', "`"$Binary`"")
$PowerShellProgram = (Get-Process -Id $PID).Path

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

function Invoke-Check {
    param([string]$Label, [string[]]$Arguments)
    $Log = Join-Path $OutputDirectory "$Label.log"
    $Check = Start-Process -FilePath $PowerShellProgram -NoNewWindow -Wait -PassThru `
        -ArgumentList (@('-NoProfile', '-File') + $Arguments) `
        -RedirectStandardOutput $Log -RedirectStandardError (Join-Path $OutputDirectory "$Label.err.log")
    Add-Content -Encoding utf8 -LiteralPath $Log "exit=$($Check.ExitCode)"
    Write-Host "== $Label exit=$($Check.ExitCode) log=$Log"
    return $Check.ExitCode
}

foreach ($Required in $Program, $PlatformFile, $Binary) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) {
        Stop-Refused "This file is missing: $Required"
    }
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$ProfileDirectory = Join-Path $OutputDirectory 'profile'
$RoamingDirectory = Join-Path $ProfileDirectory 'AppData\Roaming'
$LocalDirectory = Join-Path $ProfileDirectory 'AppData\Local'
New-Item -ItemType Directory -Force $RoamingDirectory, $LocalDirectory | Out-Null

Add-Type -Namespace ReaCheck -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);'
[void][ReaCheck.Native]::SetErrorMode(0x8007)

$env:QT_QPA_PLATFORM = $Platform
$env:QT_QPA_PLATFORM_PLUGIN_PATH = $PlatformDirectory
$env:USERPROFILE = $ProfileDirectory
$env:APPDATA = $RoamingDirectory
$env:LOCALAPPDATA = $LocalDirectory
$env:REA_MCP_DIR = $null
$env:SLEIGHHOME = Join-Path $InstallDirectory 'lib\rizin\plugins\rz_ghidra_sleigh'

$Stamp = @("time=$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))", (Get-Stamp $Program), (Get-Stamp $PlatformFile))
$Stamp += Get-ChildItem -LiteralPath (Join-Path $InstallDirectory 'plugins\native') -Filter '*.dll' -File |
    ForEach-Object { Get-Stamp $_.FullName }
$Stamp += "QT_QPA_PLATFORM=$env:QT_QPA_PLATFORM"
$Stamp += "profile=$ProfileDirectory"

$Process = Start-Process -FilePath $Program -ArgumentList $ProgramArguments -WorkingDirectory $InstallDirectory `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput (Join-Path $OutputDirectory 'program.stdout.txt') `
    -RedirectStandardError (Join-Path $OutputDirectory 'program.stderr.txt')
$null = $Process.Handle
$Stamp += "pid=$($Process.Id)"
$ExitCodes = @()

try {
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
    $ModuleNames = @($Process.Modules | ForEach-Object { $_.ModuleName.ToLowerInvariant() })
    $Stamp += "window handle=$($Process.MainWindowHandle)"
    $Stamp += "platform modules=$(($ModuleNames | Where-Object { $_ -in 'qoffscreen.dll', 'qwindows.dll' }) -join ',')"
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
    if ($Process.HasExited) {
        $Stamp += "the program ended with the exit code $($Process.ExitCode)"
    }
    else {
        $Process.Kill()
        $Process.WaitForExit()
        $Stamp += "stopped process $($Process.Id)"
    }
    $Stamp | Set-Content -Encoding utf8 -LiteralPath (Join-Path $OutputDirectory 'stamp.txt')
    $Stamp | Write-Host
}

$Failed = @($ExitCodes | Where-Object { $_ -ne 0 }).Count
Write-Host "exit=$Failed"
exit $Failed
