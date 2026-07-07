# Entra User-Provisioning Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the employer 2nd-interview screenshare demo: a legacy on-prem `NewUsers.ps1` beside a modern, config-driven Microsoft Graph provisioning script, plus the crafted prompt and pwsh-standards skill that produced it.

**Architecture:** One PowerShell script (`New-EntraUsersFromCsv.ps1`) reads a CSV of new hires and a `department-map.psd1` config, builds collision-safe identities, and — in a real run — creates Entra users via Graph, adds them to their department's M365 group (license flows via group-based licensing), issues a one-time Temporary Access Pass, and emails it to each hire's manager with first-sign-in instructions. All mutations are wrapped in `ShouldProcess`; the demo runs in offline `-WhatIf`, which needs no tenant, no Graph module, and prints the intended plan.

**Tech Stack:** PowerShell 7 (`pwsh`), Microsoft.Graph sub-modules (real run only: `Microsoft.Graph.Authentication`, `.Users`, `.Groups`, `.Identity.SignIns`), PSScriptAnalyzer (lint/verification), `Import-PowerShellDataFile` for `.psd1` config.

## Global Constraints

- **Verification is `-WhatIf` + PSScriptAnalyzer, not Pester.** Spec section 9: no unit-test framework. Each task is verified by running the offline `-WhatIf` path and by `Invoke-ScriptAnalyzer` showing no alias/warning findings.
- **Written for a human reviewer** (spec 3.5): no aliases (full `Where-Object`, `ForEach-Object`, `Get-ChildItem`, `Select-Object`), full parameter names, no positional args, splatting over backtick continuation, a guiding comment before each logical block.
- **Offline `-WhatIf` must run on any machine:** module import and `Connect-MgGraph` are gated behind `if (-not $WhatIfPreference)`. Graph cmdlets live only inside `ShouldProcess` blocks, so they are never invoked during a dry run.
- **No secret is ever logged:** the TAP value goes only into the manager email; never to console or log file.
- **ASCII only** in scripts (no em-dashes/smart quotes) — PS 5.1 UTF-8-no-BOM parsing safety.
- **License is group-based** (spec 3.4): assign the user to the department group; do not call `Set-MgUserLicense` in the default path (show it commented as the explicit alternative).
- **Real SKU part numbers**, fake group names (spec 4.2).
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87
  ```

---

## File Structure

- `legacy/NewUsers.ps1` — verbatim copy of the 2019 original (the "before"). Created in Task 1.
- `src/department-map.psd1` — department -> group + license SKU config. Created in Task 1.
- `data/new-hires.csv` — fake test data with `First,Last,Department,JobTitle,Manager`. Created in Task 1.
- `src/New-EntraUsersFromCsv.ps1` — the professional script. Built across Tasks 2-5.
- `standards/pwsh-standards.SKILL.md` — copy of the updated skill (shown artifact). Created in Task 6.
- `~/.claude/skills/pwsh-standards/SKILL.md` + `references/patterns.md` — the five skill additions. Modified in Task 6.
- `prompt/prompt.md` — the crafted prompt. Created in Task 7.
- `README.md` — the run-sheet. Rewritten in Task 8.

---

## Task 1: Inputs — legacy copy, department map, fake CSV

**Files:**
- Create: `legacy/NewUsers.ps1`
- Create: `src/department-map.psd1`
- Create: `data/new-hires.csv`

**Interfaces:**
- Produces: `department-map.psd1` returns a hashtable keyed by department name; each value is a hashtable `@{ Group = <string>; License = <string> }`. Consumed by Task 3 (`Import-PowerShellDataFile`).
- Produces: `new-hires.csv` columns `First,Last,Department,JobTitle,Manager`. Consumed by Task 2.

- [ ] **Step 1: Copy the legacy original verbatim**

Copy `C:\Users\thoum\OneDrive\Documents\Git Repositories\scripts.old\NewUsers.ps1` to `legacy/NewUsers.ps1` unchanged. This is the "before" artifact; do not clean it up — its flaws are the teaching material.

- [ ] **Step 2: Write `src/department-map.psd1`**

```powershell
# Department -> M365 group + license SKU map.
# Group names are illustrative; SKU part numbers are the real Microsoft values.
# The user is added to the group; the license flows via GROUP-BASED LICENSING
# (the license is assigned to the group once, in tenant config, not per user).
@{
    'Attorney'      = @{ Group = 'Attorneys-Users';     License = 'SPE_E5' }  # Microsoft 365 E5
    'Paralegal'     = @{ Group = 'Legal-Support-Users'; License = 'SPE_E3' }  # Microsoft 365 E3
    'Legal Support' = @{ Group = 'Legal-Support-Users'; License = 'SPE_E3' }
    'IT'            = @{ Group = 'IT-Staff';            License = 'SPE_E5' }
    'Finance'       = @{ Group = 'Finance-Users';       License = 'SPE_E3' }
    'Marketing'     = @{ Group = 'Marketing-Users';     License = 'SPE_E3' }
    'HR'            = @{ Group = 'HR-Users';            License = 'SPE_E3' }
}
```

- [ ] **Step 3: Write `data/new-hires.csv`** (includes a deliberate collision and one invalid row)

```csv
First,Last,Department,JobTitle,Manager
Jordan,Doe,Attorney,Associate Attorney,alan.pierce@contoso.com
Jamie,Doe,Paralegal,Senior Paralegal,alan.pierce@contoso.com
Priya,Kumar,IT,Systems Engineer,dana.wells@contoso.com
Marcus,Lee,Finance,Staff Accountant,rosa.nunez@contoso.com
Chen,Wu,Marketing,Marketing Specialist,rosa.nunez@contoso.com
Aisha,Bello,HR,HR Generalist,dana.wells@contoso.com
Tom,Riley,Legal Support,Records Clerk,alan.pierce@contoso.com
,Nguyen,Attorney,Associate Attorney,alan.pierce@contoso.com
Sam,Park,Robotics,Automation Lead,dana.wells@contoso.com
```

Notes for the implementer (these are intentional, do not "fix"):
- Rows 1 and 2 (`Jordan Doe`, `Jamie Doe`) both resolve to base username `jdoe` — the collision case.
- Row 8 has a blank `First` — the invalid-row case (must be skipped with a reason, not crash).
- Row 9 department `Robotics` is not in the map — the unmapped-department case (skipped with a reason).

- [ ] **Step 4: Verify the config and CSV load**

Run:
```bash
pwsh -NoProfile -Command "(Import-PowerShellDataFile ./src/department-map.psd1).Keys -join ', '; '---'; (Import-Csv ./data/new-hires.csv).Count"
```
Expected: the 7 department keys printed, then `---`, then `9` (row count).

- [ ] **Step 5: Commit**

```bash
git add legacy/NewUsers.ps1 src/department-map.psd1 data/new-hires.csv
git commit -m "feat: add legacy original, department map, and fake new-hire CSV

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87"
```

---

## Task 2: Script skeleton — params, help, config/CSV load, row validation

**Files:**
- Create: `src/New-EntraUsersFromCsv.ps1`

**Interfaces:**
- Consumes: `department-map.psd1` (Task 1), `new-hires.csv` (Task 1).
- Produces: `Write-Log` function `Write-Log -Message <string> -Level <INFO|WARNING|ERROR|SUCCESS>`. Produces validated-row objects with properties `First,Last,Department,JobTitle,Manager` for Task 3. Produces script parameters `-CsvPath`, `-MapPath`, `-UpnSuffix`, `-TenantId`, `-ClientId`, `-CertificateThumbprint`, `-FromAddress`, `-SmtpServer`.

- [ ] **Step 1: Write the script skeleton with comment-based help, params, `Write-Log`, and validation loop**

Create `src/New-EntraUsersFromCsv.ps1` with exactly this content (full cmdlet and parameter names throughout, block comments narrating intent):

```powershell
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

