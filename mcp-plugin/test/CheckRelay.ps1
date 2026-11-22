param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ConnectionDirectory,
    [switch]$DefaultSession
)

$ErrorActionPreference = 'Stop'

$RelayScript = Join-Path (Split-Path $PSScriptRoot) 'StdioRelay.ps1'
$PowerShellProgram = (Get-Process -Id $PID).Path
$Utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null

$script:Failures = @()

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "ok    $Message"
    }
    else {
        Write-Host "FAIL  $Message"
        $script:Failures += $Message
    }
}

function Invoke-RelayRun {
    param([string]$Name, [string]$Directory, [string[]]$InputLines, [int]$SelectedProcessId = 0)
    $Prefix = Join-Path $OutputDirectory $Name
    [IO.File]::WriteAllText("$Prefix.stdin.txt", (($InputLines -join "`n") + "`n"), $Utf8)
    $Arguments = @('-NoProfile', '-File', "`"$RelayScript`"", '-ProcessId', $SelectedProcessId)
    if ($Directory) {
        $Arguments += @('-ConnectionDirectory', "`"$Directory`"")
    }
    $SavedDirectory = $env:REA_MCP_DIR
    $env:REA_MCP_DIR = $null
    try {
        $Process = Start-Process -FilePath $PowerShellProgram -NoNewWindow -Wait -PassThru `
            -ArgumentList $Arguments `
            -RedirectStandardInput "$Prefix.stdin.txt" `
            -RedirectStandardOutput "$Prefix.stdout.txt" `
            -RedirectStandardError "$Prefix.stderr.txt"
    }
    finally {
        $env:REA_MCP_DIR = $SavedDirectory
    }
    $OutputLines = @([IO.File]::ReadAllLines("$Prefix.stdout.txt", $Utf8) | Where-Object { $_ })
    return [pscustomobject]@{
        ExitCode = $Process.ExitCode
        Lines    = $OutputLines
        Replies  = @($OutputLines | ForEach-Object { $_ | ConvertFrom-Json })
        Errors   = [IO.File]::ReadAllText("$Prefix.stderr.txt", $Utf8)
    }
}

function Write-ConnectionFile {
    param([string]$Directory, [int]$Id, [string]$Url, [DateTimeOffset]$StartedAt)
    New-Item -ItemType Directory -Force $Directory | Out-Null
    $Content = [ordered]@{
        url       = $Url
        token     = 'check-relay-token'
        pid       = $Id
        startedAt = $StartedAt.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
    } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $Directory "server-$Id.json"), $Content, $Utf8)
}

$InitializeLine = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"CheckRelay","version":"1"}}}'
$InitializedLine = '{"jsonrpc":"2.0","method":"notifications/initialized"}'
$ToolListLine = '{"jsonrpc":"2.0","id":"list","method":"tools/list"}'
$ToolCallLine = '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_functions","arguments":{"limit":3}}}'
$ClosedPortUrl = 'http://127.0.0.1:1/mcp'
$Now = [DateTimeOffset]::UtcNow
$OwnStart = [DateTimeOffset](Get-Process -Id $PID).StartTime

$EmptyDirectory = Join-Path $OutputDirectory 'connections-empty'
New-Item -ItemType Directory -Force $EmptyDirectory | Out-Null
$Empty = Invoke-RelayRun -Name 'no-session' -Directory $EmptyDirectory -InputLines @($InitializeLine, $InitializedLine, '', $ToolListLine)
Assert-That ($Empty.ExitCode -eq 0) 'without a session, the relay ends with the exit code 0 at the end of the input'
Assert-That ($Empty.Replies.Count -eq 2) 'without a session, the relay answers each request and does not answer the notification'
Assert-That ($Empty.Replies[0].id -eq 1 -and $Empty.Replies[0].error.code -eq -32000) 'without a session, the relay returns the error -32000 with the number id of the request'
Assert-That ($Empty.Replies[1].id -eq 'list' -and $Empty.Replies[1].error.code -eq -32000) 'without a session, the relay returns the error -32000 with the string id of the request'

