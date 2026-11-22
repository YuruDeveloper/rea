param(
    [Parameter(Mandatory)][string]$ConnectionFile,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$FunctionFilter = 'main',
    [string]$ExpectedFunction = 'sym.main'
)

$ErrorActionPreference = 'Stop'

$Connection = Get-Content -Raw $ConnectionFile | ConvertFrom-Json
$Url = $Connection.url
$Token = $Connection.token
$Port = ([Uri]$Url).Port
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null

$script:Sequence = 0
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

function Invoke-Exchange {
    param(
        [string]$Name,
        [string]$Method = 'Post',
        [string]$Target = $Url,
        [hashtable]$Headers = @{ Authorization = "Bearer $Token" },
        [string]$Body
    )
    $script:Sequence++
    $Prefix = Join-Path $OutputDirectory ('{0:d2}-{1}' -f $script:Sequence, $Name)
    $SavedHeaders = @{}
    foreach ($Key in $Headers.Keys) {
        $SavedHeaders[$Key] = $Headers[$Key] -replace [regex]::Escape($Token), '<token>'
    }
    [ordered]@{ method = $Method.ToUpper(); url = $Target; headers = $SavedHeaders; body = $Body } |
        ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 "$Prefix.request.json"

    $Arguments = @{
        Uri                = $Target
        Method             = $Method
        Headers            = $Headers
        SkipHttpErrorCheck = $true
        NoProxy            = $true
    }
    if ($Body) {
        $Arguments.Body = $Body
        $Arguments.ContentType = 'application/json'
    }
    $Response = Invoke-WebRequest @Arguments
    $Text = if ($Response.Content -is [byte[]]) {
        [Text.Encoding]::UTF8.GetString($Response.Content)
    }
    else {
        [string]$Response.Content
    }
    [ordered]@{
        status      = [int]$Response.StatusCode
        contentType = [string]$Response.Headers['Content-Type']
        body        = $Text
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 "$Prefix.response.json"
    return [pscustomobject]@{
        Status = [int]$Response.StatusCode
        Text   = $Text
        Json   = if ($Text) { $Text | ConvertFrom-Json } else { $null }
    }
}

function Get-ToolData {
    param($Exchange)
    return ($Exchange.Json.result.content[0].text | ConvertFrom-Json)
}

$Initialize = Invoke-Exchange -Name 'initialize' -Body (@{
        jsonrpc = '2.0'; id = 1; method = 'initialize'
        params  = @{
            protocolVersion = '2025-06-18'; capabilities = @{}
            clientInfo      = @{ name = 'CheckServer'; version = '1' }
        }
    } | ConvertTo-Json -Depth 5 -Compress)
Assert-That ($Initialize.Status -eq 200) 'initialize returns HTTP 200'
Assert-That ($Initialize.Json.result.protocolVersion -eq '2025-06-18') 'initialize returns the requested protocol version'
Assert-That ($null -ne $Initialize.Json.result.capabilities.tools) 'initialize announces the tools capability'

$Initialized = Invoke-Exchange -Name 'initialized' -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}'
Assert-That ($Initialized.Status -eq 202) 'a notification returns HTTP 202'

$ToolList = Invoke-Exchange -Name 'tools-list' -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
$ToolNames = @($ToolList.Json.result.tools | ForEach-Object { $_.name })
Assert-That ($ToolList.Status -eq 200) 'tools/list returns HTTP 200'
Assert-That ($ToolNames -contains 'list_functions') 'tools/list contains list_functions'
Assert-That ($ToolNames -contains 'decompile_function') 'tools/list contains decompile_function'

$FunctionList = Invoke-Exchange -Name 'list-functions' -Body '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_functions","arguments":{}}}'
$FunctionData = Get-ToolData $FunctionList
Assert-That ($FunctionList.Json.result.isError -eq $false) 'list_functions is not an error'
Assert-That ($FunctionData.dataNotice.Length -gt 0) 'list_functions marks the result as data'
Assert-That ($FunctionData.data.total -gt 0) 'list_functions returns one function or more'
Assert-That (@($FunctionData.data.functions | Where-Object { $_.name -eq $ExpectedFunction }).Count -eq 1) "list_functions contains $ExpectedFunction"