# $PSScriptRoot is empty when the script is run via 'pwsh -File' from some shells; fall back.
if (-not $PSScriptRoot) {
    $ScriptRoot = $PWD.Path
}
else {
    $ScriptRoot = $PSScriptRoot
}
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
```

- [ ] **Step 2: Run the offline dry run and verify validation output**

Run:
```bash
pwsh -NoProfile -File ./src/New-EntraUsersFromCsv.ps1 -CsvPath ./data/new-hires.csv -WhatIf
```
Expected (order/timestamps may vary):
- `Loaded department map with 7 departments.`
- `Read 9 rows from ...`
- `Row 8: SKIPPED (missing field(s): First).`
- `Row 9: SKIPPED (department 'Robotics' is not in the map).`
- `7 of 9 rows are valid and will be processed.`

- [ ] **Step 3: Lint with PSScriptAnalyzer (readability gate)**

Run:
```bash
pwsh -NoProfile -Command "if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module PSScriptAnalyzer -Scope CurrentUser -Force }; Invoke-ScriptAnalyzer -Path ./src/New-EntraUsersFromCsv.ps1 -Settings PSGallery | Format-Table -AutoSize"
```
Expected: no `PSAvoidUsingCmdletAliases` findings and no Warning/Error severities. (Info-level findings are acceptable; alias findings are not — they violate the readability constraint.)

- [ ] **Step 4: Commit**

```bash
git add src/New-EntraUsersFromCsv.ps1
git commit -m "feat: script skeleton with help, params, config load, row validation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87"
```

---

## Task 3: Identity construction and collision handling

**Files:**
- Modify: `src/New-EntraUsersFromCsv.ps1`

**Interfaces:**
- Consumes: validated rows and `$departmentMap` from Task 2, `-UpnSuffix`.
- Produces: `New-UniqueUsername` returning `[pscustomobject]@{ Username = <string>; Upn = <string> }`. Produces, per valid row, a `$plan` object with properties `First,Last,Department,JobTitle,Manager,Username,Upn,Group,License` consumed by Task 4.

- [ ] **Step 1: Add the `New-UniqueUsername` function** inside `#region Functions` (after `Write-Log`)

