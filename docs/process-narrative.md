# How this demo was built: a narrative

This document is part of the demo. It records *how* the before/after script in this repo came to
exist, because the process is the point. The script matters; the judgment that shaped it matters
more.

The short version: this was not "AI, write me a script." It was an engineer with twenty years in
IT deciding what good looks like, front-loading that judgment, and directing an AI to execute it,
then pressure-testing the result until it held. The AI was fast, consistent hands. The
architecture, the standards, and every consequential decision were human.

---

## The situation

Second-round interview for an Enterprise Applications Automation Engineer role. In the first
round, the hiring manager was skeptical of AI-assisted work. That skepticism is fair, and arguing
with it would be the wrong move. The right move is to show what disciplined AI-assisted
engineering actually looks like, so the skepticism has nowhere to land.

So the demo is a deliberate before/after:

- **Before:** `legacy/NewUsers.ps1`, a real script written in 2019 to create Active Directory
  accounts from a CSV. It works. It also has a hardcoded plaintext password, no collision
  handling, no error handling, and it existed as six near-identical hand-edited copies, one per
  client.
- **After:** `src/New-EntraUsersFromCsv.ps1`, the same idea rebuilt for modern cloud identity,
  produced by directing an AI with a crafted prompt and a codified standards skill.

The gap between those two files is the argument.

---

## The decisions, and why each was made

The design was not handed down in one shot. It was built one decision at a time, each one
challenged before it was accepted. That sequence is worth reading, because it is the actual skill
on display.

### 1. A hybrid demo, not a live free-for-all

Three options were on the table: build the whole thing live on the call, pre-build it and walk
through it, or a hybrid. The hybrid won: pre-build the full artifact as a guaranteed fallback,
then do one small, contained live change (adding a field from a new CSV column) so the
interviewer sees real-time direction without betting a thirty-minute interview on live tooling
behaving. Payoff of a live demo, without the failure mode.

### 2. Pivot from on-prem AD to Microsoft Entra / Graph

The 2019 script uses `New-ADUser`. The modern version uses `New-MgUser` over Microsoft Graph.
This was deliberate on two fronts. It turns a cleanup story into a *modernization* story, which is
a stronger thing to show. And it maps directly onto the target environment (Graph, Entra, M365,
licensing) and onto the two technical-screen answers that landed best in round one: Microsoft
Graph and certificate-based authentication.

### 3. The chain of evidence: prompt + standards, both in the repo

The output quality had to be visibly attributable to the engineer, not to luck. So two artifacts
sit in the repo alongside the code:

- `prompt/prompt.md`, the crafted prompt. The judgment is front-loaded here: Graph not AD,
  cert-based auth, config-driven, group-based licensing, idempotent, `-WhatIf`, and "follow my
  pwsh-standards skill."
- `standards/pwsh-standards.SKILL.md`, the codified PowerShell standards the AI was told to
  follow. This is the load-bearing artifact for a skeptic. It proves the quality is a repeatable
  standard the engineer defined, not something the machine guessed at.

### 4. Written for a human reviewer

An explicit requirement, and arguably the most important one: the generated script must be
optimized for a human reading it, not just a machine running it. Full cmdlet and parameter names,
no aliases, splatting over line-continuation, a guiding comment before each block. If the reviewer
can read it top to bottom and follow it, the "AI writes junk" prior has nowhere to go. This became
a new section in the standards skill.

### 5. Group-based licensing

The script does not assign licenses per user. It adds the user to their department's M365 group
and lets the license flow from the group. That is the best-practice answer (single source of
truth, deprovisioning by group removal, no per-user drift), and choosing it on purpose, with the
per-user `Set-MgUserLicense` call shown but commented as the inferior alternative, demonstrates
knowing what good looks like rather than just knowing which API to call.

### 6. The credential chain, pressure-tested to the end

This is the part that was hardest, and the part that got interrogated most, driven by the
engineer's own questions:

- The old script hardcoded a shared plaintext password. The first fix was a random per-user
  password. Then: *how does the user actually get it?*
- Better answer: no password at all. Issue a one-time **Temporary Access Pass** and force the
  hire onto MFA on first sign-in. Then: *how does the user get the TAP?*
- A bootstrap credential can never travel through the account being created, because the hire
  cannot sign in yet. It is inherently an out-of-band handoff to someone who already has a trusted
  channel. So the TAP is emailed to the hire's **manager** (a Manager column in the CSV) for
  in-person handoff. Then: *and what does the hire do with it?*
- The manager email carries **first-sign-in instructions**, a five-step walkthrough from
  office.com to registering the Authenticator app.

That progression, from shared password to one-time pass to manager relay to first-sign-in steps,
is itself the strongest security answer in the demo, because it thinks past the happy path. It was
reached by refusing to accept the first plausible answer.

### 7. Offline `-WhatIf`: zero setup, zero risk

The demo runs in `-WhatIf` mode, fully offline. It connects to no tenant, needs no Graph module
installed, creates no stray users, and prints exactly what it *would* do. That is itself a
senior-engineer signal: a safe dry run built before anything touches production identity. It also
means the demo runs on any machine with nothing to set up beforehand.

---

## What is in this repo

| Path | What it is |
| --- | --- |
| `legacy/NewUsers.ps1` | The 2019 original. The "before." |
| `prompt/prompt.md` | The crafted prompt that directed the build. |
| `standards/pwsh-standards.SKILL.md` | The codified standards the AI followed. |
| `src/New-EntraUsersFromCsv.ps1` | The modern result. The "after." |
| `src/department-map.psd1` | Department -> group + license config. |
| `data/new-hires.csv` | Fake test data, with deliberate collision and bad rows. |
| `docs/superpowers/specs/` | The approved design spec. |
| `docs/superpowers/plans/` | The task-by-task implementation plan. |
| `docs/process-narrative.md` | This document. |
| `README.md` | The run-sheet and talking points. |

The spec (`docs/superpowers/specs/2026-07-07-entra-user-provisioning-demo-design.md`) and the plan
(`docs/superpowers/plans/2026-07-07-entra-user-provisioning-demo.md`) capture every decision above
in full detail. They were written and approved before any implementation code, which is its own
small demonstration of the process.

---

## How to build it from here

The plan is self-contained and assumes no prior context, so a fresh Claude Code session opened in
this repo can execute it directly:

1. Open a Claude Code session with this repo (`C:\Projects\Demo`) as the working directory.
2. Point it at `docs/superpowers/plans/2026-07-07-entra-user-provisioning-demo.md`.
3. Execute task by task. Each task ends with an offline `-WhatIf` run and a PSScriptAnalyzer lint
   as its acceptance check (this is a demo artifact, so verification is dry-run behavior and
   readability, not a unit-test suite).

The tasks are ordered so the script is runnable and reviewable at every step, and each finishes
with a commit.

---
*Built with Claude (Opus 4.8)*
