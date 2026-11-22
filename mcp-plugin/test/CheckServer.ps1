param(
    [Parameter(Mandatory)][string]$ConnectionFile,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$FunctionFilter = 'main',
    [string]$ExpectedFunction = 'sym.main',
    [string]$CalledFunction = 'sym.read_item',
    [string]$StringFilter = 'INVENTORY FILE',
    [string]$ImportFilter = 'FOPEN'
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
    if ($Exchange.Json.result.isError -ne $false) {
        return $null
    }
    return ($Exchange.Json.result.content[0].text | ConvertFrom-Json)
}

function Invoke-Tool {
    param([string]$Name, [string]$Tool, [hashtable]$Arguments = @{})
    $script:ToolCallId++
    return Invoke-Exchange -Name $Name -Body (@{
            jsonrpc = '2.0'; id = $script:ToolCallId; method = 'tools/call'
            params  = @{ name = $Tool; arguments = $Arguments }
        } | ConvertTo-Json -Depth 5 -Compress)
}

function Test-AddressOrder {
    param([object[]]$Entries)
    $Previous = [uint64]0
    foreach ($Entry in $Entries) {
        $Current = [Convert]::ToUInt64($Entry.address.Substring(2), 16)
        if ($Current -lt $Previous) {
            return $false
        }
        $Previous = $Current
    }
    return $true
}

$script:ToolCallId = 100

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
foreach ($ToolName in 'disassemble_function', 'find_references', 'list_strings', 'list_imports', 'get_current_location') {
    Assert-That ($ToolNames -contains $ToolName) "tools/list contains $ToolName"
}
Assert-That (@($ToolList.Json.result.tools | Where-Object { $_.annotations.readOnlyHint -ne $true }).Count -eq 0) 'tools/list marks each tool as read-only'

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

$Disassembly = Invoke-Tool -Name 'disassemble-main' -Tool 'disassemble_function' -Arguments @{ function = $ExpectedFunction }
$DisassemblyData = (Get-ToolData $Disassembly).data
$Instructions = @($DisassemblyData.instructions)
Assert-That ($Disassembly.Json.result.isError -eq $false) 'disassemble_function is not an error'
Assert-That ($DisassemblyData.address -eq $DecompileData.data.address) 'disassemble_function returns the address of the function'
Assert-That ($Instructions.Count -gt 0 -and $Instructions[0].address -eq $DisassemblyData.address) 'disassemble_function starts at the address of the function'
Assert-That (@($Instructions | Where-Object { $_.bytes -notmatch '^([0-9a-f]{2})+$' -or -not $_.text }).Count -eq 0) 'disassemble_function returns the bytes and the text of each instruction'
Assert-That (Test-AddressOrder $Instructions) 'disassemble_function returns the instructions in the order of the addresses'

$DisassemblyMissing = Invoke-Tool -Name 'disassemble-missing' -Tool 'disassemble_function' -Arguments @{ function = 'no_such_function; ?e injected' }
Assert-That ($DisassemblyMissing.Json.result.isError -eq $true) 'disassemble_function reports a function that does not exist'

$CalledList = Invoke-Tool -Name 'list-functions-called' -Tool 'list_functions' -Arguments @{ filter = $CalledFunction }
$CalledAddress = @((Get-ToolData $CalledList).data.functions | Where-Object { $_.name -eq $CalledFunction })[0].address
Assert-That ($CalledAddress -match '^0x[0-9a-f]+$') "list_functions returns the address of $CalledFunction"

$ReferencesTo = Invoke-Tool -Name 'references-to' -Tool 'find_references' -Arguments @{ address = $CalledAddress }
$ReferencesToData = (Get-ToolData $ReferencesTo).data
$Calls = @($ReferencesToData.references | Where-Object { $_.type -eq 'CALL' })
Assert-That ($ReferencesTo.Json.result.isError -eq $false) 'find_references is not an error'
Assert-That ($ReferencesToData.direction -eq 'to') 'find_references uses the direction "to" when the request gives no direction'
Assert-That ($Calls.Count -gt 0) "find_references returns a call of $CalledFunction"
Assert-That (@($ReferencesToData.references | Where-Object { $_.to -ne $CalledAddress }).Count -eq 0) 'find_references returns only references to the address'
Assert-That (@($Instructions | Where-Object { $_.address -eq $Calls[0].from }).Count -eq 1) "find_references returns a call that is an instruction of $ExpectedFunction"

