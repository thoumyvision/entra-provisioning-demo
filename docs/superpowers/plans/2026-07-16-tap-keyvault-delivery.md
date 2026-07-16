# TAP Key Vault Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manager-email Temporary Access Pass (TAP) handoff in `src/New-EntraUsersFromCsv.ps1` with a per-hire, time-bound Azure Key Vault secret the manager retrieves on demand, per the approved design at `docs/superpowers/specs/2026-07-16-tap-keyvault-delivery-design.md`.

**Architecture:** The script gains a second, cert-based auth context (Az, alongside the existing Graph connection) and a new function, `Set-TapVaultSecret`, that writes the TAP into a `TAP-<username>` secret whose `NotBefore`/`Expires` window mirrors the TAP's own start-date activation window exactly. The manager-email function is renamed and rewritten to carry only a pointer to that secret (vault name, secret name, retrieval command) — never the TAP value.

**Tech Stack:** PowerShell 7 (`pwsh`), `Microsoft.Graph.*` sub-modules (unchanged), `Az.Accounts` + `Az.KeyVault` (new, real-run only), PSScriptAnalyzer.

## Global Constraints

- **Verification is `-WhatIf` + PSScriptAnalyzer, not Pester.** Same as the original build — this is a demo artifact.
- **Secret window mirrors the TAP window exactly:** `NotBefore` = `$plan.StartDate` (the same `datetime` already used for the TAP's `startDateTime`), `Expires` = `$plan.StartDate.AddMinutes($tapLifetimeMinutes)`. Confirmed against `NotBefore`/`Expires` accepting `[Nullable<DateTime>]` on `Set-AzKeyVaultSecret` (Microsoft Learn, `az.keyvault/set-azkeyvaultsecret`).
- **The secret value is never logged, printed, or emailed.** `Set-TapVaultSecret` returns only `VaultName`/`SecretName`. This extends the existing "never log the TAP" invariant.
- **`ConvertTo-SecureString -AsPlainText -Force` is required and must carry a suppression attribute.** `Set-AzKeyVaultSecret -SecretValue` only accepts `[SecureString]` (confirmed via Microsoft Learn, including Microsoft's own example using this exact conversion). This trips PSScriptAnalyzer's `PSAvoidUsingConvertToSecureStringWithPlainText` rule, so `Set-TapVaultSecret` needs a `[Diagnostics.CodeAnalysis.SuppressMessageAttribute(...)]` with a justification, not a workaround. The "0 findings" lint gate stays true because of the suppression, not despite a real violation.
- **`Az.Accounts`/`Az.KeyVault` import and `Connect-AzAccount` are gated inside the same `$isRealRun`-guarded block as the existing Graph import/connect**, so `-WhatIf` still needs no modules installed and no tenant.
- **No CSV or `department-map.psd1` schema changes.**
- **No script-managed Key Vault RBAC** — vault/secret access is a documented tenant prerequisite, not something this script grants.
- **ASCII only**, no em-dashes, in script and Markdown changes.
- **No firm or interviewer named** in `docs/process-narrative.md` — attribute generically ("follow-up interview feedback"), consistent with the existing de-identification (commit `0181625`).
- Commit trailer on every commit:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Ri1cHqQytuiZnrU3b8jFay
  ```

---

## File Structure

- `src/New-EntraUsersFromCsv.ps1` — all script changes, across Tasks 1-2.
- `prompt/prompt.md` — amended credential-delivery requirement. Task 3.
- `docs/process-narrative.md` — new decision section. Task 3.
- `README.md` — prerequisites, expected `-WhatIf` output, talking point. Task 3.
- `SESSION_CONTEXT.md` — new decision-log entry. Task 3.

---

## Task 1: Second auth context, `-KeyVaultName` parameter, updated help

**Files:**
- Modify: `src/New-EntraUsersFromCsv.ps1`

**Interfaces:**
- Produces: script parameter `-KeyVaultName [string]`, consumed by Task 2.
- Consumes: existing `$TenantId`, `$ClientId`, `$CertificateThumbprint`, `$isRealRun` (already defined).

- [ ] **Step 1: Update the `.DESCRIPTION` block**

In the comment-based help at the top of `src/New-EntraUsersFromCsv.ps1`, replace:

```powershell
.DESCRIPTION
    Reads a CSV of new hires and a department-map.psd1 config, then for each valid row:
      - builds a collision-safe username and UPN,
      - creates the user in Entra via Microsoft Graph,
      - adds the user to their department's M365 group (license flows via GROUP-BASED licensing),
      - issues a one-time Temporary Access Pass (no password is ever set),
      - emails the Temporary Access Pass and first-sign-in instructions to the hire's manager
        for in-person handoff.
```

with:

```powershell
.DESCRIPTION
    Reads a CSV of new hires and a department-map.psd1 config, then for each valid row:
      - builds a collision-safe username and UPN,
      - creates the user in Entra via Microsoft Graph,
      - adds the user to their department's M365 group (license flows via GROUP-BASED licensing),
      - issues a one-time Temporary Access Pass (no password is ever set),
      - writes the Temporary Access Pass to a per-hire Azure Key Vault secret and emails the
        manager a pointer to it and first-sign-in instructions - never the pass itself.
```

- [ ] **Step 2: Add `.PARAMETER KeyVaultName`**

Replace:

```powershell
.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate for app-only auth. Required for a real run.

.PARAMETER FromAddress
```

with:

```powershell
.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate for app-only auth. Required for a real run.

.PARAMETER KeyVaultName
    Name of the Azure Key Vault that receives each hire's Temporary Access Pass secret.
    Required for a real run.

.PARAMETER FromAddress
```

- [ ] **Step 3: Update `.NOTES`**

Replace:

```powershell
.NOTES
    File Name      : New-EntraUsersFromCsv.ps1
    Author         : Marcus Whitman
    Prerequisite   : PowerShell 7+. Real run also needs Microsoft.Graph modules, an app
                     registration with User.ReadWrite.All, Group.ReadWrite.All,
                     UserAuthenticationMethod.ReadWrite.All, and the Temporary Access Pass
                     authentication-method policy enabled for the target users.
    TAP Activation : The Temporary Access Pass activates on the hire's StartDate for about
                     8 hours (not at script-run time), since accounts are often created days
                     before onboarding. The lifetime must fall within the tenant's TAP
                     authentication-method policy max lifetime.
    Last Modified  : 2026-07-07
#>
```

with:

```powershell
.NOTES
    File Name      : New-EntraUsersFromCsv.ps1
    Author         : Marcus Whitman
    Prerequisite   : PowerShell 7+. Real run also needs Microsoft.Graph modules, Az.Accounts,
                     and Az.KeyVault; an app registration with User.ReadWrite.All,
                     Group.ReadWrite.All, UserAuthenticationMethod.ReadWrite.All, and Key Vault
                     Secrets Officer at the target vault; the Temporary Access Pass
                     authentication-method policy enabled for the target users; and a
                     Managers/Onboarding security group holding Key Vault Secrets User at the
                     vault so managers can retrieve secrets (this script does not grant that
                     role - it is tenant config, provisioned the same way as the TAP policy and
                     the department groups).
    TAP Activation : The Temporary Access Pass activates on the hire's StartDate for about
                     8 hours (not at script-run time), since accounts are often created days
                     before onboarding. The lifetime must fall within the tenant's TAP
                     authentication-method policy max lifetime.
    KV Window      : The Key Vault secret's readable window (NotBefore/Expires) mirrors the
                     TAP's own activation window exactly, so it cannot be retrieved before the
                     TAP itself would even work.
    Last Modified  : 2026-07-16
#>
```

- [ ] **Step 4: Add the `$KeyVaultName` parameter**

Replace:

```powershell
    [Parameter(Mandatory = $false)]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string] $FromAddress,
```

with:

```powershell
    [Parameter(Mandatory = $false)]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string] $KeyVaultName,

    [Parameter(Mandatory = $false)]
    [string] $FromAddress,
