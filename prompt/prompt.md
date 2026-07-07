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
