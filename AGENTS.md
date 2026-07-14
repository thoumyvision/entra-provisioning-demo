# AGENTS.md — Demo Repository

Cross-agent baseline for any AI coding agent working in this repo. Tool-specific extensions layer
on top:

- **Claude Code (primary)** — see [CLAUDE.md](CLAUDE.md) (imports this file)
- **Grok Build (backup)** — same harness via Claude compatibility; follow this file plus the
  [Grok Build section](#grok-build-claude-harness-backup) below
- **Other agents** — read this file as primary; open skill `SKILL.md` files when a request matches

## Purpose

This repository is a technical demonstration. It shows a before/after:

- **Before:** `legacy/NewUsers.ps1`, a 2019 script that creates on-prem Active Directory accounts
  from a CSV.
- **After:** `src/New-EntraUsersFromCsv.ps1`, the same idea rebuilt for modern Microsoft Entra /
  Graph provisioning, produced by directing an AI with a crafted prompt (`prompt/prompt.md`) and a
  codified PowerShell standards skill.

The gap between those two files, and the process that produced it, is the point.

Read these before working in the repo:

- `docs/process-narrative.md` — how and why the design was made, decision by decision
- `docs/superpowers/specs/2026-07-07-entra-user-provisioning-demo-design.md` — the approved spec
- `docs/superpowers/plans/2026-07-07-entra-user-provisioning-demo.md` — the task-by-task plan

## Working Style

- **Lead with a recommendation,** then explain the reasoning. Do not just present options and wait.
- **Challenge a conclusion** if it looks wrong before agreeing with it.
- **Plan before non-trivial work** (3+ steps, multiple files, or a design decision).
- **Verify before marking anything done** — run it, show the output, confirm behavior matches
  intent. For this repo, verification is an offline `-WhatIf` run plus a PSScriptAnalyzer lint.

## PowerShell Standards

- **Follow the `pwsh-standards` skill** for all PowerShell in this repo.
- **Written for a human reviewer:** full cmdlet and parameter names, no aliases (`Where-Object`
  not `?`, `ForEach-Object` not `%`), splatting over backtick line-continuation, and a guiding
  comment before each logical block. A reviewer should be able to read a script top to bottom
  without running it.
- **ASCII only in scripts** — no em-dashes or smart quotes. They read as machine-generated and can
  break PowerShell 5.1 parsing when a file is saved UTF-8 without a BOM. The same applies to
  Markdown in this repo: use plain hyphens, colons, and commas.

## Git

- **Track both `.md` and `.html`** as plain-text source. Only ignore genuinely binary formats.
- **Commit messages:** a conventional prefix (`feat`, `docs`, `chore`, `fix`), an imperative
  subject line, and no em-dashes.
- **End commit messages** with a `Co-Authored-By: Claude ...` trailer and the `Claude-Session:`
  link from the current session (the harness provides both per session). Attribution is
  deliberate: this repo is transparent about AI use.

## Deliverable Attribution

Written deliverables carry a byline naming the **active agent**. Being open about AI use is part
of what this demo is arguing for.

- Claude Code → "Built with Claude (Opus 4.8)" or the current Claude model
- Grok Build → "Built with Grok [model]" (e.g. Grok Build)

Commit trailers: use the harness-provided `Co-Authored-By` / session link for the agent that
produced the commit. Do not claim Claude authorship for Grok-produced work, or the reverse.

## Path-scoped rules (`.claude/rules/`)

Repo-local mirrors so Grok Build auto-loads them:

| File | Applies when |
|------|----------------|
| `powershell.md` | `*.ps1` |
| `scripts.md` | Scripts under `scripts/` / `src/` or `*.ps1` / `*.py` |
| `cli-tools.md` | Document conversion and CLI tools |

Also follow the vendored `pwsh-standards` skill under `.claude/skills/pwsh-standards/` (and
`standards/pwsh-standards.SKILL.md` for the demo narrative).

## Grok Build (Claude harness backup)

Marcus's primary agent is Claude Code. When Claude usage is exhausted, **Grok Build is the
backup** and should reuse this harness.

### What Grok already auto-loads

| Surface | Paths |
|---------|-------|
| Project instructions | `AGENTS.md`, `CLAUDE.md` |
| Global behavior | `~/.claude/Claude.md` |
| Repo skills | `.claude/skills/*/SKILL.md` (pwsh-standards, graph-api, superpowers plan skills, …) |
| Global skills | `~/.claude/skills/*/SKILL.md` |
| Path rules | `.claude/rules/*.md` (repo mirror) |

Confirm with `grok inspect` after config changes.

### Operating rules for Grok sessions

1. **Read the design docs first** — `docs/process-narrative.md`, approved spec, and plan under
   `docs/superpowers/`.
2. **Skills first** — `pwsh-standards` for all PowerShell; plan/execute skills when implementing
   the task plan.
3. **Verify** — offline `-WhatIf` plus PSScriptAnalyzer before calling done.
4. **ASCII only** in scripts and Markdown.
5. **Handoff** — leave plan progress notes; optional `/resume-claude`.
6. **Do not duplicate into `.grok/`** — keep skills under `.claude/`.
