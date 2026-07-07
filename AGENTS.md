# AGENTS.md — Demo Repository

Cross-agent baseline for any AI coding agent working in this repo. Tool-specific extensions live
in [CLAUDE.md](CLAUDE.md), which imports this file so the substance stays in one place.

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

Written deliverables in this repo carry a "Built with Claude (Opus 4.8)" byline. Being open about
AI use is part of what this demo is arguing for.
