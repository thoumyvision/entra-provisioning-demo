# SESSION_CONTEXT - Entra User-Provisioning Demo

Resume context for `C:\Projects\Demo` (origin: `github.com/thoumyvision/Demo`). Last updated
2026-07-07.

## Status: complete and pushed

All planned work is done, reviewed, and on `main` (in sync with `origin/main`, HEAD `163fa5a`).
The demo runs offline and is ready to present. Nothing is mid-flight.

## What this repo is

A before/after technical demonstration: a 2019 on-prem Active Directory provisioning script
(`legacy/NewUsers.ps1`, the "before") beside a modern, config-driven Microsoft Entra / Graph
provisioning script (`src/New-EntraUsersFromCsv.ps1`, the "after"), plus the crafted prompt and
codified PowerShell standards that produced it. The gap between the two files, and the process
that produced it, is the point.

Read `AGENTS.md` and `docs/process-narrative.md` first on resume.

## Layout

| Path | What it is |
|------|------------|
| `legacy/NewUsers.ps1` | The 2019 original (verbatim, flaws intact). |
| `src/New-EntraUsersFromCsv.ps1` | The modern Entra/Graph script. |
| `src/department-map.psd1` | Department -> M365 group + license SKU config. |
| `data/new-hires.csv` | Fake test data (deliberate collision, blank row, unmapped dept, StartDate column). |
| `prompt/prompt.md` | The crafted prompt that directed the build. |
| `standards/pwsh-standards.SKILL.md` | Vendored copy of the codified standards. |
| `README.md` | Run-sheet + old-vs-new table + talking points. |
| `docs/process-narrative.md` | Decision-by-decision narrative (interviewer-facing). |
| `docs/superpowers/specs/`, `plans/` | Approved spec and task plan (historical design records). |

## How to run and verify (offline, no tenant, no Graph module)

```powershell
pwsh -NoProfile -File src/New-EntraUsersFromCsv.ps1 -CsvPath data/new-hires.csv -WhatIf
```

Expected: 7 `PLAN` lines, `jdoe` -> `jdoe2` collision resolved, the blank-First row and the
unmapped `Robotics` row skipped with reasons, each PLAN line ending `TAP valid <date> -> email
<manager>`, a 7-row `Planned (WhatIf)` summary, and no `Connect-MgGraph`. Lint gate:

```powershell
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path src/New-EntraUsersFromCsv.ps1 -Settings PSGallery"
```

Expected: 0 findings.

## How it was built

Executed the plan at `docs/superpowers/plans/2026-07-07-entra-user-provisioning-demo.md` via
subagent-driven development: a fresh implementer subagent per task, an independent spec+quality
review after each, and a whole-branch review at the end. Verification is offline `-WhatIf`
behavior + PSScriptAnalyzer, not Pester (demo artifact).

## Key decisions and build-time corrections (so they are not re-litigated)

- **Removed a dead `$ScriptRoot` fallback block** the plan's skeleton carried (Marcus's call) -
  the `-MapPath` default already reads `$PSScriptRoot`.
- **`[AllowEmptyCollection()]`** on the username resolver's `$AssignedUsernames` param - a
  mandatory collection parameter otherwise rejects the legitimately-empty first-hire set.
- **Renamed `New-UniqueUsername` -> `Resolve-UniqueUsername`** - the function is a pure
  computation; the `New-` verb tripped `PSUseShouldProcessForStateChangingFunctions`, and adding
  a fake `SupportsShouldProcess` would have been a misleading smell.
- **Splatting, not backtick continuation** - the whole-branch review caught 5 multi-parameter
  calls using backticks, contradicting the vendored standard; all converted to splats.
- **Cleaned the standards doc** - removed a leaked `$ARGUMENTS` placeholder and an em-dash from
  the global source and the vendored copy.
- **TAP aligned to the hire's start date** (Marcus-directed): a one-time 60-minute TAP created at
  run time expires before use (async manager email, accounts cut days early). Added a `StartDate`
  CSV column; the TAP now sets `startDateTime` to the onboarding day (08:00, pinned to UTC) with
  an 8-hour window, bounded by the tenant TAP policy. The review caught a timezone bug
  (`Kind=Unspecified` + `.ToUniversalTime()` could roll the day back on UTC+9/+10/+12 hosts);
  fixed with `SpecifyKind(...Utc)`. Prompt and README updated to match. See memory
  [[tap-align-to-start-date]].
- **Process narrative scrubbed** of interviewer-facing commentary (skepticism read, "landed best
  in round one", "AI writes junk" prior, etc.) since the narrative is read by the interviewer.

## Open items

- **Optional wording tweak (Marcus's call):** `docs/process-narrative.md` line ~27, "The gap
  between those two files is the argument." Offered to soften "argument" -> "point"; left as-is
  pending decision.
- **Pending `/claude-sync`:** the global `~/.claude/skills/pwsh-standards/` edits (5 new sections
  + `$ARGUMENTS`/em-dash cleanup) and the `~/.claude/skills/claude-sync/SKILL.md` edit adding this
  repo are made but uncommitted in the `claude-config` repo. Push them on the next evening sync.

## Notes

- Commit trailer for this repo (matches its existing history):
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` +
  `Claude-Session: https://claude.ai/code/session_01V6295VZRdgZjm4kSxApQ87`.
- ASCII only in scripts and Markdown; scripts UTF-8 no BOM (except `legacy/NewUsers.ps1`, a
  verbatim copy that retains its original BOM).
