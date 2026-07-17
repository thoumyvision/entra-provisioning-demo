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

This demo was built for a second-round conversation about an Enterprise Applications Automation
Engineer role. It is a deliberate before/after, meant to make the engineering judgment visible
rather than describe it:

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

Three options were on the table: build the whole thing live, pre-build it and walk through it, or
a hybrid. The hybrid won: pre-build the full artifact, then do one small, contained live change
(adding a field from a new CSV column) to show real-time direction without depending on live
tooling behaving in a short session. Payoff of a live demo, without the failure mode.

### 2. Pivot from on-prem AD to Microsoft Entra / Graph

The 2019 script uses `New-ADUser`. The modern version uses `New-MgUser` over Microsoft Graph.
This was deliberate on two fronts. It turns a cleanup story into a *modernization* story, which is
a stronger thing to show. And it maps directly onto the target environment (Graph, Entra, M365,
licensing) and onto the core technologies the role centers on: Microsoft Graph and
certificate-based authentication.

### 3. The chain of evidence: prompt + standards, both in the repo

The output quality had to be visibly attributable to the engineer, not to luck. So two artifacts
sit in the repo alongside the code:

- `prompt/prompt.md`, the crafted prompt. The judgment is front-loaded here: Graph not AD,
  cert-based auth, config-driven, group-based licensing, idempotent, `-WhatIf`, and "follow my
  pwsh-standards skill."
- `standards/pwsh-standards.SKILL.md`, the codified PowerShell standards the AI was told to
  follow. This is the load-bearing artifact: it shows the quality is a repeatable standard the
  engineer defined, not something the machine guessed at.

### 4. Written for a human reviewer

An explicit requirement, and arguably the most important one: the generated script must be
optimized for a human reading it, not just a machine running it. Full cmdlet and parameter names,
no aliases, splatting over line-continuation, a guiding comment before each block. A reviewer
should be able to read it top to bottom and trust it without running it. This became a new section
in the standards skill.

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

### 7. The pass had to be valid when the hire actually arrives

This link in the credential chain was forged during the build, not the design, which is exactly
why it is worth recording. The first implementation issued the Temporary Access Pass with a
60-minute lifetime counted from the moment the script runs. On a screenshare that looks fine. In
practice it is broken: the pass reaches the hire through an asynchronous email to their manager,
and accounts are routinely provisioned days before someone's first day, so a 60-minute countdown
starting at provisioning time is dead long before the new hire ever sits down.

The correction was to stop thinking in "minutes from now" and start thinking in "the hire's start
date." The CSV gained a StartDate column, and the script now sets the pass's `startDateTime` to the
onboarding day with a workday-length window, bounded by the tenant's own Temporary Access Pass
policy. The prompt was updated to ask for this explicitly, so the chain of evidence stays honest:
the requirement lives in the prompt, the behavior lives in the script.

Then the review earned its keep. It flagged that the activation timestamp was being built with no
explicit time zone, so on a host east of UTC+8 the pass would activate a calendar day earlier than
the date shown to the manager, a quiet, geography-dependent bug of the kind that ships when nobody
is looking. Pinning the instant to UTC closed it. The point is not that the first cut had a bug; it
is that a disciplined process expects one and goes looking for it.

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

`standards/pwsh-standards.SKILL.md` is a point-in-time exhibit for the chain-of-evidence table
above. The `.claude/skills/` folder is the live, functioning copy: open this repo in Claude Code
and the same skills that gated the real build (`pwsh-standards`, plus the `using-superpowers`,
`brainstorming`, `writing-plans`, `executing-plans`, and `subagent-driven-development` skills named
in this repo's own `CLAUDE.md`) are active, with no dependency on Marcus's personal `~/.claude/`
config. Also vendored: `graph-api`, Marcus's own Microsoft Graph reference skill. It didn't gate
the original build, but it is what an agent would actually reach for while extending
`src/New-EntraUsersFromCsv.ps1` (cert-based auth, pagination, error handling), which is exactly the
kind of live change the interview's live segment exercises. See
`.claude/skills/THIRD-PARTY-NOTICES.md` for provenance and license on the five that come from the
open-source Superpowers plugin.

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
*Built with Claude (Opus 4.8); Key Vault TAP delivery added with Claude (Sonnet 5)*
