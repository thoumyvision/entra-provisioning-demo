# Design: TAP delivery via Key Vault pull instead of email

**Date:** 2026-07-16
**Author:** Marcus Whitman (with Claude)
**Repo:** `entra-provisioning-demo`
**Purpose:** Harden the credential-handoff link in `src/New-EntraUsersFromCsv.ps1` so the
one-time Temporary Access Pass (TAP) never travels through the manager's mailbox, continuing
the demo's existing credential-chain narrative (see
`docs/superpowers/specs/2026-07-07-entra-user-provisioning-demo-design.md` section 3.6 and
`docs/process-narrative.md` sections 6-7) with its next hardening step.

---

## 1. Why this exists

Follow-up interview feedback raised a question the original design had not pushed on: the
credential chain ends with the TAP value sitting in a plaintext email, indefinitely, in a
mailbox and mail-relay log with no access control or audit trail. That is a weaker security
property than the one-time, single-use TAP itself implies.

Initial research explored whether the onboarding flow could avoid a TAP (or any bootstrap
credential) entirely. It cannot, in any form that still matches this demo's remote/async
onboarding model: Microsoft's own documented "Verified ID + Face Check" pattern strengthens
identity proofing *before* a TAP is issued, but still issues and enters a TAP. The only
genuinely TAP-free path (admin-side FIDO2 hardware-key provisioning via Graph, preview) requires
pre-shipping physical keys to every new hire, which is a different onboarding model, not a
delivery-mechanism swap. That path is out of scope here; see section 8.

The correctly-scoped fix is narrower and real: keep the TAP, change how it reaches the manager.
Write it to a per-hire, time-bound Azure Key Vault secret instead of an email body. The manager
retrieves it on demand, access is RBAC-controlled and logged, and the value never sits in a
mailbox.

---

## 2. Data flow

Per hire, the provisioning loop gains one link and changes one:

1. Create the Entra user, add to the department's M365 group (unchanged).
2. Issue the one-time TAP via Graph (unchanged mechanism; window changes, see section 4).
3. **New:** write the TAP value into a per-hire Key Vault secret with a validity window that
   mirrors the TAP's own window.
4. **Changed:** email the manager a *pointer* to that secret (vault name, secret name, retrieval
   command) instead of the TAP value. The email never contains the credential.

Retrieval access (who can read the secret) is a **tenant prerequisite the script assumes is
already provisioned**, exactly like the TAP authentication-method policy and the department-map's
M365 group/license mappings already are. The script does not create, grant, or manage Key Vault
RBAC; that is one-time tenant setup, not a per-run action.

---

## 3. New auth context and parameters

Key Vault's data plane is not Microsoft Graph, so the script authenticates twice against the
same app registration and certificate — no new credential type is introduced:

```powershell
Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint
Connect-AzAccount -ServicePrincipal -Tenant $TenantId -ApplicationId $ClientId -CertificateThumbprint $CertificateThumbprint
```

New parameter: `-KeyVaultName` (mandatory for a real run, same tier as `-TenantId`, `-ClientId`,
`-CertificateThumbprint`).

`Import-Module -Name Az.Accounts, Az.KeyVault` moves into the same `$isRealRun`-gated import
block as the existing `Microsoft.Graph.*` imports, so `-WhatIf` continues to need no modules
installed and no tenant connection — this must not regress.

New prerequisites, documented in the script's `.NOTES` and in `README.md`, not enforced by the
script:

- The app registration holds **Key Vault Secrets Officer** at the vault scope (to write secrets).
- A Managers/Onboarding security group holds **Key Vault Secrets User** at the vault scope (to
  read secrets). Any member of that group can read any hire's secret; the demo does not scope
  RBAC per-secret (see section 8 for the rejected tighter alternative and why).

---

## 4. Secret lifecycle

Secret name: `TAP-<username>`, where `<username>` is the existing collision-safe handle already
computed by `Resolve-UniqueUsername` (alphanumeric only, already legal for a Key Vault secret
name — no new sanitization needed).

The secret's readable window mirrors the TAP's own usable window exactly, rather than being
readable from creation time:

- `NotBefore` = the hire's start-date activation instant (the same `datetime` already computed
  for the TAP's `startDateTime`, `Kind=Utc`, 08:00 on `StartDate`).
