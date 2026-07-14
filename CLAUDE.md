# CLAUDE.md — Claude Code

The tool-agnostic baseline for this repo (purpose, working style, PowerShell standards, git and
attribution conventions, **Grok Build backup harness**) lives in [AGENTS.md](AGENTS.md) and is
imported here so Claude Code and other agents share one source of truth:

@AGENTS.md

Everything below is Claude-Code-specific. **Grok Build should follow AGENTS.md**.

## Claude-Code-Specific Behavior

- **Use plan mode for non-trivial tasks** — invoke `EnterPlanMode` for any task involving 3+
  steps, multiple files, or a design decision. Grok equivalent: plan mode / explicit written plan.
- **Follow the `pwsh-standards` skill** (repo `.claude/skills/pwsh-standards/` or global) whenever
  writing or reviewing PowerShell.
- **Persist before compacting** — note plan task progress so a Grok handoff can continue.

## Executing the Implementation Plan

To build the demo, execute the plan at
`docs/superpowers/plans/2026-07-07-entra-user-provisioning-demo.md` task by task, using the
`superpowers:executing-plans` skill (inline, with checkpoints) or
`superpowers:subagent-driven-development` skill (a fresh subagent per task). Grok can follow the
same plan files and skill SKILL.md bodies under `.claude/skills/`.

The plan is self-contained and assumes no prior context. Each task ends with an offline `-WhatIf`
run and a PSScriptAnalyzer lint as its acceptance check, then a commit. There is intentionally no
Pester suite — this is a demo artifact, so verification is dry-run behavior and readability.

## Handoff (Claude <-> Grok)

- Ending Claude mid-work: note which plan task is next.
- Starting Grok after Claude: read AGENTS.md + plan file; optional `/resume-claude`.
- Ending Grok: same so Claude can resume when quota returns.
