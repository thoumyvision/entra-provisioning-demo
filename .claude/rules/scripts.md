<!--
  Mirrored into this repo so Grok Build auto-loads path-scoped rules.
  Grok scans <repo>/.claude/rules/ but not ~/.claude/rules/.
  Source of truth for Claude Code multi-machine sync: ~/.claude/rules/ (claude-config).
  When you change a rule, update both locations (or re-copy from global).
-->
---
paths:
  - "**/scripts/**"
  - "**/*.ps1"
  - "**/*.py"
---

# Script File Management

**Always save scripts to the project's `scripts/` folder, not to temporary or throwaway locations (`%TEMP%`, `/tmp/`, etc.).**

- Scripts written to temp directories are lost between sessions and must be regenerated, wasting time and tokens
- Each project folder has a `scripts/` subfolder — use it
- For multi-client projects, use `scripts/<ClientName>/` subfolders for client-specific scripts
- Reusable/general scripts go directly in `scripts/`
- Name scripts descriptively: `dns_email_audit.ps1`, `itglue_upload.ps1`, `ninja_network_collect.ps1`
- Add a header comment to every script: purpose, usage, prerequisites, creation date

