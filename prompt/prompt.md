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
- **No password, and the pass never travels by email.** Issue a one-time Temporary Access Pass,
  write it to a per-hire Azure Key Vault secret, and email the manager only a pointer to that
  secret (vault name, secret name, retrieval command) - never the pass value. Never write the
  pass to a log, console, or email. Align both the pass and the secret's readable window to the
  hire's start date (a StartDate column in the CSV): set the TAP's `startDateTime` and the
  secret's `NotBefore`/`Expires` to the onboarding day with a matching workday-length window,
  not a short lifetime from run time - accounts are provisioned early and the notification is
  asynchronous, so a run-time countdown expires before the hire ever signs in, and a secret
  readable early would just move the "credential sits around" problem from a mailbox to a vault.
- **Collision-safe and idempotent.** First-initial + last name; if `jdoe` is taken, use `jdoe2`.
  Check the tenant on a real run; dedupe within the batch on a dry run.
- **Safe by default.** `SupportsShouldProcess`; a full `-WhatIf` that connects to nothing,
  changes nothing, and prints the plan. It must run on a machine with no Graph module installed.
- **Written for a human reviewer.** Full cmdlet and parameter names, no aliases, splatting,
  a guiding comment before each block. Someone should be able to read it without running it.

Handle bad input without crashing the batch: skip rows missing required fields or with an
unmapped department, report why, and keep going.