```powershell
function New-UniqueUsername {
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

        [Parameter(Mandatory = $true)]
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
```

- [ ] **Step 2: Build the per-row plan** — append to `#region Main`, after the validation loop

```powershell
# Build a concrete provisioning plan for every valid row. This resolves the username,
# UPN, group, and license now so the plan can be printed (and reviewed) before anything changes.
$assignedUsernames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$isRealRun = -not $WhatIfPreference

$plans = [System.Collections.Generic.List[object]]::new()
foreach ($row in $validRows) {
    $identity = New-UniqueUsername -FirstName $row.First -LastName $row.Last -UpnSuffix $UpnSuffix `
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
```

- [ ] **Step 3: Run the dry run and verify collision resolution**

Run:
```bash
pwsh -NoProfile -File ./src/New-EntraUsersFromCsv.ps1 -CsvPath ./data/new-hires.csv -WhatIf -Verbose
```
Then confirm by printing the plan objects (temporary check — add `$plans | Format-Table Username,Upn,Department,Group,License` at the end, run, verify, then remove it before commit):
Expected: `Jordan Doe` -> `jdoe`, `Jamie Doe` -> `jdoe2`; `Priya Kumar` -> `pkumar` (Group `IT-Staff`, License `SPE_E5`); 7 plan rows total.

- [ ] **Step 4: Lint**

Run:
```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src/New-EntraUsersFromCsv.ps1 -Settings PSGallery | Format-Table -AutoSize"
```
Expected: no alias or Warning/Error findings.

- [ ] **Step 5: Commit**

```bash
git add src/New-EntraUsersFromCsv.ps1
git commit -m "feat: collision-safe username construction and per-row plan

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87"
```

---

## Task 4: Provisioning actions — plan output, ShouldProcess, Graph calls, manager email

**Files:**
- Modify: `src/New-EntraUsersFromCsv.ps1`

**Interfaces:**
- Consumes: `$plans` (Task 3), all connection params (Task 2), `Write-Log` (Task 2).
- Produces: `Get-FirstSignInEmailBody` returning the manager email body `[string]`. Produces the final results summary printed to console.

- [ ] **Step 1: Add `Get-FirstSignInEmailBody`** inside `#region Functions`

```powershell
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
```

- [ ] **Step 2: Connect (real run only) and process each plan** — append to `#region Main`, after the plan is built