$Filtered = Invoke-Exchange -Name 'list-functions-filter' -Body (@{
        jsonrpc = '2.0'; id = 4; method = 'tools/call'
        params  = @{ name = 'list_functions'; arguments = @{ filter = $FunctionFilter; limit = 1 } }
    } | ConvertTo-Json -Depth 5 -Compress)
$FilteredData = Get-ToolData $Filtered
Assert-That (@($FilteredData.data.functions).Count -eq 1) 'list_functions obeys limit'
Assert-That ($FilteredData.data.total -lt $FunctionData.data.total) 'list_functions obeys filter'

$MisspelledKey = Invoke-Exchange -Name 'review-1015-misspelled-key' -Body '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"list_functions","arguments":{"filter":"main","limti":1}}}'
Assert-That ($MisspelledKey.Json.result.isError -eq $true) 'review 1015: list_functions reports the key limti, which the schema does not have'
Assert-That ($MisspelledKey.Json.result.content[0].text -match 'limti') 'review 1015: the tool error names the key limti'
Assert-That ($MisspelledKey.Json.result.content[0].text -notmatch 'dataNotice') 'review 1015: the tool error contains no data from the binary'

$CorrectKey = Invoke-Exchange -Name 'review-1015-correct-key' -Body '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"list_functions","arguments":{"filter":"main","limit":1}}}'
Assert-That ($CorrectKey.Json.result.isError -eq $false) 'review 1015: list_functions accepts the keys filter and limit'
Assert-That (@((Get-ToolData $CorrectKey).data.functions).Count -eq 1) 'review 1015: list_functions with the limit 1 returns one function'

$DecompileExtraKey = Invoke-Exchange -Name 'review-1015-decompile-extra-key' -Body (@{
        jsonrpc = '2.0'; id = 17; method = 'tools/call'
        params  = @{ name = 'decompile_function'; arguments = @{ function = $ExpectedFunction; limit = 1 } }
    } | ConvertTo-Json -Depth 5 -Compress)
Assert-That ($DecompileExtraKey.Json.result.isError -eq $true) 'review 1015: decompile_function reports a key that the schema does not have'

$Decompile = Invoke-Exchange -Name 'decompile-main' -Body (@{
        jsonrpc = '2.0'; id = 5; method = 'tools/call'
        params  = @{ name = 'decompile_function'; arguments = @{ function = $ExpectedFunction } }
    } | ConvertTo-Json -Depth 5 -Compress)
$DecompileData = Get-ToolData $Decompile
Assert-That ($Decompile.Json.result.isError -eq $false) 'decompile_function is not an error'
Assert-That ($DecompileData.data.name -eq $ExpectedFunction) 'decompile_function returns the function name'
$ShortName = ($ExpectedFunction -split '\.')[-1]
Assert-That ($DecompileData.data.code -match ('\b' + [regex]::Escape($ShortName) + '\(')) 'decompile_function returns code that names the function'
Assert-That ($Decompile.Json.result.content[0].text.StartsWith('{"dataNotice":')) 'decompile_function puts the data notice before the data'
Set-Content -Encoding utf8 (Join-Path $OutputDirectory 'decompile-main.code.txt') $DecompileData.data.code

$ByShortName = Invoke-Exchange -Name 'decompile-by-short-name' -Body (@{
        jsonrpc = '2.0'; id = 14; method = 'tools/call'
        params  = @{ name = 'decompile_function'; arguments = @{ function = $ShortName } }
    } | ConvertTo-Json -Depth 5 -Compress)
Assert-That ((Get-ToolData $ByShortName).data.address -eq $DecompileData.data.address) 'decompile_function accepts the name that the code shows'

$ByAddress = Invoke-Exchange -Name 'decompile-by-address' -Body (@{
        jsonrpc = '2.0'; id = 6; method = 'tools/call'
        params  = @{ name = 'decompile_function'; arguments = @{ function = $DecompileData.data.address } }
    } | ConvertTo-Json -Depth 5 -Compress)
Assert-That ((Get-ToolData $ByAddress).data.code -eq $DecompileData.data.code) 'decompile_function accepts an address'

