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