```

- [ ] **Step 5: Add the gated Az connection**

Replace:

```powershell
if ($isRealRun -and $plans.Count -gt 0) {
    Import-Module -Name Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
    Write-Log -Message "Connected to Microsoft Graph (app-only, certificate)." -Level SUCCESS
}
```

with:

```powershell
if ($isRealRun -and $plans.Count -gt 0) {
    Import-Module -Name Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
    Write-Log -Message "Connected to Microsoft Graph (app-only, certificate)." -Level SUCCESS

    # Key Vault is a separate data plane from Graph, so it needs its own connection - the same
    # app registration and certificate, no new credential type introduced.
    Import-Module -Name Az.Accounts, Az.KeyVault
    $azConnectParams = @{
        ServicePrincipal      = $true
        Tenant                = $TenantId
        ApplicationId         = $ClientId
        CertificateThumbprint = $CertificateThumbprint
    }
    Connect-AzAccount @azConnectParams | Out-Null
    Write-Log -Message "Connected to Azure Key Vault (app-only, certificate)." -Level SUCCESS
}
```

- [ ] **Step 6: Run the offline dry run and confirm behavior is unchanged**

Run:
```bash
pwsh -NoProfile -File ./src/New-EntraUsersFromCsv.ps1 -CsvPath ./data/new-hires.csv -WhatIf
```
Expected: identical to the pre-Task-1 baseline — 7 `PLAN ...` lines still ending `TAP valid <date> -> email <manager>` (this task does not touch the PLAN line; that's Task 2), the `jdoe`/`jdoe2` collision resolved, 2 rows skipped with reasons, a 7-row `Planned (WhatIf)` summary, no `Connect-MgGraph` or `Connect-AzAccount` call, no error about missing Graph or Az modules.

- [ ] **Step 7: Lint**

Run:
```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src/New-EntraUsersFromCsv.ps1 -Settings PSGallery | Where-Object { $_.Severity -in 'Warning','Error' } | Format-Table -AutoSize"
```
Expected: no rows (empty).

- [ ] **Step 8: Commit**

```bash
git add src/New-EntraUsersFromCsv.ps1
git commit -m "feat: add Key Vault auth context and KeyVaultName parameter

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ri1cHqQytuiZnrU3b8jFay"
```

---

## Task 2: `Set-TapVaultSecret`, manager-notification rewrite, and wiring

**Files:**
- Modify: `src/New-EntraUsersFromCsv.ps1`

**Interfaces:**
- Consumes: `$KeyVaultName` (Task 1), `$plan.StartDate`/`$plan.Username` (existing), `$tap.TemporaryAccessPass`/`$tapLifetimeMinutes` (existing).
- Produces: `Set-TapVaultSecret -VaultName <string> -SecretName <string> -TemporaryAccessPass <string> -NotBefore <datetime> -ExpiresOn <datetime>` returning `[pscustomobject]@{ VaultName; SecretName }`. Produces `Get-ManagerNotificationEmailBody -HireDisplayName <string> -HireUpn <string> -VaultName <string> -SecretName <string> -LifetimeInMinutes <int> -ValidFromDate <datetime>` returning `[string]`, replacing `Get-FirstSignInEmailBody`.

- [ ] **Step 1: Add `Set-TapVaultSecret`**

Inside `#region Functions`, immediately after the `Get-FirstSignInEmailBody` function (which Step 2 below renames and rewrites in place), add:

