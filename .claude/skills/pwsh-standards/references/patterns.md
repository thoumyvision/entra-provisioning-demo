# PowerShell Patterns Reference

Extended patterns and examples for PowerShell scripts. Referenced from the main pwsh-standards skill.

## API Patterns

### REST API Calls with Error Handling
```powershell
function Invoke-APIRequest {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [string]$Method = "GET",

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{},

        [Parameter(Mandatory = $false)]
        [object]$Body = $null
    )

    try {
        $params = @{
            Uri     = $Uri
            Method  = $Method
            Headers = $Headers
        }

        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            $params.ContentType = "application/json"
        }

        $response = Invoke-RestMethod @params
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorMessage = $_.Exception.Message

        Write-Error "API request failed [$statusCode]: $errorMessage"

        if ($_.ErrorDetails.Message) {
            Write-Error "Details: $($_.ErrorDetails.Message)"
        }

        throw
    }
}
```

### Pagination Pattern
```powershell
function Get-PaginatedResults {
    param(
        [Parameter(Mandatory)]
        [string]$BaseUri,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [int]$PageSize = 100
    )

    $allResults = @()
    $page = 1
    $hasMore = $true

    while ($hasMore) {
        $uri = "$BaseUri&page=$page&page_size=$PageSize"
        Write-Log "Fetching page $page..." -Level INFO

        $response = Invoke-APIRequest -Uri $uri -Headers $Headers

        $allResults += $response.data

        if ($response.data.Count -lt $PageSize) {
            $hasMore = $false
        }
        else {
            $page++
        }
    }

    Write-Log "Retrieved $($allResults.Count) total records" -Level SUCCESS
    return $allResults
}
```

---

## Logging and Output

### Logging Function
```powershell
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO",

        [string]$LogFile = $script:LogFile
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Console output with colors
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "DEBUG"   { "Cyan" }
        default   { "Gray" }
    }

    Write-Host $logMessage -ForegroundColor $color

    # File output
    if ($LogFile) {
        try {
            $logDir = Split-Path -Path $LogFile -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            Add-Content -Path $LogFile -Value $logMessage -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }
}
```

### Progress Reporting
```powershell
# For long-running operations
$items = @(1..100)
$total = $items.Count
$current = 0

foreach ($item in $items) {
    $current++
    $percentComplete = [math]::Round(($current / $total) * 100, 2)

    Write-Progress -Activity "Processing Items" `
                   -Status "Item $current of $total ($percentComplete%)" `
                   -PercentComplete $percentComplete

    # Process item...
    Start-Sleep -Milliseconds 100
}

Write-Progress -Activity "Processing Items" -Completed
```

---

## Azure Key Vault Integration

### Retrieve Secrets Safely
```powershell
function Get-KeyVaultSecret {
    param(
        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter(Mandatory)]
        [string]$SecretName
    )

    try {
        $secret = az keyvault secret show `
            --vault-name $VaultName `
            --name $SecretName `
            --query value `
            -o tsv 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to retrieve secret '$SecretName' from vault '$VaultName'"
        }

        if ([string]::IsNullOrWhiteSpace($secret)) {
            throw "Secret '$SecretName' is empty or does not exist"
        }

        return $secret
    }
    catch {
        Write-Error "Key Vault Error: $_"
        throw
    }
}

# Usage
$apiKey = Get-KeyVaultSecret -VaultName "fabrikam-scripts-secrets" -SecretName "api-key"
```

---

## Best Practices

### Script Organization
- ✅ **#region blocks** for logical sections (Configuration, Functions, Main Script)
- ✅ **Functions before main code** - define all functions in #region Functions
- ✅ **Single responsibility** - one script does one thing well
- ✅ **Reusable functions** - extract common patterns into functions

### Performance
- ✅ **Use -Filter instead of | Where-Object** when possible (especially with AD/Exchange)
- ✅ **Set $ProgressPreference = "SilentlyContinue"** for faster web requests
- ✅ **Avoid Write-Host in production** - use Write-Output or Write-Verbose
- ✅ **Pipeline when appropriate** - `Get-Process | Where-Object {$_.CPU -gt 100}`