$DeadDirectory = Join-Path $OutputDirectory 'connections-dead'
$DeadProcess = Start-Process -FilePath $PowerShellProgram -ArgumentList @('-NoProfile', '-Command', 'exit') -NoNewWindow -Wait -PassThru
Write-ConnectionFile -Directory $DeadDirectory -Id $DeadProcess.Id -Url $ClosedPortUrl -StartedAt $Now
$Dead = Invoke-RelayRun -Name 'dead-process' -Directory $DeadDirectory -InputLines @($ToolListLine)
Assert-That ($Dead.Replies.Count -eq 1 -and $Dead.Replies[0].error.message -match '^No session is open') 'the relay skips the connection file of a process that ended'

$MainSource = [IO.File]::ReadAllText((Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'src\Main.cpp'))
$OrganizationName = [regex]::Match($MainSource, 'setOrganizationName\("([^"]+)"\)').Groups[1].Value
$ApplicationName = [regex]::Match($MainSource, 'setApplicationName\("([^"]+)"\)').Groups[1].Value
$LocalDataDirectory = [Environment]::GetFolderPath('LocalApplicationData', 'DoNotVerify')
$DefaultDirectory = Join-Path $LocalDataDirectory "$OrganizationName\$ApplicationName\mcp"
$Default = Invoke-RelayRun -Name 'default-directory' -Directory '' -InputLines @($ToolListLine) -SelectedProcessId $DeadProcess.Id
Assert-That ($OrganizationName -and $ApplicationName) 'the file src/Main.cpp gives the organization name and the program name'
Assert-That ($Default.Replies.Count -eq 1 -and "$($Default.Replies[0].error.message)".EndsWith("The connection folder is $DefaultDirectory")) 'without -ConnectionDirectory and REA_MCP_DIR, the relay uses the data folder of the program that src/Main.cpp names'

$ReusedDirectory = Join-Path $OutputDirectory 'connections-reused'
Write-ConnectionFile -Directory $ReusedDirectory -Id $PID -Url $ClosedPortUrl -StartedAt $OwnStart.AddMinutes(-10)
$Reused = Invoke-RelayRun -Name 'reused-process-id' -Directory $ReusedDirectory -InputLines @($ToolListLine)
Assert-That ($Reused.Replies.Count -eq 1 -and $Reused.Replies[0].error.message -match '^No session is open') 'the relay skips the connection file when the process started after the file'

$RemoteDirectory = Join-Path $OutputDirectory 'connections-remote'
Write-ConnectionFile -Directory $RemoteDirectory -Id $PID -Url 'http://192.0.2.1:1/mcp' -StartedAt $Now
$Remote = Invoke-RelayRun -Name 'remote-url' -Directory $RemoteDirectory -InputLines @($ToolListLine)
Assert-That ($Remote.Replies.Count -eq 1 -and $Remote.Replies[0].error.message -match '^No session is open') 'the relay skips a connection file whose URL is not on 127.0.0.1'
Assert-That ($Remote.Errors -notmatch 'check-relay-token') 'the relay does not write the token to the error output'

$ClosedDirectory = Join-Path $OutputDirectory 'connections-closed-port'
Write-ConnectionFile -Directory $ClosedDirectory -Id $PID -Url $ClosedPortUrl -StartedAt $Now
$Closed = Invoke-RelayRun -Name 'closed-port' -Directory $ClosedDirectory -InputLines @($ToolListLine, $InitializedLine, 'not json')
Assert-That ($Closed.Replies.Count -eq 2) 'when the connection fails, the relay answers the request and the line that is not JSON'
Assert-That ($Closed.Replies[0].id -eq 'list' -and $Closed.Replies[0].error.message -match 'failed') 'when the connection fails, the relay returns an error for the request'
Assert-That ($null -eq $Closed.Replies[1].id -and $Closed.Replies[1].error.code -eq -32000) 'when the connection fails, the relay returns an error with the id null for the line that is not JSON'
Assert-That ($Closed.Errors -notmatch 'check-relay-token' -and ($Closed.Lines -join '') -notmatch 'check-relay-token') 'the relay does not write the token to an output'

