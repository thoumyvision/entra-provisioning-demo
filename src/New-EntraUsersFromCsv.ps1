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

function Resolve-UniqueUsername {
    <#
    .SYNOPSIS
        Build a first-initial + last-name username that does not collide, and return it with its UPN.
    .DESCRIPTION
        Ensures uniqueness within this run using the AssignedUsernames set. On a real run,
        pass -CheckTenant to also confirm the UPN is free in Entra via Get-MgUser.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FirstName,

        [Parameter(Mandatory = $true)]
        [string] $LastName,

        [Parameter(Mandatory = $true)]
        [string] $UpnSuffix,

        # AllowEmptyCollection: the set is legitimately empty on the first hire; a mandatory collection parameter otherwise rejects an empty collection at bind time.
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $AssignedUsernames,

        [Parameter(Mandatory = $false)]
        [switch] $CheckTenant
    )

    # Base handle: first initial + last name, lowercased, with any non-alphanumeric stripped.
    $baseHandle = ('{0}{1}' -f $FirstName.Substring(0, 1), $LastName).ToLower()
    $baseHandle = $baseHandle -replace '[^a-z0-9]', ''

    $candidate = $baseHandle
    $suffixNumber = 1

    # Walk jdoe -> jdoe2 -> jdoe3 ... until the handle is free both in this run and (optionally) the tenant.
    while ($true) {
        $candidateUpn = '{0}@{1}' -f $candidate, $UpnSuffix
        $collides = $AssignedUsernames.Contains($candidate)

        if (-not $collides -and $CheckTenant) {
            $existingUser = Get-MgUser -Filter "userPrincipalName eq '$candidateUpn'" -ErrorAction SilentlyContinue
            if ($existingUser) {
                $collides = $true
            }
        }

        if (-not $collides) {
            [void] $AssignedUsernames.Add($candidate)
            return [pscustomobject]@{
                Username = $candidate
                Upn      = $candidateUpn
            }
        }

        $suffixNumber++
        $candidate = '{0}{1}' -f $baseHandle, $suffixNumber
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

# Build a concrete provisioning plan for every valid row. This resolves the username,
# UPN, group, and license now so the plan can be printed (and reviewed) before anything changes.
$assignedUsernames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$isRealRun = -not $WhatIfPreference

$plans = [System.Collections.Generic.List[object]]::new()
foreach ($row in $validRows) {
    $identity = Resolve-UniqueUsername -FirstName $row.First -LastName $row.Last -UpnSuffix $UpnSuffix `
        -AssignedUsernames $assignedUsernames -CheckTenant:$isRealRun

    $mapping = $departmentMap[$row.Department]

    $plans.Add([pscustomobject]@{
        First      = $row.First
        Last       = $row.Last
        Department = $row.Department
        JobTitle   = $row.JobTitle
        Manager    = $row.Manager
        Username   = $identity.Username
        Upn        = $identity.Upn
        Group      = $mapping.Group
        License    = $mapping.License
    })
}
#endregion
