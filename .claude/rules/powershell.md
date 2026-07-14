<!--
  Mirrored into this repo so Grok Build auto-loads path-scoped rules.
  Grok scans <repo>/.claude/rules/ but not ~/.claude/rules/.
  Source of truth for Claude Code multi-machine sync: ~/.claude/rules/ (claude-config).
  When you change a rule, update both locations (or re-copy from global).
-->
---
paths:
  - "**/*.ps1"
---

# PowerShell Execution Rules

- **Always use `pwsh` (PS7), never `powershell` (PS5.1)** — PS5.1 `ConvertFrom-Json` crashes with `AccessViolationException` on large JSON inputs
- **`$PSScriptRoot` is empty when running via Bash `pwsh -File`** — always add fallback: `if (-not $PSScriptRoot) { $PSScriptRoot = $PWD.Path }`
- **Never use `pwsh -Command` for multi-line scripts** — bash mangles `\$` escaping; pwsh sees bare `\` as a command and fails. Write to a `.ps1` file and use `pwsh -File` instead.
- **Backticks inside double-quoted strings escape the next character** — including the closing paren. `"## Outcomes that move out of `New`"` parses as `## Outcomes that move out of New)` and breaks `.Add(...)` calls. Use single-quoted strings (`'...'`) when the literal string contains backticks, or escape any backtick you actually want in the output as `` `` ``.
- **Build URLs with `-f` formatter, not interpolation, when the URL contains `?`** — `"$($base)/SLA/$id`?includedetails=true"` invites two bugs: (a) PowerShell 7 sees `$id?` as a null-conditional and may consume tokens unexpectedly, (b) the bash heredoc / `pwsh -Command` boundary mangles the backtick. Prefer `'{0}/SLA/{1}?includedetails=true' -f $base, $id` — no escaping required, parses cleanly.
- **`Invoke-RestMethod` can flatten array-of-objects responses into a single PSObject with parallel-arrays-per-property** on some endpoints (each property becomes an array of values across all records, instead of one object per record). When iteration with `foreach ($item in $list) { $item.id }` returns "all ids concatenated" instead of one per record, that's the trap. Workaround: `ConvertTo-Json -Depth 30 | Out-File ...` then `Get-Content -Raw | ConvertFrom-Json` — the round-trip deserializes properly into a record array.
- **Use `python` for all invocations** — works on both Windows (`python3` is not registered) and Arch Linux (`python` symlinks to python3). Use `python script.py`, `python -m markitdown`, etc.