```powershell
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
    Write-Log -Message ("PLAN {0}: create {1} | group {2} | license {3} (group-based) | TAP -> email {4}" -f `
            $displayName, $plan.Upn, $plan.Group, $plan.License, $plan.Manager) -Level INFO

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
        $newUser = New-MgUser -DisplayName $displayName -GivenName $plan.First -Surname $plan.Last `
            -UserPrincipalName $plan.Upn -MailNickname $plan.Username -Department $plan.Department `
            -JobTitle $plan.JobTitle -AccountEnabled -PasswordProfile $passwordProfile

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
        $emailBody = Get-FirstSignInEmailBody -HireDisplayName $displayName -HireUpn $plan.Upn `
            -TemporaryAccessPass $tap.TemporaryAccessPass -LifetimeInMinutes $tapLifetimeMinutes
        Send-MailMessage -To $plan.Manager -From $FromAddress -SmtpServer $SmtpServer `
            -Subject "First-day sign-in details for $displayName" -Body $emailBody

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
```

- [ ] **Step 3: Run the full offline dry run and verify the complete plan prints**

Run:
```bash
pwsh -NoProfile -File ./src/New-EntraUsersFromCsv.ps1 -CsvPath ./data/new-hires.csv -WhatIf
```
Expected:
- 7 `PLAN <name>: create ... | group ... | license ... | TAP -> email ...` lines.
- A `What if:` line per valid hire (from ShouldProcess), e.g. `What if: Performing the operation "Create Entra user, add to 'Attorneys-Users', ..." on target "jdoe@contoso.com".`
- `jdoe@contoso.com` and `jdoe2@contoso.com` both present (collision resolved).
- The two skip warnings (row 8, row 9) still print.
- A final summary table with 7 rows, all `Planned (WhatIf)`.
- No `Connect-MgGraph` call, no error about missing Microsoft.Graph module.

- [ ] **Step 4: Lint**

Run:
```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src/New-EntraUsersFromCsv.ps1 -Settings PSGallery | Where-Object { $_.Severity -in 'Warning','Error' } | Format-Table -AutoSize"
```
Expected: no rows (empty). Note: PSScriptAnalyzer flags `Send-MailMessage` as deprecated (`PSAvoidUsingCmdletAliases` will not, but `PSAvoidUsingDeprecatedManifestFields`/`PSUseCompatibleCmdlets` might not either); if a `Send-MailMessage` obsolescence Info/Warning appears, add a one-line comment above it noting it stands in for the org's approved mail path in this demo, and confirm it is not an Error.

- [ ] **Step 5: Commit**

```bash
git add src/New-EntraUsersFromCsv.ps1
git commit -m "feat: provisioning actions with ShouldProcess, TAP, and manager email

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87"
```

---

## Task 5: Live-segment readiness — confirm the additive change is trivial

**Files:**
- Modify: none (this task validates the demo's live moment works, then reverts)

**Interfaces:**
- Consumes: the finished `src/New-EntraUsersFromCsv.ps1`.

- [ ] **Step 1: Dry-run the planned live change to prove it is safe**

The live demo change (spec 7) is "also set each user's OfficeLocation from a new CSV column." Verify it is a clean, contained edit by doing it on a scratch copy: add an `Office` column to a copy of the CSV, add `-OfficeLocation $plan.Office` to the `New-MgUser` splat and an `Office` property to the plan object, run `-WhatIf`, confirm it still prints cleanly, then **discard the scratch changes** (do not commit — this is what Marcus does live).

Run (scratch validation):
```bash
cp ./data/new-hires.csv /tmp/live-test.csv
# (manually add an Office column + value to /tmp/live-test.csv, mirror the two edits on a temp copy of the script, run -WhatIf)
```
Expected: it runs and prints without error, confirming the live change is a 2-line, low-risk edit. Then `git checkout -- .` any script scratch edits.

- [ ] **Step 2: No commit** — this task produces no repo change by design. Record in the README (Task 8) that the live change is pre-validated.

---

## Task 6: Update the pwsh-standards skill and vendor a copy into the repo

**Files:**
- Modify: `C:\Users\thoum\.claude\skills\pwsh-standards\SKILL.md`
- Modify: `C:\Users\thoum\.claude\skills\pwsh-standards\references\patterns.md`
- Create: `standards/pwsh-standards.SKILL.md` (copy of the updated SKILL.md)

**Interfaces:**
- Produces: the five new standard sections referenced by `prompt/prompt.md` (Task 7).

- [ ] **Step 1: Add a "Written for a Human Reviewer" section to `SKILL.md`**

Insert after the "Naming Conventions" section:

```markdown
## Written for a Human Reviewer

Scripts are read more than they are run, and a reviewer who cannot follow a script will not trust it. Optimize generated PowerShell for a human reading it top to bottom:

- **No aliases.** Use `Where-Object` not `?`, `ForEach-Object` not `%`, `Get-ChildItem` not `gci`/`ls`/`dir`, `Select-Object` not `select`. Aliases are for the interactive prompt, never for saved scripts.
- **Full parameter names, no positional arguments.** Write `Get-MgUser -UserId $upn`, not `Get-MgUser $upn`. The reader should never have to remember positional order.
- **Splat multi-parameter calls** into a hashtable rather than using backtick line-continuation; splatting reads cleanly and avoids trailing-backtick breakage.
- **A guiding comment before each logical block** stating what the block accomplishes and why. This complements (does not contradict) "explain why not what": comment at the *block* level to narrate intent, while still avoiding line-noise like `$i = 0  # set i to zero`.
```

- [ ] **Step 2: Add a "Microsoft Graph Authentication" section to `SKILL.md`** (after "Error Handling")

```markdown
## Microsoft Graph Authentication

- **App-only, certificate-based auth for automation** (no user, no secret in a person's name):
  `Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $Thumbprint -NoWelcome`
- **Least-privilege application permissions** granted to the app registration, documented in the script's help. Assign only what the script uses (e.g. `User.ReadWrite.All`, `Group.ReadWrite.All`).
- **Import only the specific sub-modules** used (`Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, ...), never the whole `Microsoft.Graph` meta-module - it is large and slow to load.
- **Gate the connection** behind the real-run path so a `-WhatIf` dry run needs no module and no tenant.
```

- [ ] **Step 3: Add "ShouldProcess", "Config-Driven Design", and "Idempotency" subsections to `references/patterns.md`** (before "Quick Reference")

```markdown
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
```

- [ ] **Step 4: Verify the skill files are valid Markdown and copy into the repo**

Run:
```bash
cp "C:/Users/thoum/.claude/skills/pwsh-standards/SKILL.md" ./standards/pwsh-standards.SKILL.md
pwsh -NoProfile -Command "Get-Content ./standards/pwsh-standards.SKILL.md | Select-String -Pattern 'Written for a Human Reviewer','Microsoft Graph Authentication' | ForEach-Object { $_.Line }"
```
Expected: both section headings print, confirming the vendored copy includes the new sections.

- [ ] **Step 5: Commit (repo copy only; the skill repo is committed via its own sync)**

```bash
git add standards/pwsh-standards.SKILL.md
git commit -m "docs: vendor updated pwsh-standards skill into the demo repo

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87"
```

Note for the implementer: the `~/.claude/skills/pwsh-standards/` edits live in the `claude-config` repo (`thoumyvision/claude-config`), not this Demo repo. Commit them there separately, or leave them staged for Marcus's next `/claude-sync`.

---

## Task 7: Write the crafted prompt

**Files:**
- Create: `prompt/prompt.md`

- [ ] **Step 1: Write `prompt/prompt.md`**

```markdown
# Prompt: modernize the new-user provisioning script

Follow my **pwsh-standards** skill for everything below.

I have a script from 2019, `legacy/NewUsers.ps1`, that reads a CSV and creates Active
Directory accounts on-prem. I want a modern replacement that provisions cloud identities in
Microsoft Entra instead. Build `src/New-EntraUsersFromCsv.ps1` to these requirements:

- **Microsoft Graph, not AD.** Use `New-MgUser` and the Graph module, not `New-ADUser`.
- **App-only certificate auth.** Connect with `Connect-MgGraph` using a tenant ID, client ID,
  and certificate thumbprint. Never a password or a user account.
- **Config-driven by department.** Read a `department-map.psd1` that maps each department to an
  M365 group and a license SKU. One script + one config replaces the six per-client copies I
  used to hand-edit.
- **Group-based licensing.** Add the user to their department's group and let the license flow
  from the group. Show the explicit per-user `Set-MgUserLicense` call as a commented
  alternative, but do not use it.
- **No password.** Issue a one-time Temporary Access Pass and email it, with first-sign-in
  instructions, to the hire's manager (a Manager column in the CSV) for in-person handoff.
  Never write the pass to a log.
- **Collision-safe and idempotent.** First-initial + last name; if `jdoe` is taken, use `jdoe2`.
  Check the tenant on a real run; dedupe within the batch on a dry run.
- **Safe by default.** `SupportsShouldProcess`; a full `-WhatIf` that connects to nothing,
  changes nothing, and prints the plan. It must run on a machine with no Graph module installed.
- **Written for a human reviewer.** Full cmdlet and parameter names, no aliases, splatting,
  a guiding comment before each block. Someone should be able to read it without running it.

Handle bad input without crashing the batch: skip rows missing required fields or with an
unmapped department, report why, and keep going.
```

- [ ] **Step 2: Commit**

```bash
git add prompt/prompt.md
git commit -m "docs: add the crafted prompt that produced the script

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87"
```

---

## Task 8: Write the README run-sheet

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite `README.md`**

```markdown
# Demo: from a 2019 AD script to modern Entra provisioning

A before/after that shows how directing an AI with codified standards produces automation that
is faster to build and cleaner than what I wrote by hand years ago.

## The chain of evidence

1. `legacy/NewUsers.ps1` - a real script I wrote in 2019. It works, but: a hardcoded plaintext
   password, no collision handling, no error handling, one bad row kills the run, and I kept six
   hand-edited copies (one per client).
2. `prompt/prompt.md` - the prompt I gave the AI. The judgment is front-loaded here.
3. `standards/pwsh-standards.SKILL.md` - my codified PowerShell standards. The quality is mine,
   made repeatable.
4. `src/New-EntraUsersFromCsv.ps1` - the result.

## What the new script does differently

| 2019 `NewUsers.ps1` | `New-EntraUsersFromCsv.ps1` |
| --- | --- |
| `New-ADUser` (on-prem) | `New-MgUser` (Microsoft Graph) |
| Hardcoded `"Summer2019!"` | No password; one-time Temporary Access Pass |
| No collision handling | `jdoe` -> `jdoe2` automatically |
| One bad row kills the loop | Per-row error handling; batch continues |
| Hardcoded path/domain/OU | Parameters + `department-map.psd1` config |
| Six hand-edited copies | One script + one config |
| No department logic | Department -> M365 group; license via group-based licensing |
| Ran blind against prod | Full `-WhatIf` dry run |

## Run the demo (offline, no tenant needed)

```powershell
pwsh -File src/New-EntraUsersFromCsv.ps1 -CsvPath data/new-hires.csv -WhatIf
```

This prints the full plan and changes nothing. Watch for: the `jdoe` / `jdoe2` collision
resolving, the blank row and the unmapped `Robotics` row being skipped with reasons, and the
per-hire `PLAN ...` line ending in `TAP -> email <manager>`.

## Talking points

- **Cert-based app-only auth** - no password, no automation tied to a person.
- **Group-based licensing** - assign the user to a group, the license follows; deprovisioning is
  removing them from the group. `Set-MgUserLicense` is shown as the commented alternative.
- **Temporary Access Pass** - the hire never gets a password. They get a single-use, 60-minute
  pass, emailed to their manager for in-person handoff, with first-sign-in steps. Bootstrapping a
  first credential is inherently out-of-band; if there is no manager, the fallback is a handoff
  report to the operator.
- **Written for a human reviewer** - full command and parameter names, comments throughout,
  because I know someone is going to read it, not just run it.
- **One config replaces six copies** - the department map is the whole difference between one
  maintainable tool and six drifting scripts.

## Live segment

The `OfficeLocation`-from-a-new-column change is pre-validated as a clean, ~2-line edit - safe to
do live under direction, with this finished script as the fallback.

---
*Built with Claude (Opus 4.8)*
```

- [ ] **Step 2: Final full dry run as the acceptance check**

Run:
```bash
pwsh -NoProfile -File ./src/New-EntraUsersFromCsv.ps1 -CsvPath ./data/new-hires.csv -WhatIf
```
Expected: matches the "Run the demo" description — 7 PLAN lines, collision resolved, 2 skips, final summary table, no tenant connection.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README run-sheet with old-vs-new table and talking points

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87"
```

- [ ] **Step 4: Push**

```bash
git push
```

---

## Self-Review (completed during authoring)

**Spec coverage:** legacy copy (T1), department map + legal flavoring (T1), fake CSV with collision/invalid/unmapped rows (T1), Graph script skeleton + validation (T2), collision handling + idempotency (T3), ShouldProcess + group-based licensing + TAP + manager email + first-sign-in instructions + offline -WhatIf (T4), live segment readiness (T5), five skill additions + vendored copy (T6), crafted prompt (T7), README run-sheet (T8). All spec sections 1-9 map to a task.

**Placeholder scan:** no TBD/TODO; all code is complete. The only intentional "do it live, do not commit" is Task 5, which is explicit by design.

**Type consistency:** `Write-Log -Message/-Level`, `New-UniqueUsername` -> `{ Username; Upn }`, `$plan` properties `First,Last,Department,JobTitle,Manager,Username,Upn,Group,License`, and `Get-FirstSignInEmailBody -HireDisplayName/-HireUpn/-TemporaryAccessPass/-LifetimeInMinutes` are used consistently across Tasks 2-4.