```powershell
function Set-TapVaultSecret {
    <#
    .SYNOPSIS
        Write a hire's Temporary Access Pass into a Key Vault secret whose readable window
        mirrors the pass's own activation window.
    .DESCRIPTION
        NotBefore and Expires are set to the same instant and lifetime as the Temporary Access
        Pass itself, so the secret cannot be retrieved before the pass would even work. Returns
        only the vault and secret name for logging - never the secret value.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The Temporary Access Pass is generated by Microsoft Graph at runtime, not a hardcoded secret. Set-AzKeyVaultSecret requires SecureString for -SecretValue, so this is the required conversion boundary. The plaintext value is never logged, printed, or returned.')]
    param(
        [Parameter(Mandatory = $true)]
        [string] $VaultName,

        [Parameter(Mandatory = $true)]
        [string] $SecretName,

        [Parameter(Mandatory = $true)]
        [string] $TemporaryAccessPass,

        [Parameter(Mandatory = $true)]
        [datetime] $NotBefore,

        [Parameter(Mandatory = $true)]
        [datetime] $ExpiresOn
    )

    # SecretValue requires a SecureString; the plaintext copy is local to this scope and never
    # logged, printed, or returned.
    $secureValue = ConvertTo-SecureString -String $TemporaryAccessPass -AsPlainText -Force

    $secretParams = @{
        VaultName   = $VaultName
        Name        = $SecretName
        SecretValue = $secureValue
        NotBefore   = $NotBefore
        Expires     = $ExpiresOn
    }
    [void] (Set-AzKeyVaultSecret @secretParams)

    # Only the vault and secret name are returned - never the value - so callers can log or
    # email a pointer without ever handling the pass itself.
    return [pscustomobject]@{
        VaultName  = $VaultName
        SecretName = $SecretName
    }
}
```