$ReferencesFrom = Invoke-Tool -Name 'references-from' -Tool 'find_references' -Arguments @{ address = $Calls[0].from; direction = 'from' }
$ReferencesFromData = (Get-ToolData $ReferencesFrom).data
Assert-That (@($ReferencesFromData.references | Where-Object { $_.to -eq $CalledAddress }).Count -eq 1) 'find_references with the direction "from" returns the reference to the called function'

$ReferencesBadAddress = Invoke-Tool -Name 'references-bad-address' -Tool 'find_references' -Arguments @{ address = '0x1000; ?e injected' }
Assert-That ($ReferencesBadAddress.Json.result.isError -eq $true) 'find_references reports an address that is not a number'
$ReferencesBadDirection = Invoke-Tool -Name 'references-bad-direction' -Tool 'find_references' -Arguments @{ address = $CalledAddress; direction = 'both' }
Assert-That ($ReferencesBadDirection.Json.result.isError -eq $true) 'find_references reports a direction that is not known'

$StringList = Invoke-Tool -Name 'list-strings' -Tool 'list_strings'
$StringData = (Get-ToolData $StringList).data
Assert-That ($StringList.Json.result.isError -eq $false) 'list_strings is not an error'
Assert-That ($StringData.total -gt 0 -and @($StringData.strings).Count -gt 0) 'list_strings returns one string or more'
Assert-That (Test-AddressOrder @($StringData.strings)) 'list_strings returns the strings in the order of the addresses'

$StringFiltered = Invoke-Tool -Name 'list-strings-filter' -Tool 'list_strings' -Arguments @{ filter = $StringFilter; limit = 1 }
$StringFilteredData = (Get-ToolData $StringFiltered).data
Assert-That (@($StringFilteredData.strings).Count -eq 1) 'list_strings obeys limit'
Assert-That ($StringFilteredData.total -gt 0 -and $StringFilteredData.total -lt $StringData.total) 'list_strings obeys filter'
Assert-That ($StringFilteredData.strings[0].string.ToLower().Contains($StringFilter.ToLower())) 'list_strings returns a string that contains the filter text'

$StringSecond = Invoke-Tool -Name 'list-strings-offset' -Tool 'list_strings' -Arguments @{ offset = 1; limit = 1 }
Assert-That ((Get-ToolData $StringSecond).data.strings[0].address -eq $StringData.strings[1].address) 'list_strings obeys offset'

$ImportList = Invoke-Tool -Name 'list-imports' -Tool 'list_imports'
$ImportData = (Get-ToolData $ImportList).data
Assert-That ($ImportList.Json.result.isError -eq $false) 'list_imports is not an error'
Assert-That ($ImportData.total -gt 0 -and @($ImportData.imports).Count -gt 0) 'list_imports returns one import or more'
Assert-That (@($ImportData.imports | Where-Object { -not $_.name -or -not $_.library }).Count -eq 0) 'list_imports returns the name and the library of each import'

$ImportFiltered = Invoke-Tool -Name 'list-imports-filter' -Tool 'list_imports' -Arguments @{ filter = $ImportFilter }
$ImportFilteredData = (Get-ToolData $ImportFiltered).data
Assert-That ($ImportFilteredData.total -gt 0 -and $ImportFilteredData.total -lt $ImportData.total) 'list_imports obeys filter'
Assert-That ($ImportFilteredData.imports[0].name.ToLower().Contains($ImportFilter.ToLower())) 'list_imports returns an import whose name contains the filter text'

$ImportBadLimit = Invoke-Tool -Name 'list-imports-bad-limit' -Tool 'list_imports' -Arguments @{ limit = 0 }
Assert-That ($ImportBadLimit.Json.result.isError -eq $true) 'list_imports reports a limit that is out of range'

$Location = Invoke-Tool -Name 'current-location' -Tool 'get_current_location'
$LocationData = (Get-ToolData $Location).data
Assert-That ($Location.Json.result.isError -eq $false) 'get_current_location is not an error'
Assert-That ($LocationData.address -match '^0x[0-9a-f]+$') 'get_current_location returns an address'
Assert-That ($null -eq $LocationData.function -or $LocationData.function.address -match '^0x[0-9a-f]+$') 'get_current_location returns a function or null'

$LocationExtraKey = Invoke-Tool -Name 'current-location-extra-key' -Tool 'get_current_location' -Arguments @{ address = '0x0' }
Assert-That ($LocationExtraKey.Json.result.isError -eq $true) 'get_current_location reports a key, because its schema has no keys'

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