### Security
- ✅ **Never hardcode credentials** - use Azure Key Vault
- ✅ **Use SecureString for passwords** when needed
- ✅ **Clear sensitive variables** after use: `$password = $null; [GC]::Collect()`
- ✅ **Validate all external input** - use parameter validation attributes
- ⛔ **Never log secrets** - avoid Write-Host/Write-Log with sensitive data

### Error Messages
- ✅ **Be specific** - "Failed to connect to API at https://api.example.com" not "Error occurred"
- ✅ **Include context** - Parameter values, state, what was attempted
- ✅ **Provide next steps** - "Check network connectivity" or "Verify API key"
- ✅ **Log stack traces** for debugging: `$_.ScriptStackTrace`

### Comments
- ✅ **Explain "why" not "what"** - code shows what, comments explain why
- ✅ **Comment-based help** for all functions and scripts
- ✅ **TODO comments** for future work: `# TODO: Add retry logic`
- ⛔ **Avoid obvious comments** - `$x = 1  # Set x to 1` adds no value

---

## Code Examples

### Complete Function Example
```powershell
function Get-NinjaOneDevices {
    <#
    .SYNOPSIS
        Retrieve devices from NinjaOne API

    .DESCRIPTION
        Fetches all devices from NinjaOne RMM platform with pagination support.
        Automatically retrieves access token from Azure Key Vault.

    .PARAMETER OrganizationId
        Optional. Filter devices by organization ID.

    .PARAMETER MaxResults
        Maximum number of results to return. Default: unlimited.

    .EXAMPLE
        Get-NinjaOneDevices -OrganizationId 123

    .EXAMPLE
        Get-NinjaOneDevices -MaxResults 100
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$OrganizationId,

        [Parameter(Mandatory = $false)]
        [int]$MaxResults = 0
    )

    try {
        # Get credentials from Key Vault
        $clientId = Get-KeyVaultSecret -VaultName "fabrikam-scripts-secrets" -SecretName "ninjaone-client-id"
        $clientSecret = Get-KeyVaultSecret -VaultName "fabrikam-scripts-secrets" -SecretName "ninjaone-client-secret"

        # Get access token
        $tokenParams = @{
            Uri = "https://app.ninjarmm.com/ws/oauth/token"
            Method = "POST"
            ContentType = "application/x-www-form-urlencoded"
            Body = @{
                grant_type = "client_credentials"
                client_id = $clientId
                client_secret = $clientSecret
                scope = "monitoring"
            }
        }

        $tokenResponse = Invoke-RestMethod @tokenParams
        $accessToken = $tokenResponse.access_token

        # Build API request
        $headers = @{
            Authorization = "Bearer $accessToken"
        }

        $uri = "https://app.ninjarmm.com/v2/devices"
        if ($OrganizationId) {
            $uri += "?organizationId=$OrganizationId"
        }

        # Fetch devices
        $devices = Invoke-APIRequest -Uri $uri -Headers $headers

        # Apply max results if specified
        if ($MaxResults -gt 0 -and $devices.Count -gt $MaxResults) {
            $devices = $devices[0..($MaxResults - 1)]
        }

        Write-Log "Retrieved $($devices.Count) devices" -Level SUCCESS
        return $devices
    }
    catch {
        Write-Log "Failed to retrieve devices: $_" -Level ERROR
        throw
    }
    finally {
        # Clear sensitive data
        $clientSecret = $null
        $accessToken = $null
        [GC]::Collect()
    }
}
```

---

## ShouldProcess (safe -WhatIf / -Confirm)

Declaring `SupportsShouldProcess` is not enough - you must gate each mutation:

```powershell
[CmdletBinding(SupportsShouldProcess = $true)]
param()

if ($PSCmdlet.ShouldProcess($targetName, 'Delete user')) {
    Remove-MgUser -UserId $targetName
}
```

Under `-WhatIf`, `ShouldProcess` returns `$false` and PowerShell prints a "What if:" line, so the guarded code never runs. This is how you ship a script that can be dry-run against production safely.

## Config-Driven Design