- [ ] **Step 2: Rename and rewrite `Get-FirstSignInEmailBody` to `Get-ManagerNotificationEmailBody`**

Replace the entire existing function:

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
        [int] $LifetimeInMinutes,

        [Parameter(Mandatory = $true)]
        [datetime] $ValidFromDate
    )

    # The pass activates on the hire's start date, not at script-run time, so express the
    # window as "active on <date> for about N hours" rather than a countdown from now.
    $hours = [int]($LifetimeInMinutes / 60)

    # Plain-text body. The manager hands this to the new hire in person on day one.
    return @"
A new account is ready for $HireDisplayName.

Please give the new hire their one-time sign-in pass in person on their start date.

Your one-time sign-in pass becomes active on $($ValidFromDate.ToString('dddd, MMMM d, yyyy'))
and is valid for about $hours hours that day. It works only once.

  Work sign-in address : $HireUpn
  Temporary Access Pass: $TemporaryAccessPass

First sign-in steps (for the new hire):
  1. Go to https://www.office.com and choose Sign in.
  2. Enter your work sign-in address above.
  3. When asked for a password, choose "Use a Temporary Access Pass" and enter the code above.
  4. Follow the prompts to set up the Microsoft Authenticator app - this becomes your
     permanent sign-in method.
  5. The pass works once and is valid for about $hours hours on the start date above, so
     finish setup in one sitting. If it expires, contact IT for a new one.
"@
}
```

with:

```powershell
function Get-ManagerNotificationEmailBody {
    <#
    .SYNOPSIS
        Build the manager notification email body: a pointer to the Key Vault secret holding
        the Temporary Access Pass, plus first-sign-in steps. Never contains the pass itself.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $HireDisplayName,

        [Parameter(Mandatory = $true)]
        [string] $HireUpn,

        [Parameter(Mandatory = $true)]
        [string] $VaultName,

        [Parameter(Mandatory = $true)]
        [string] $SecretName,

        [Parameter(Mandatory = $true)]
        [int] $LifetimeInMinutes,

        [Parameter(Mandatory = $true)]
        [datetime] $ValidFromDate
    )

    # The secret's readable window mirrors the pass's own activation window, not script-run
    # time, so express it as "retrievable on <date> for about N hours" rather than a countdown.
    $hours = [int]($LifetimeInMinutes / 60)

    # Plain-text body. It never contains the pass itself - only where to retrieve it.
    return @"
A new account is ready for $HireDisplayName.

Please retrieve their one-time sign-in pass from Key Vault on their start date and hand it to
them in person.

  Work sign-in address: $HireUpn
  Key Vault: $VaultName
  Secret name: $SecretName

The secret becomes readable on $($ValidFromDate.ToString('dddd, MMMM d, yyyy')) and stays
readable for about $hours hours that day. Retrieve it with:

  az keyvault secret show --vault-name $VaultName --name $SecretName --query value -o tsv

First sign-in steps (for the new hire):
  1. Go to https://www.office.com and choose Sign in.
  2. Enter your work sign-in address above.
  3. When asked for a password, choose "Use a Temporary Access Pass" and enter the retrieved code.
  4. Follow the prompts to set up the Microsoft Authenticator app - this becomes your
     permanent sign-in method.
  5. The pass works once and is valid for about $hours hours on the start date above, so
     finish setup in one sitting. If it expires, contact IT for a new one.
"@
}
```

- [ ] **Step 3: Update the PLAN line and ShouldProcess action text**

Replace:

```powershell
    # Print the human-readable planned action for this hire, including the TAP activation date, so
    # the dry run visibly shows the pass aligned to the hire's start date rather than run time.
    $planMessage = "PLAN {0}: create {1} | group {2} | license {3} (group-based) | TAP valid {4:yyyy-MM-dd} -> email {5}" -f $displayName, $plan.Upn, $plan.Group, $plan.License, $plan.StartDate, $plan.Manager
    Write-Log -Message $planMessage -Level INFO

    # ShouldProcess gates every real change. Under -WhatIf it returns $false and PowerShell prints
    # the standard "What if:" line, so nothing below runs and no Graph cmdlet is ever invoked.
    $action = "Create Entra user, add to '$($plan.Group)', issue Temporary Access Pass, email manager"
