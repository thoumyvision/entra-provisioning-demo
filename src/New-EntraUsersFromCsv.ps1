#requires -Version 7.0

<#
.SYNOPSIS
    Provision Microsoft Entra (Azure AD) users from a CSV, config-driven by department.

.DESCRIPTION
    Reads a CSV of new hires and a department-map.psd1 config, then for each valid row:
      - builds a collision-safe username and UPN,
      - creates the user in Entra via Microsoft Graph,
      - adds the user to their department's M365 group (license flows via GROUP-BASED licensing),
      - issues a one-time Temporary Access Pass (no password is ever set),
      - emails the Temporary Access Pass and first-sign-in instructions to the hire's manager
        for in-person handoff.

    All changes are wrapped in ShouldProcess. Run with -WhatIf to see the full plan without
    connecting to any tenant or changing anything (the dry run needs no Graph module installed).

.PARAMETER CsvPath
    Path to the new-hire CSV. Required. Columns: First,Last,Department,JobTitle,Manager.

.PARAMETER MapPath
    Path to the department-map.psd1 config. Defaults to department-map.psd1 beside this script.

.PARAMETER UpnSuffix
    Domain used to build each user's UserPrincipalName (e.g. contoso.com).

.PARAMETER TenantId
    Entra tenant ID. Required for a real (non -WhatIf) run.

.PARAMETER ClientId
    App-registration (client) ID used for app-only auth. Required for a real run.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate for app-only auth. Required for a real run.

.PARAMETER FromAddress
    Sender address for the manager handoff email. Required for a real run.

.PARAMETER SmtpServer
    SMTP server used to send the manager handoff email. Required for a real run.

.EXAMPLE
    .\New-EntraUsersFromCsv.ps1 -CsvPath ..\data\new-hires.csv -WhatIf
    Prints the full provisioning plan for every row. Connects to nothing, changes nothing.

.NOTES
    File Name      : New-EntraUsersFromCsv.ps1
    Author         : Marcus Whitman
    Prerequisite   : PowerShell 7+. Real run also needs Microsoft.Graph modules, an app
                     registration with User.ReadWrite.All, Group.ReadWrite.All,
                     UserAuthenticationMethod.ReadWrite.All, and the Temporary Access Pass
                     authentication-method policy enabled for the target users.
    Last Modified  : 2026-07-07
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to the new-hire CSV")]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string] $CsvPath,

    [Parameter(Mandatory = $false)]
    [string] $MapPath = (Join-Path -Path $PSScriptRoot -ChildPath 'department-map.psd1'),

    [Parameter(Mandatory = $false)]
    [string] $UpnSuffix = 'contoso.com',

    [Parameter(Mandatory = $false)]
    [string] $TenantId,

    [Parameter(Mandatory = $false)]
    [string] $ClientId,

    [Parameter(Mandatory = $false)]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string] $FromAddress,

    [Parameter(Mandatory = $false)]
    [string] $SmtpServer
)

#region Configuration
$ErrorActionPreference = 'Stop'
#endregion

#region Functions
function Write-Log {
    <#
    .SYNOPSIS
        Write a timestamped, color-coded message to the console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string] $Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message

    switch ($Level) {
        'ERROR'   { Write-Host -Object $line -ForegroundColor Red }
        'WARNING' { Write-Host -Object $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host -Object $line -ForegroundColor Green }
        default   { Write-Host -Object $line -ForegroundColor Gray }
    }
}
#endregion

#region Main
# Load the department -> group + license map. Import-PowerShellDataFile safely evaluates
# the .psd1 as data (it cannot run arbitrary code), which is why config lives in a .psd1.
$departmentMap = Import-PowerShellDataFile -Path $MapPath
Write-Log -Message ("Loaded department map with {0} departments." -f $departmentMap.Keys.Count) -Level INFO

# Load every row from the CSV up front so we can report totals.
$allRows = Import-Csv -Path $CsvPath
Write-Log -Message ("Read {0} rows from {1}." -f $allRows.Count, $CsvPath) -Level INFO

# Validate each row before we try to build an identity from it. A row is valid only when
# First, Last, Department, and Manager are all present and the department exists in the map.
$validRows = [System.Collections.Generic.List[object]]::new()
$rowNumber = 0
foreach ($row in $allRows) {
    $rowNumber++

    $missingFields = @('First', 'Last', 'Department', 'Manager') |
        Where-Object -FilterScript { [string]::IsNullOrWhiteSpace($row.$_) }

    if ($missingFields.Count -gt 0) {
        Write-Log -Message ("Row {0}: SKIPPED (missing field(s): {1})." -f $rowNumber, ($missingFields -join ', ')) -Level WARNING
        continue
    }

    if (-not $departmentMap.ContainsKey($row.Department)) {
        Write-Log -Message ("Row {0}: SKIPPED (department '{1}' is not in the map)." -f $rowNumber, $row.Department) -Level WARNING
        continue
    }

    $validRows.Add($row)
}

Write-Log -Message ("{0} of {1} rows are valid and will be processed." -f $validRows.Count, $allRows.Count) -Level INFO
#endregion