- `Expires` = that instant plus the TAP's `lifetimeInMinutes` (480).

A manager who checks Key Vault before the start date gets denied by policy, the same as if they
tried to use the TAP itself early. This closes the exact gap that motivated the change — a
credential is never retrievable before it is meant to be used — rather than only moving the
"sits around unused" window from a mailbox to a vault.

---

## 5. Function changes in `src/New-EntraUsersFromCsv.ps1`

- **New function `Set-TapVaultSecret`** — wraps `Set-AzKeyVaultSecret` with the `NotBefore`/
  `Expires` window from section 4. Returns only the vault name and secret name for logging;
  never the secret value.
- **`Get-FirstSignInEmailBody` renamed to `Get-ManagerNotificationEmailBody`** — the rename
  reflects that the function no longer carries a credential, only a pointer to one. New body
  content: hire name, work sign-in address (UPN), vault name, secret name, a retrieval command
  (`az keyvault secret show --vault-name <vault> --name <secret> --query value -o tsv`), and an
  explicit reminder that retrieval only works from the start date onward. The five-step
  first-sign-in walkthrough for the hire is unchanged.
- **PLAN line** (the `-WhatIf` output) changes from
  `... TAP valid <date> -> email <manager>` to
  `... TAP -> Key Vault secret 'TAP-<user>' (readable <date>) -> notify <manager>`, so the dry
  run still shows the full chain, including the new link, at a glance.

No CSV or `department-map.psd1` schema changes — the `Manager` column continues to be the
notification recipient's email address.

---

## 6. Error handling

No new pattern. The Key Vault write joins the existing single `try/catch` per hire alongside
user creation, group membership, and TAP issuance. A vault write failure fails that hire's row
and the batch continues with the next, identical to how a Graph failure is handled today. The
"never log the credential" invariant extends trivially to the secret value, since
`Set-TapVaultSecret` never returns it.

---

## 7. Docs updated alongside the script

Following the same chain-of-evidence discipline the original build established (the judgment
lives in the prompt and the narrative, not just the code):

- **`prompt/prompt.md`** — amend the credential-handling requirement to specify Key Vault
  pull-based delivery instead of email, the same way the StartDate/TAP-alignment requirement was
  added after that correction.
- **`docs/process-narrative.md`** — a new section continuing the numbered decision list after
  section 7, framed as the next question in the same interrogation ("the pass had to be valid
  when the hire arrives... but why does a one-time credential need to sit in a mailbox at all?").
  Attributed generically to interview follow-up feedback — **no firm or interviewer named**,
  consistent with the de-identification already done for public release (commit `0181625`).
- **`README.md`** — new prerequisites (`Az.Accounts`, `Az.KeyVault` modules; the two Key Vault
  RBAC roles from section 3), the updated expected `-WhatIf` output line, and an updated
  old-vs-new talking point for credential delivery.
- **`SESSION_CONTEXT.md`** — a new decision-log entry in the same style as the existing ones.

---

## 8. Rejected alternative: per-secret scoped RBAC

Considered and rejected as over-scope for this demo: instead of vault-level group RBAC, resolve
the CSV `Manager` value to an Entra object and have the script grant `Key Vault Secrets User`
scoped to just that one secret (Key Vault supports per-object RBAC scoping). True least
privilege — only the specific hire's manager could read that specific secret.

Rejected because it requires a materially larger permission grant on the app registration
(role-assignment rights, not just directory/vault writes), a Manager-to-object-ID resolution
step the CSV does not currently support, and cleanup logic so per-secret role assignments do not
accumulate indefinitely. That is meaningfully more attack surface and complexity for a script
whose job is provisioning users, not managing authorization. Noted in `README.md` as a documented
"next hardening step," not built.

Also rejected: pre-shipped FIDO2 hardware keys to eliminate the TAP itself (see section 1). Out
of scope because it changes the onboarding model (physical logistics, preview Graph API,
Authentication Administrator-tier permissions) rather than hardening the existing one.

---

## 9. Out of scope (YAGNI)

- No script-managed Key Vault RBAC (section 8).
- No change to how the TAP itself is issued via Graph, only how its value is delivered.
- No CSV or `department-map.psd1` schema changes.
- No Pester suite — verification stays offline `-WhatIf` + PSScriptAnalyzer, matching the
  original design's rationale (demo artifact, not a maintained product).
