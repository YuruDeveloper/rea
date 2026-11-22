param(
    [string]$ConnectionDirectory = $env:REA_MCP_DIR,
    [int]$ProcessId = 0
)

$ErrorActionPreference = 'Stop'

if (-not $ConnectionDirectory) {
    $LocalDataDirectory = [Environment]::GetFolderPath('LocalApplicationData', 'DoNotVerify')
    $ConnectionDirectory = Join-Path $LocalDataDirectory 'rea\rea\mcp'
}

$Utf8 = [Text.UTF8Encoding]::new($false)
$Reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), $Utf8)
$Writer = [IO.StreamWriter]::new([Console]::OpenStandardOutput(), $Utf8)
$Writer.NewLine = "`n"
$Writer.AutoFlush = $true

$Handler = [Net.Http.SocketsHttpHandler]::new()
$Handler.UseProxy = $false
$Handler.AllowAutoRedirect = $false
$Client = [Net.Http.HttpClient]::new($Handler)
$Client.Timeout = [Threading.Timeout]::InfiniteTimeSpan

$StartSlackSeconds = 2
$RelayErrorCode = -32000
$script:Current = $null

function Write-Diagnostic {
    param([string]$Text)
    [Console]::Error.WriteLine("rea-mcp relay: $Text")
}

function Test-ServerProcess {
    param([int]$Id, [DateTimeOffset]$StartedAt)
    $Process = Get-Process -Id $Id -ErrorAction SilentlyContinue
    if (-not $Process) {
        return $false
    }
    try {
        $ProcessStart = [DateTimeOffset]$Process.StartTime
    }
    catch {
        return $false
    }
    return $ProcessStart -le $StartedAt.AddSeconds($StartSlackSeconds)
}

function Read-ConnectionFile {
    param([string]$Path)
    try {
        $Document = [Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText($Path))
        $Root = $Document.RootElement
        $Url = [Uri]$Root.GetProperty('url').GetString()
        $StartedAt = [DateTimeOffset]::Parse($Root.GetProperty('startedAt').GetString(),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal)
        $Connection = [pscustomobject]@{
            Path      = $Path
            Url       = $Url
            Token     = $Root.GetProperty('token').GetString()
            ProcessId = $Root.GetProperty('pid').GetInt32()
            StartedAt = $StartedAt
        }
    }
    catch {
        Write-Diagnostic "skipped a connection file that could not be read: $Path"
        return $null
    }
    if ($Url.Scheme -ne 'http' -or $Url.Host -ne '127.0.0.1') {
        Write-Diagnostic "skipped a connection file whose URL is not on 127.0.0.1: $Path"
        return $null
    }
    return $Connection
}

function Find-Connection {
    if (-not (Test-Path -LiteralPath $ConnectionDirectory -PathType Container)) {
        return $null
    }
    $Live = @()
    foreach ($File in Get-ChildItem -LiteralPath $ConnectionDirectory -Filter 'server-*.json' -File) {
        $Connection = Read-ConnectionFile $File.FullName
        if (-not $Connection) {
            continue
        }
        if ($ProcessId -ne 0 -and $Connection.ProcessId -ne $ProcessId) {
            continue
        }
        if (-not (Test-ServerProcess $Connection.ProcessId $Connection.StartedAt)) {
            Write-Diagnostic "skipped the connection file of a session that ended:$($File.FullName)"
            continue
        }
        $Live += $Connection
    }
    if ($Live.Count -eq 0) {
        return $null
    }
    $Newest = @($Live | Sort-Object StartedAt -Descending)[0]
    if ($Live.Count -gt 1) {
        Write-Diagnostic "found $($Live.Count) sessions and selected process $($Newest.ProcessId). Use -ProcessId to select another."
    }
    return $Newest
}

function Get-Connection {
    $Known = $script:Current
    if ($Known -and (Test-ServerProcess $Known.ProcessId $Known.StartedAt)) {
        return $Known
    }
    $script:Current = Find-Connection
    return $script:Current
}

function Get-ReplyId {
    param([string]$Line)
    try {
        $Root = [Text.Json.JsonDocument]::Parse($Line).RootElement
    }
    catch {
        return 'null'
    }
    $Id = [Text.Json.JsonElement]::new()
    $Method = [Text.Json.JsonElement]::new()
    if ($Root.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
        return 'null'
    }
    if (-not $Root.TryGetProperty('id', [ref]$Id) -or -not $Root.TryGetProperty('method', [ref]$Method)) {
        return $null
    }
    return $Id.GetRawText()
}

function Format-RelayError {
    param([string]$ReplyId, [string]$Message)
    if (-not $ReplyId) {
        return $null
    }
    Write-Diagnostic $Message
    return '{"jsonrpc":"2.0","id":' + $ReplyId + ',"error":{"code":' + $RelayErrorCode +
        ',"message":' + (ConvertTo-Json -InputObject $Message -Compress) + '}}'
}

function Test-JsonRpcText {
    param([string]$Text)
    try {
        $Root = [Text.Json.JsonDocument]::Parse($Text).RootElement
    }
    catch {
        return $false
    }
    $Version = [Text.Json.JsonElement]::new()
    return $Root.ValueKind -eq [Text.Json.JsonValueKind]::Object -and $Root.TryGetProperty('jsonrpc', [ref]$Version)
}

function Invoke-Relay {
    param([string]$Line)
    $ReplyId = Get-ReplyId $Line
    $Connection = Get-Connection
    if (-not $Connection) {
        return Format-RelayError $ReplyId "No session is open. Start the program, open a binary, then send the request again. The connection folder is $ConnectionDirectory"
    }

    $Request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, $Connection.Url)
    [void]$Request.Headers.TryAddWithoutValidation('Authorization', "Bearer $($Connection.Token)")
    [void]$Request.Headers.TryAddWithoutValidation('Accept', 'application/json, text/event-stream')
    $Request.Content = [Net.Http.StringContent]::new($Line, $Utf8, 'application/json')
    try {
        $Response = $Client.Send($Request)
        $Status = [int]$Response.StatusCode
        $Text = $Utf8.GetString($Response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult())
    }
    catch {
        $script:Current = $null
        return Format-RelayError $ReplyId "The request to the session of process $($Connection.ProcessId) failed: $($_.Exception.GetBaseException().Message)"
    }

    if ($Status -eq 202) {
        return $null
    }
    if (Test-JsonRpcText $Text) {
        return $Text -replace '[\r\n]+', ' '
    }
    return Format-RelayError $ReplyId "The session of process $($Connection.ProcessId) answered HTTP $Status."
}

while ($null -ne ($Line = $Reader.ReadLine())) {
    if (-not $Line.Trim()) {
        continue
    }
    $Reply = Invoke-Relay $Line
    if ($Reply) {
        $Writer.WriteLine($Reply)
    }
}