```

with:

```powershell
    # Print the human-readable planned action for this hire, including the Key Vault secret's
    # readable date, so the dry run visibly shows the pass and its delivery both aligned to the
    # hire's start date rather than run time.
    $planMessage = "PLAN {0}: create {1} | group {2} | license {3} (group-based) | TAP -> Key Vault secret 'TAP-{4}' (readable {5:yyyy-MM-dd}) -> notify {6}" -f $displayName, $plan.Upn, $plan.Group, $plan.License, $plan.Username, $plan.StartDate, $plan.Manager
    Write-Log -Message $planMessage -Level INFO

    # ShouldProcess gates every real change. Under -WhatIf it returns $false and PowerShell prints
    # the standard "What if:" line, so nothing below runs and no Graph or Az cmdlet is ever invoked.
    $action = "Create Entra user, add to '$($plan.Group)', issue Temporary Access Pass, write it to Key Vault, notify manager"
```

- [ ] **Step 4: Rewire steps 3-4 into steps 3-5 (vault write replaces direct email of the pass)**

Replace:

```powershell
        # 3) Issue a one-time TAP that becomes valid at the start of the hire's onboarding day (startDateTime),
        #    not at script-run time - accounts are often created days early and the manager reads the email async.
        $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $newUser.Id -BodyParameter @{
            isUsableOnce      = $true
            startDateTime     = $plan.StartDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
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
            ValidFromDate       = $plan.StartDate
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
```

with:

```powershell
        # 3) Issue a one-time TAP that becomes valid at the start of the hire's onboarding day (startDateTime),
        #    not at script-run time - accounts are often created days early and the manager reads the email async.
        $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $newUser.Id -BodyParameter @{
            isUsableOnce      = $true
            startDateTime     = $plan.StartDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
            lifetimeInMinutes = $tapLifetimeMinutes
        }

        # 4) Write the pass to a per-hire Key Vault secret whose readable window mirrors the
        #    TAP's own window, so it cannot be retrieved before the pass would even work. The
        #    TAP value goes ONLY into this secret - never to the log, console, or an email.
        $vaultSecretParams = @{
            VaultName           = $KeyVaultName
            SecretName          = "TAP-$($plan.Username)"
            TemporaryAccessPass = $tap.TemporaryAccessPass
            NotBefore           = $plan.StartDate
            ExpiresOn           = $plan.StartDate.AddMinutes($tapLifetimeMinutes)
        }
        $vaultSecret = Set-TapVaultSecret @vaultSecretParams

        # 5) Email the manager a pointer to the secret and first-sign-in steps for in-person
        #    handoff. Send-MailMessage is deprecated/obsolete in PS7; it stands in here for the
        #    org's approved mail-relay path in this demo (a real deployment would call that instead).
        $emailBodyParams = @{
            HireDisplayName   = $displayName
            HireUpn           = $plan.Upn
            VaultName         = $vaultSecret.VaultName
            SecretName        = $vaultSecret.SecretName
            LifetimeInMinutes = $tapLifetimeMinutes
            ValidFromDate     = $plan.StartDate
        }
        $emailBody = Get-ManagerNotificationEmailBody @emailBodyParams
        $mailParams = @{
            To         = $plan.Manager
            From       = $FromAddress
            SmtpServer = $SmtpServer
            Subject    = "First-day sign-in details for $displayName"
            Body       = $emailBody
        }
        Send-MailMessage @mailParams

        Write-Log -Message ("Provisioned {0}, wrote pass to Key Vault, and notified {1}." -f $plan.Upn, $plan.Manager) -Level SUCCESS
        $results.Add([pscustomobject]@{ Upn = $plan.Upn; Status = 'Created' })
```

- [ ] **Step 5: Run the offline dry run and verify the new PLAN line format**

Run:
```bash
pwsh -NoProfile -File ./src/New-EntraUsersFromCsv.ps1 -CsvPath ./data/new-hires.csv -WhatIf
```
Expected 7 `PLAN` lines (exact, given the current `data/new-hires.csv`):
```
PLAN Jordan Doe: create jdoe@contoso.com | group Attorneys-Users | license SPE_E5 (group-based) | TAP -> Key Vault secret 'TAP-jdoe' (readable 2026-07-13) -> notify alan.pierce@contoso.com
PLAN Jamie Doe: create jdoe2@contoso.com | group Legal-Support-Users | license SPE_E3 (group-based) | TAP -> Key Vault secret 'TAP-jdoe2' (readable 2026-07-13) -> notify alan.pierce@contoso.com
PLAN Priya Kumar: create pkumar@contoso.com | group IT-Staff | license SPE_E5 (group-based) | TAP -> Key Vault secret 'TAP-pkumar' (readable 2026-07-20) -> notify dana.wells@contoso.com
PLAN Marcus Lee: create mlee@contoso.com | group Finance-Users | license SPE_E3 (group-based) | TAP -> Key Vault secret 'TAP-mlee' (readable 2026-07-13) -> notify rosa.nunez@contoso.com
PLAN Chen Wu: create cwu@contoso.com | group Marketing-Users | license SPE_E3 (group-based) | TAP -> Key Vault secret 'TAP-cwu' (readable 2026-07-20) -> notify rosa.nunez@contoso.com
PLAN Aisha Bello: create abello@contoso.com | group HR-Users | license SPE_E3 (group-based) | TAP -> Key Vault secret 'TAP-abello' (readable 2026-07-13) -> notify dana.wells@contoso.com
PLAN Tom Riley: create triley@contoso.com | group Legal-Support-Users | license SPE_E3 (group-based) | TAP -> Key Vault secret 'TAP-triley' (readable 2026-07-27) -> notify alan.pierce@contoso.com
```
Also confirm: the two skip warnings (blank-First row, unmapped `Robotics` row) still print, the final summary table still has 7 `Planned (WhatIf)` rows, and there is still no `Connect-MgGraph`/`Connect-AzAccount` call.

- [ ] **Step 6: Lint**

Run:
```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src/New-EntraUsersFromCsv.ps1 -Settings PSGallery | Where-Object { $_.Severity -in 'Warning','Error' } | Format-Table -AutoSize"
```
Expected: no rows (empty) — the `ConvertTo-SecureString -AsPlainText -Force` call inside `Set-TapVaultSecret` must NOT appear here; the `SuppressMessageAttribute` from Step 1 is what keeps it out. If it does appear, the attribute's rule name or placement is wrong, not the call itself — fix the attribute, do not remove the conversion.

- [ ] **Step 7: Commit**

```bash
git add src/New-EntraUsersFromCsv.ps1
git commit -m "feat: deliver TAP via Key Vault secret instead of email

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ri1cHqQytuiZnrU3b8jFay"
```

---

## Task 3: Update prompt, narrative, README, and session context

**Files:**
- Modify: `prompt/prompt.md`
- Modify: `docs/process-narrative.md`
- Modify: `README.md`
- Modify: `SESSION_CONTEXT.md`

- [ ] **Step 1: Update `prompt/prompt.md`**

Replace:

```markdown
- **No password.** Issue a one-time Temporary Access Pass and email it, with first-sign-in
  instructions, to the hire's manager (a Manager column in the CSV) for in-person handoff.
  Never write the pass to a log. Align the pass to the hire's start date (a StartDate column
  in the CSV): set its `startDateTime` to the onboarding day with a workday-length window,
  not a short lifetime from run time - accounts are provisioned early and the email is
  asynchronous, so a run-time countdown expires before the hire ever signs in.