$Missing = Invoke-Exchange -Name 'decompile-missing' -Body '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"decompile_function","arguments":{"function":"no_such_function; ?e injected"}}}'
Assert-That ($Missing.Json.result.isError -eq $true) 'decompile_function reports a function that does not exist'

$UnknownTool = Invoke-Exchange -Name 'unknown-tool' -Body '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"no_such_tool"}}'
Assert-That ($UnknownTool.Json.error.code -eq -32602) 'an unknown tool returns the error -32602'

$UnknownMethod = Invoke-Exchange -Name 'unknown-method' -Body '{"jsonrpc":"2.0","id":9,"method":"no/such"}'
Assert-That ($UnknownMethod.Json.error.code -eq -32601) 'an unknown method returns the error -32601'

$BadJson = Invoke-Exchange -Name 'bad-json' -Body '{"jsonrpc":'
Assert-That ($BadJson.Status -eq 400 -and $BadJson.Json.error.code -eq -32700) 'a body that is not JSON returns HTTP 400 and the error -32700'

$NoToken = Invoke-Exchange -Name 'no-token' -Headers @{} -Body '{"jsonrpc":"2.0","id":10,"method":"tools/list"}'
Assert-That ($NoToken.Status -eq 401) 'a request without a token returns HTTP 401'
Assert-That ($NoToken.Text -notmatch 'list_functions') 'a request without a token gets no tool list'

$WrongToken = Invoke-Exchange -Name 'wrong-token' -Headers @{ Authorization = 'Bearer ' + ('0' * $Token.Length) } -Body '{"jsonrpc":"2.0","id":11,"method":"tools/list"}'
Assert-That ($WrongToken.Status -eq 401) 'a request with a wrong token returns HTTP 401'

$WithOrigin = Invoke-Exchange -Name 'origin' -Headers @{ Authorization = "Bearer $Token"; Origin = 'http://example.test' } -Body '{"jsonrpc":"2.0","id":12,"method":"tools/list"}'
Assert-That ($WithOrigin.Status -eq 403) 'a request with an Origin header returns HTTP 403'

$GetRequest = Invoke-Exchange -Name 'get' -Method 'Get'
Assert-That ($GetRequest.Status -eq 405) 'a GET request returns HTTP 405'

$WrongPath = Invoke-Exchange -Name 'wrong-path' -Target ($Url -replace '/mcp$', '/other') -Body '{"jsonrpc":"2.0","id":13,"method":"tools/list"}'
Assert-That ($WrongPath.Status -eq 404) 'another path returns HTTP 404'

function Test-TcpConnect {
    param([string]$Address)
    $Client = [Net.Sockets.TcpClient]::new(([Net.IPAddress]$Address).AddressFamily)
    try {
        $Connected = $Client.ConnectAsync($Address, $Port).Wait(3000)
        return ($Connected -and $Client.Connected)
    }
    catch {
        return $false
    }
    finally {
        $Client.Dispose()
    }
}

$Addresses = @(Get-NetIPAddress | Where-Object {
        $_.AddressState -eq 'Preferred' -and $_.IPAddress -ne '127.0.0.1'
    } | ForEach-Object { $_.IPAddress -replace '%.*$', '' })
$ConnectResults = @([ordered]@{ address = '127.0.0.1'; connected = (Test-TcpConnect '127.0.0.1') })
foreach ($Address in $Addresses) {
    $ConnectResults += [ordered]@{ address = $Address; connected = (Test-TcpConnect $Address) }
}
[ordered]@{ port = $Port; results = $ConnectResults } | ConvertTo-Json -Depth 5 |
    Set-Content -Encoding utf8 (Join-Path $OutputDirectory 'tcp-connect.json')
Assert-That ($ConnectResults[0].connected) 'a TCP connection to 127.0.0.1 opens'
Assert-That ($Addresses.Count -gt 0) 'this computer has an address that is not 127.0.0.1'
foreach ($Result in $ConnectResults | Select-Object -Skip 1) {
    Assert-That (-not $Result.connected) "a TCP connection to $($Result.address) does not open"
}

if ($script:Failures.Count -gt 0) {
    Write-Host "== $($script:Failures.Count) check(s) failed"
    exit 1
}
Write-Host '== All checks passed'
exit 0
