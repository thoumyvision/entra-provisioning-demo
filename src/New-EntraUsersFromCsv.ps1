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

function Get-FirstSignInEmailBody {
    <#
    .SYNOPSIS
        Build the manager handoff email body containing the Temporary Access Pass and first-sign-in steps.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $HireDisplayName,

        [Parameter(Mandatory = $true)]
        [string] $HireUpn,

        [Parameter(Mandatory = $true)]
        [string] $TemporaryAccessPass,

        [Parameter(Mandatory = $true)]
        [int] $LifetimeInMinutes
    )

    # Plain-text body. The manager hands this to the new hire in person on day one.
    return @"
A new account is ready for $HireDisplayName.

Please give the new hire their one-time sign-in pass in person. It expires in
$LifetimeInMinutes minutes and works only once.

  Work sign-in address : $HireUpn
  Temporary Access Pass: $TemporaryAccessPass

First sign-in steps (for the new hire):
  1. Go to https://www.office.com and choose Sign in.
  2. Enter your work sign-in address above.
  3. When asked for a password, choose "Use a Temporary Access Pass" and enter the code above.
  4. Follow the prompts to set up the Microsoft Authenticator app - this becomes your
     permanent sign-in method.
  5. The pass works once and expires in $LifetimeInMinutes minutes, so finish setup in one
     sitting. If it expires, contact IT for a new one.
"@
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
    $identityParams = @{
        FirstName         = $row.First
        LastName          = $row.Last
        UpnSuffix         = $UpnSuffix
        AssignedUsernames = $assignedUsernames
        CheckTenant       = $isRealRun
    }
    $identity = Resolve-UniqueUsername @identityParams

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

# Connect to Microsoft Graph only for a real run. The dry run skips this entirely, so it needs
# no Graph module installed and no tenant. Import only the specific sub-modules we use
# (least privilege / least footprint), not the whole Microsoft.Graph meta-module.
if ($isRealRun -and $plans.Count -gt 0) {
    Import-Module -Name Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
    Write-Log -Message "Connected to Microsoft Graph (app-only, certificate)." -Level SUCCESS
}

$tapLifetimeMinutes = 60
$results = [System.Collections.Generic.List[object]]::new()

foreach ($plan in $plans) {
    $displayName = '{0} {1}' -f $plan.First, $plan.Last

    # Print the human-readable planned action for this hire. This prints on both dry and real runs
    # so the operator always sees exactly what will happen / happened, in one line.
    $planMessage = "PLAN {0}: create {1} | group {2} | license {3} (group-based) | TAP -> email {4}" -f $displayName, $plan.Upn, $plan.Group, $plan.License, $plan.Manager
    Write-Log -Message $planMessage -Level INFO

    # ShouldProcess gates every real change. Under -WhatIf it returns $false and PowerShell prints
    # the standard "What if:" line, so nothing below runs and no Graph cmdlet is ever invoked.
    $action = "Create Entra user, add to '$($plan.Group)', issue Temporary Access Pass, email manager"
    if (-not $PSCmdlet.ShouldProcess($plan.Upn, $action)) {
        $results.Add([pscustomobject]@{ Upn = $plan.Upn; Status = 'Planned (WhatIf)' })
        continue
    }

    try {
        # 1) Create the user. mailNickname is the username; forceChangePasswordNextSignIn is moot
        #    because we set no usable password - the Temporary Access Pass is the only way in.
        $passwordProfile = @{
            forceChangePasswordNextSignIn = $true
            password                      = ([System.Guid]::NewGuid().ToString('N') + '!Aa9')  # random, never used, never logged
        }
        $newUserParams = @{
            DisplayName       = $displayName
            GivenName         = $plan.First
            Surname           = $plan.Last
            UserPrincipalName = $plan.Upn
            MailNickname      = $plan.Username
            Department        = $plan.Department
            JobTitle          = $plan.JobTitle
            AccountEnabled    = $true
            PasswordProfile   = $passwordProfile
        }
        $newUser = New-MgUser @newUserParams

        # 2) Add to the department group. License flows from GROUP-BASED LICENSING (assigned to the
        #    group in tenant config), so we do NOT assign a license per user here.
        #    Explicit per-user alternative, shown but intentionally not used:
        #        Set-MgUserLicense -UserId $newUser.Id -AddLicenses @(@{ SkuId = <sku-guid> }) -RemoveLicenses @()
        $group = Get-MgGroup -Filter "displayName eq '$($plan.Group)'" -ErrorAction Stop
        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $newUser.Id

        # 3) Issue a one-time Temporary Access Pass. Its value is returned exactly once, right here.
        $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $newUser.Id -BodyParameter @{
            isUsableOnce      = $true
            lifetimeInMinutes = $tapLifetimeMinutes
        }

        # 4) Email the pass and first-sign-in steps to the manager for in-person handoff.
        #    The TAP value goes ONLY into this email - never to the log or console.
        #    Send-MailMessage is deprecated/obsolete in PS7; it stands in here for the org's
        #    approved mail-relay path in this demo (a real deployment would call that instead).
        $emailBodyParams = @{
            HireDisplayName     = $displayName
            HireUpn             = $plan.Upn
            TemporaryAccessPass = $tap.TemporaryAccessPass
            LifetimeInMinutes   = $tapLifetimeMinutes
        }
        $emailBody = Get-FirstSignInEmailBody @emailBodyParams
        $mailParams = @{
            To         = $plan.Manager
            From       = $FromAddress
            SmtpServer = $SmtpServer
            Subject    = "First-day sign-in details for $displayName"
            Body       = $emailBody
        }
        Send-MailMessage @mailParams

        Write-Log -Message ("Provisioned {0} and emailed sign-in details to {1}." -f $plan.Upn, $plan.Manager) -Level SUCCESS
        $results.Add([pscustomobject]@{ Upn = $plan.Upn; Status = 'Created' })
    }
    catch {
        # One bad hire must not stop the batch. Record the failure and keep going.
        Write-Log -Message ("Failed to provision {0}: {1}" -f $plan.Upn, $_.Exception.Message) -Level ERROR
        $results.Add([pscustomobject]@{ Upn = $plan.Upn; Status = ('Failed: ' + $_.Exception.Message) })
    }
}

# Final summary so the operator sees the outcome of the whole batch at a glance.
Write-Log -Message "Run complete. Summary:" -Level INFO
$results | Format-Table -AutoSize
#endregion