```

with:

```markdown
- **No password, and the pass never travels by email.** Issue a one-time Temporary Access Pass,
  write it to a per-hire Azure Key Vault secret, and email the manager only a pointer to that
  secret (vault name, secret name, retrieval command) - never the pass value. Never write the
  pass to a log, console, or email. Align both the pass and the secret's readable window to the
  hire's start date (a StartDate column in the CSV): set the TAP's `startDateTime` and the
  secret's `NotBefore`/`Expires` to the onboarding day with a matching workday-length window,
  not a short lifetime from run time - accounts are provisioned early and the notification is
  asynchronous, so a run-time countdown expires before the hire ever signs in, and a secret
  readable early would just move the "credential sits around" problem from a mailbox to a vault.
```

- [ ] **Step 2: Add a new section 8 to `docs/process-narrative.md`, renumber the old section 8 to 9**

Replace:

```markdown
### 8. Offline `-WhatIf`: zero setup, zero risk
```

with:

```markdown
### 8. The pass still had to stop living in an inbox

Follow-up interview feedback pushed on this chain one link further: even a one-time, single-use
Temporary Access Pass has a weaker security property once it is emailed, because the value then
sits in a mailbox and a mail-relay log indefinitely, with no access control and no audit trail on
who read it or when.

The first instinct was to ask whether the credential could be removed altogether - some newer
Microsoft Entra patterns (Verified ID plus Face Check) sounded, from the outside, like they might
onboard a hire with no bootstrap credential at all. Checking Microsoft's own documentation closed
that off: Verified ID and Face Check strengthen the identity-proofing step *before* a TAP is
issued; they do not remove the TAP itself. The only genuinely credential-free path documented is
admin-side FIDO2 hardware-key provisioning, which requires shipping a physical security key to
every hire ahead of time - a different onboarding model, not a smaller fix to this one.

