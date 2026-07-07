---
name: pwsh-standards
description: "PowerShell coding standards and patterns for infrastructure automation. Use this skill whenever writing new PowerShell scripts, reviewing PowerShell code quality, or needing patterns for error handling, API calls, logging, parameter validation, or Azure Key Vault integration in PowerShell. Also use when the user asks about PowerShell best practices, naming conventions, or script structure."
---

# PowerShell Coding Standards

PowerShell coding conventions and best practices for infrastructure automation and MSP scripting. Follow these standards for consistency across all scripts in this repository.

## Script Template

Every PowerShell script should follow this structure:

```powershell
#requires -Version 5.1

<#
.SYNOPSIS
    Brief one-line description of what the script does

.DESCRIPTION
    Detailed description of script functionality, use cases, and behavior

.PARAMETER ParameterName
    Description of parameter purpose and expected values

.EXAMPLE
    .\Script-Name.ps1 -ParameterName "Value"
    Description of what this example does

.NOTES
    File Name      : Script-Name.ps1
    Author         : Marcus Whitman
    Prerequisite   : PowerShell 5.1+, Azure CLI (if applicable)
    Last Modified  : YYYY-MM-DD

.LINK
    Related documentation or project links
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Description of required parameter")]
    [ValidateNotNullOrEmpty()]
    [string]$RequiredParam,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Option1", "Option2", "Option3")]
    [string]$OptionalParam = "Option1"
)

#region Configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Speeds up Invoke-RestMethod/Invoke-WebRequest

# Script configuration
$ScriptPath = $PSScriptRoot
$LogFile = Join-Path $ScriptPath "logs\$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
#endregion

#region Functions
function Write-Log {
    <#
    .SYNOPSIS
        Write message to log file and console
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to console with color
    switch ($Level) {
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage -ForegroundColor Gray }
    }

    # Write to log file
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logMessage
    }
}

# Additional functions here...
#endregion

#region Main Script
try {
    Write-Log "Script started" -Level INFO

    # Your main script logic here...

    Write-Log "Script completed successfully" -Level SUCCESS
    exit 0
}
catch {
    Write-Log "Script failed: $_" -Level ERROR
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    # Cleanup code here (if needed)
}
#endregion
```

---

## Naming Conventions

### Script Names
- **Use PascalCase with hyphens:** `Get-UserReport.ps1`, `Set-NinjaOnePolicy.ps1`
- **Verb-Noun format:** Follow PowerShell approved verbs (Get, Set, New, Remove, etc.)
- **Be descriptive:** `Update-ITGlueConfiguration.ps1` not `update.ps1`

### Function Names
```powershell
# Good
function Get-AzureKeyVaultSecret { }
function Invoke-NinjaOneAPI { }
function Test-NetworkConnectivity { }

# Bad
function getSecret { }  # Not PascalCase
function DoStuff { }    # Not descriptive, no approved verb
function api { }        # Too short, no verb
```

### Variable Names
```powershell
# Good - PascalCase for readability
$ClientName = "Contoso"
$ApiEndpoint = "https://api.example.com"
$TotalRecords = 100

# Acceptable - camelCase
$clientName = "Contoso"
$apiEndpoint = "https://api.example.com"

# Bad
$client_name = "Contoso"  # snake_case (not PowerShell convention)
$x = "Contoso"            # Not descriptive
```

### Parameter Names
```powershell
[CmdletBinding()]
param(
    # Good - Clear, descriptive, PascalCase
    [string]$OrganizationName,
    [int]$MaxRetries,
    [switch]$Force,

    # Bad
    [string]$org,           # Too abbreviated
    [int]$x,                # Not descriptive
    [switch]$f              # Single letter
)
```

---

## Written for a Human Reviewer

Scripts are read more than they are run, and a reviewer who cannot follow a script will not trust it. Optimize generated PowerShell for a human reading it top to bottom:

- **No aliases.** Use `Where-Object` not `?`, `ForEach-Object` not `%`, `Get-ChildItem` not `gci`/`ls`/`dir`, `Select-Object` not `select`. Aliases are for the interactive prompt, never for saved scripts.
- **Full parameter names, no positional arguments.** Write `Get-MgUser -UserId $upn`, not `Get-MgUser $upn`. The reader should never have to remember positional order.
- **Splat multi-parameter calls** into a hashtable rather than using backtick line-continuation; splatting reads cleanly and avoids trailing-backtick breakage.
- **A guiding comment before each logical block** stating what the block accomplishes and why. This complements (does not contradict) "explain why not what": comment at the *block* level to narrate intent, while still avoiding line-noise like `$i = 0  # set i to zero`.

---

## Parameter Validation

### Required Parameters
```powershell
param(
    [Parameter(Mandatory = $true, HelpMessage = "Organization name to query")]
    [ValidateNotNullOrEmpty()]
    [string]$OrganizationName
)
```