Externalize environment-specific data (mappings, endpoints, per-client values) into a `.psd1`
or JSON file instead of hardcoding it. Load a `.psd1` with `Import-PowerShellDataFile` (it
evaluates data only, never arbitrary code). One config-driven script replaces many
copy-pasted variants:

```powershell
$map = Import-PowerShellDataFile -Path $MapPath
$mapping = $map[$row.Department]   # e.g. @{ Group = 'IT-Staff'; License = 'SPE_E5' }
```

## Idempotency and Existence Checks

Check before you create, so a rerun is safe and collisions are handled:

```powershell
$existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
if ($existing) {
    # derive an alternative (jdoe -> jdoe2) or skip with a reason
}
```

---

## Quick Reference

### Common Patterns
```powershell
# Check if command exists
if (Get-Command "az" -ErrorAction SilentlyContinue) { }

# Test path exists
if (Test-Path $filePath) { }

# Join paths safely
$fullPath = Join-Path $basePath $fileName

# Create directory if not exists
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# Read JSON config
$config = Get-Content "config.json" | ConvertFrom-Json

# Write JSON output
$data | ConvertTo-Json -Depth 10 | Set-Content "output.json"

# Measure execution time
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
# ... code ...
$stopwatch.Stop()
Write-Log "Execution time: $($stopwatch.Elapsed.TotalSeconds)s" -Level INFO
```

---

## Invoking PowerShell from Bash

**Never use `pwsh -Command` for multi-line scripts.** Bash mangles `\$` variable escaping — the backslash is passed through to pwsh as a literal character, which pwsh treats as a command name, causing immediate failure.

```bash
# WRONG — bash eats the escaping, pwsh sees \ as a command
pwsh -Command "\$apiKey = az keyvault secret show ..."

# RIGHT — write to a file, run with -File
pwsh -File MyProject/scripts/do_thing.ps1
```

**Pattern:** When you need to run multi-line PowerShell from a Bash tool call, always write the script to the project's `scripts/` folder first, then invoke it with `pwsh -File`. One-liners with no variables are the only safe use of `pwsh -Command`.

**`$PSScriptRoot` caveat:** `$PSScriptRoot` is empty when a script is invoked via `pwsh -File` from Bash (as opposed to being dot-sourced or called from within PowerShell). Always add this fallback near the top of any script that uses `$PSScriptRoot`:

```powershell
if (-not $PSScriptRoot) { $PSScriptRoot = $PWD.Path }
```

**`$variable:suffix` gotcha in double-quoted strings:** PowerShell's parser treats `:` after a bare `$varname` as a scope qualifier (e.g., `$env:PATH`, `$script:LogFile`). If your string contains something like `"Line $_: text"`, the parser sees `$_:` as an incomplete scoped variable reference and throws:

```
ParserError: Variable reference is not valid. ':' was not followed by a valid variable name character.
```

Fix: use an intermediate variable or wrap in a subexpression:

```powershell
# WRONG — $_ followed by : triggers scope-qualifier parse error
Write-Host "Line $_: len=$($line.Length)"

# RIGHT — intermediate variable
$lineNum = $_
Write-Host "Line $lineNum len=$($line.Length)"

# RIGHT — subexpression forces evaluation first
Write-Host "Line $($_): len=$($line.Length)"
```

---

## CLI Tools for Script Navigation

Use these to search and explore PowerShell scripts from the terminal without loading everything into an editor:

```bash
# Search for a pattern across all PowerShell scripts in the repo
rg "Invoke-RestMethod" --type ps1

# Find all scripts that reference a specific Key Vault secret
rg "itglue-api-key" --type ps1 --type py

# Find scripts by partial name
fd -e ps1 "network"
fd -e ps1 -p NinjaOne_Network_Inventory/scripts/

# View a script with syntax highlighting and line numbers
bat NinjaOne_Network_Inventory/scripts/ninja_network_report.ps1

# View a specific line range of a script
bat -r 50:120 NinjaOne_Network_Inventory/scripts/itglue_network_writer.ps1

# Find all SESSION_CONTEXT.md files across all projects
fd SESSION_CONTEXT.md

# Interactive script picker (fd + fzf)
fd -e ps1 | fzf
```