So the fix stayed narrow and became a direct parallel to the start-date correction in section 7:
keep the TAP, change how it is delivered. The pass is now written to a per-hire Azure Key Vault
secret instead of an email body, and the manager gets a pointer (vault name, secret name, a
retrieval command) instead of the value. The secret's own readable window - `NotBefore` and
`Expires` - is set to mirror the TAP's own activation window exactly, so a manager cannot pull
the value before the pass would even work. That closes the "credential sits around waiting"
problem for good, instead of just relocating it from a mailbox to a vault.

### 9. Offline `-WhatIf`: zero setup, zero risk
```

- [ ] **Step 3: Update the byline at the bottom of `docs/process-narrative.md`**

Replace:

```markdown
*Built with Claude (Opus 4.8)*
```

with:

```markdown
*Built with Claude (Opus 4.8); Key Vault TAP delivery added with Claude (Sonnet 5)*
```

- [ ] **Step 4: Add a prerequisites note to `README.md`**

Insert a new section immediately after the "Run the demo (offline, no tenant needed)" section (after its code block and the "Watch for" paragraph that Step 5 below updates), before "## Talking points":

```markdown
## Prerequisites for a real (non `-WhatIf`) run

- Microsoft.Graph sub-modules (as before), plus `Az.Accounts` and `Az.KeyVault`.
- The app registration needs `Key Vault Secrets Officer` at the target vault (to write TAP
  secrets), in addition to its existing Graph permissions.
- A Managers/Onboarding security group needs `Key Vault Secrets User` at the vault, so managers
  can retrieve secrets. This script does not grant that role - it is tenant config, provisioned
  the same way as the TAP policy and the department groups.
```

- [ ] **Step 5: Update the "Watch for" line in `README.md`**

Replace:

```markdown
This prints the full plan and changes nothing. Watch for: the `jdoe` / `jdoe2` collision
resolving, the blank row and the unmapped `Robotics` row being skipped with reasons, and the
per-hire `PLAN ...` line ending in `TAP valid <date> -> email <manager>`.
```

with:

```markdown
This prints the full plan and changes nothing. Watch for: the `jdoe` / `jdoe2` collision
resolving, the blank row and the unmapped `Robotics` row being skipped with reasons, and the
per-hire `PLAN ...` line ending in `TAP -> Key Vault secret '<name>' (readable <date>) ->
notify <manager>`.
```

- [ ] **Step 6: Update the Temporary Access Pass talking point in `README.md`**

Replace:

```markdown
- **Temporary Access Pass** - the hire never gets a password. They get a single-use pass that
  activates on the hire's start date and is valid for an ~8-hour window that day, emailed to
  their manager for in-person handoff, with first-sign-in steps. Aligning validity to the start
  date (instead of a short window from script-run time) matters because email is asynchronous
  and accounts are often created days before onboarding. Bootstrapping a first credential is
  inherently out-of-band; if there is no manager, the fallback is a handoff report to the
  operator.
```

with:

```markdown
- **Temporary Access Pass, delivered through Key Vault, not email** - the hire never gets a
  password. They get a single-use pass that activates on the hire's start date, written to a
  per-hire Key Vault secret whose readable window mirrors the pass's own ~8-hour window that day.
  The manager gets an email, but it carries only a pointer (vault name, secret name, retrieval
  command) - never the pass value - so the credential itself never sits in a mailbox with no
  access control or audit trail. Aligning both windows to the start date (instead of a short
  countdown from script-run time) matters because the notification is asynchronous and accounts
  are often created days before onboarding. Bootstrapping a first credential is inherently
  out-of-band; if there is no manager, the fallback is a handoff report to the operator.