$TwoDirectory = Join-Path $OutputDirectory 'connections-two-sessions'
$OlderProcess = Start-Process -FilePath $PowerShellProgram -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120') -NoNewWindow -PassThru
try {
    Write-ConnectionFile -Directory $TwoDirectory -Id $OlderProcess.Id -Url $ClosedPortUrl -StartedAt ([DateTimeOffset]::UtcNow)
    Write-ConnectionFile -Directory $TwoDirectory -Id $PID -Url $ClosedPortUrl -StartedAt ([DateTimeOffset]::UtcNow.AddMinutes(1))
    $Newest = Invoke-RelayRun -Name 'two-sessions-newest' -Directory $TwoDirectory -InputLines @($ToolListLine)
    Assert-That ($Newest.Errors -match "found 2 sessions and selected process $PID\.") 'with two sessions, the relay selects the session that started last'
    Assert-That ($Newest.Replies[0].error.message -match "process $PID failed") 'with two sessions, the relay sends the request to the session that started last'
    $Selected = Invoke-RelayRun -Name 'two-sessions-selected' -Directory $TwoDirectory -InputLines @($ToolListLine) -SelectedProcessId $OlderProcess.Id
    Assert-That ($Selected.Replies[0].error.message -match "process $($OlderProcess.Id) failed") 'with -ProcessId, the relay sends the request to the selected session'
    Assert-That ($Selected.Errors -notmatch 'found 2 sessions') 'with -ProcessId, the relay does not use the other session'
}
finally {
    Stop-Process -Id $OlderProcess.Id -Force
}

if ($ConnectionDirectory) {
    $Session = Invoke-RelayRun -Name 'session' -Directory $ConnectionDirectory -InputLines @($InitializeLine, $InitializedLine, $ToolListLine, $ToolCallLine, 'not json')
    Assert-That ($Session.ExitCode -eq 0) 'with a session, the relay ends with the exit code 0 at the end of the input'
    Assert-That ($Session.Replies.Count -eq 4) 'with a session, the relay writes one line for each request and no line for the notification'
    Assert-That ($Session.Replies[0].id -eq 1 -and $Session.Replies[0].result.serverInfo.name -eq 'rea-mcp') 'with a session, the relay returns the initialize result of the server'
    Assert-That ($Session.Replies[1].id -eq 'list' -and @($Session.Replies[1].result.tools).Count -gt 0) 'with a session, the relay returns the tool list'
    Assert-That ($Session.Replies[2].id -eq 3 -and $Session.Replies[2].result.isError -eq $false) 'with a session, the relay returns the result of a tool call'
    Assert-That ($Session.Replies[2].result.content[0].text.StartsWith('{"dataNotice":')) 'with a session, the tool result keeps the data notice before the data'
    Assert-That ($Session.Replies[3].error.code -eq -32700) 'with a session, the relay returns the parse error of the server for the line that is not JSON'
}
else {
    Write-Host 'skip  the checks with a session, because -ConnectionDirectory was not given'
}

if ($DefaultSession) {
    $Found = Invoke-RelayRun -Name 'default-session' -Directory '' -InputLines @($InitializeLine, $InitializedLine, $ToolListLine)
    Assert-That ($Found.Replies.Count -eq 2 -and $Found.Replies[0].result.serverInfo.name -eq 'rea-mcp') 'without -ConnectionDirectory and REA_MCP_DIR, the relay finds the session in the default folder of the server'
    Assert-That ($Found.Replies.Count -eq 2 -and @($Found.Replies[1].result.tools).Count -gt 0) 'without -ConnectionDirectory and REA_MCP_DIR, the relay returns the tool list'
}
else {
    Write-Host 'skip  the checks with a session in the default folder, because -DefaultSession was not given'
}

if ($script:Failures.Count -gt 0) {
    Write-Host "== $($script:Failures.Count) check(s) failed"
    exit 1
}
Write-Host '== All checks passed'
exit 0