### Optional Parameters with Defaults
```powershell
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false)]
    [ValidateSet("US", "EU", "AU")]
    [string]$Region = "US"
)
```

### Validation Attributes
```powershell
param(
    # Validate not null/empty
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    # Validate specific values
    [ValidateSet("Development", "Staging", "Production")]
    [string]$Environment,

    # Validate range
    [ValidateRange(1, 100)]
    [int]$Count,

    # Validate pattern (regex)
    [ValidatePattern('^\d{3}-\d{3}-\d{4}$')]
    [string]$PhoneNumber,

    # Validate script block
    [ValidateScript({ Test-Path $_ })]
    [string]$FilePath,

    # Validate length
    [ValidateLength(1, 50)]
    [string]$Description
)
```

---

## Error Handling

### Try-Catch-Finally Pattern
```powershell
try {
    $ErrorActionPreference = "Stop"  # Converts non-terminating errors to terminating

    # Code that might fail
    $result = Invoke-RestMethod -Uri $apiUrl -Headers $headers

    # Validate result
    if (-not $result) {
        throw "API returned empty result"
    }
}
catch [System.Net.WebException] {
    # Handle specific exception type
    Write-Error "Network error: $($_.Exception.Message)"
    # Optional: retry logic here
}
catch {
    # Handle all other exceptions
    Write-Error "Unexpected error: $_"
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    throw  # Re-throw if you want calling code to handle it
}
finally {
    # Cleanup code (always runs)
    if ($connection) {
        $connection.Close()
    }
}
```

### Common Exception Types
```powershell
# Catch specific exceptions for better error handling
catch [System.Net.WebException] { }              # Network/HTTP errors
catch [System.IO.FileNotFoundException] { }      # File not found
catch [System.UnauthorizedAccessException] { }   # Permission denied
catch [System.ArgumentException] { }             # Invalid argument
catch [Microsoft.PowerShell.Commands.HttpResponseException] { }  # REST API errors
```

### Retry Logic Pattern
```powershell
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5
    )

    $attempt = 0
    $success = $false

    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        try {
            Write-Log "Attempt $attempt of $MaxRetries" -Level INFO
            $result = & $ScriptBlock
            $success = $true
            return $result
        }
        catch {
            Write-Log "Attempt $attempt failed: $_" -Level WARNING

            if ($attempt -ge $MaxRetries) {
                Write-Log "Max retries reached. Failing." -Level ERROR
                throw
            }

            Write-Log "Retrying in $DelaySeconds seconds..." -Level INFO
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# Usage
$result = Invoke-WithRetry -ScriptBlock {
    Invoke-RestMethod -Uri $apiUrl -Headers $headers
} -MaxRetries 3 -DelaySeconds 5
```

---

## Microsoft Graph Authentication

- **App-only, certificate-based auth for automation** (no user, no secret in a person's name):
  `Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $Thumbprint -NoWelcome`
- **Least-privilege application permissions** granted to the app registration, documented in the script's help. Assign only what the script uses (e.g. `User.ReadWrite.All`, `Group.ReadWrite.All`).
- **Import only the specific sub-modules** used (`Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, ...), never the whole `Microsoft.Graph` meta-module - it is large and slow to load.
- **Gate the connection** behind the real-run path so a `-WhatIf` dry run needs no module and no tenant.

---

## Extended Patterns

Read [references/patterns.md](references/patterns.md) for additional patterns:
- REST API calls with error handling (`Invoke-APIRequest`)
- Pagination pattern (`Get-PaginatedResults`)
- Logging function (`Write-Log` with file + console output)
- Progress reporting for long-running operations
- Azure Key Vault integration (`Get-KeyVaultSecret`)
- Complete function example (`Get-NinjaOneDevices`)
- Common patterns quick reference (path checks, JSON I/O, timing)
- CLI tools for script navigation (rg, fd, bat, fzf)

---

## Bash Heredoc Gotchas

When generating PowerShell scripts via bash heredoc (`pwsh -File -` or writing to a `.ps1` file):

- **`Write-Host` output gets swallowed** in `foreach` loops piped through `pwsh -File -` heredoc. Write results to a file with `Out-File` and read it back instead of relying on console output.
- **`$PSScriptRoot` fallback `$PWD.Path` resolves unreliably** in `pwsh -File -` heredoc. Use `$env:TEMP` or hardcoded paths for output files rather than relying on `$PSScriptRoot` in dynamically generated scripts.
- **Never use `pwsh -Command` for multi-line scripts** - bash mangles `\$` escaping; pwsh sees bare `\` as a command and fails. Write to a `.ps1` file and use `pwsh -File` instead.

---

## Additional Resources

- PowerShell Best Practices: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines
- Approved Verbs: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
- PoshCode Style Guide: https://github.com/PoshCode/PowerShellPracticeAndStyle