```

- [ ] **Step 7: Update the byline at the bottom of `README.md`**

Replace:

```markdown
*Built with Claude (Opus 4.8)*
```

with:

```markdown
*Built with Claude (Opus 4.8); Key Vault TAP delivery added with Claude (Sonnet 5)*
```

- [ ] **Step 8: Run the final full offline dry run as the acceptance check**

Run:
```bash
pwsh -NoProfile -File ./src/New-EntraUsersFromCsv.ps1 -CsvPath ./data/new-hires.csv -WhatIf
```
Expected: matches the updated README "Run the demo" description and the exact 7 PLAN lines from Task 2 Step 5.

- [ ] **Step 9: Lint one more time**

Run:
```bash
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src/New-EntraUsersFromCsv.ps1 -Settings PSGallery | Where-Object { $_.Severity -in 'Warning','Error' } | Format-Table -AutoSize"
```
Expected: no rows (empty).

- [ ] **Step 10: Update `SESSION_CONTEXT.md`**

Replace:

```markdown
Resume context for `C:\Projects\Demo` (origin: `github.com/thoumyvision/entra-provisioning-demo`).
Last updated 2026-07-07.
```

with:

```markdown
Resume context for `C:\Projects\Demo` (origin: `github.com/thoumyvision/entra-provisioning-demo`).
Last updated 2026-07-16.
```

Then, in the "## Key decisions and build-time corrections" list, add a new bullet after the TAP-start-date bullet:

```markdown
- **TAP delivery moved from email to Key Vault pull** (interview-follow-up-directed): the pass is
  now written to a per-hire Key Vault secret (`TAP-<username>`) whose NotBefore/Expires mirror the
  TAP's own start-date activation window; the manager email carries only a pointer (vault name,
  secret name, retrieval command), never the value. Considered and rejected eliminating the TAP
  itself (Verified ID/Face Check only strengthens proofing before a TAP is issued; the only
  genuinely TAP-free path needs pre-shipped FIDO2 hardware, a different onboarding model) and
  script-managed per-secret RBAC (too much added attack surface for this demo). See
  `docs/superpowers/specs/2026-07-16-tap-keyvault-delivery-design.md` and
  `docs/superpowers/plans/2026-07-16-tap-keyvault-delivery.md`.
```

Then, in the "## How to run and verify" section, replace:

```markdown
Expected: 7 `PLAN` lines, `jdoe` -> `jdoe2` collision resolved, the blank-First row and the
unmapped `Robotics` row skipped with reasons, each PLAN line ending `TAP valid <date> -> email
<manager>`, a 7-row `Planned (WhatIf)` summary, and no `Connect-MgGraph`. Lint gate:
```

with:

```markdown
Expected: 7 `PLAN` lines, `jdoe` -> `jdoe2` collision resolved, the blank-First row and the
unmapped `Robotics` row skipped with reasons, each PLAN line ending `TAP -> Key Vault secret
'<name>' (readable <date>) -> notify <manager>`, a 7-row `Planned (WhatIf)` summary, and no
`Connect-MgGraph` or `Connect-AzAccount`. Lint gate:
```

- [ ] **Step 11: Commit**

```bash
git add prompt/prompt.md docs/process-narrative.md README.md SESSION_CONTEXT.md
git commit -m "docs: reflect Key Vault TAP delivery in prompt, narrative, README, and session context

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ri1cHqQytuiZnrU3b8jFay"
```

- [ ] **Step 12: Push**

```bash
git push
```

---

## Self-Review (completed during authoring)

**Spec coverage:** second auth context + `-KeyVaultName` param + updated help (spec §3, Task 1);
`Set-TapVaultSecret` + secret window mirroring TAP window (spec §4, Task 2 Step 1); renamed
`Get-ManagerNotificationEmailBody` (spec §5, Task 2 Step 2); PLAN line + wiring (spec §5, Task 2
Steps 3-4); error handling unchanged/inherited (spec §6, no new task needed - the existing
per-hire `try/catch` already wraps the new calls since they sit inside it); all four doc updates
(spec §7, Task 3); rejected alternatives documented in the spec itself, not re-litigated in the
plan (spec §8). All spec sections map to a task.

**Placeholder scan:** no TBD/TODO; all code is complete, including the exact PLAN line text for
every row in the current `data/new-hires.csv`.

**Type consistency:** `Set-TapVaultSecret -VaultName/-SecretName/-TemporaryAccessPass/-NotBefore/-ExpiresOn`
returning `{ VaultName; SecretName }` and `Get-ManagerNotificationEmailBody
-HireDisplayName/-HireUpn/-VaultName/-SecretName/-LifetimeInMinutes/-ValidFromDate` are defined in
Task 2 Steps 1-2 and consumed with matching names in Task 2 Step 4.
