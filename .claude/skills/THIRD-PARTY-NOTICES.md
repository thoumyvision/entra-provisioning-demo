# Third-party notices

Skills under `.claude/skills/` in this repo come from two sources:

## Original

- `pwsh-standards/` — Marcus Whitman's own codified PowerShell standards skill. The same skill
  named in `prompt/prompt.md` ("follow my pwsh-standards skill") and vendored as a point-in-time
  exhibit at `standards/pwsh-standards.SKILL.md`.
- `graph-api/` — Marcus Whitman's own Microsoft Graph API reference skill (auth patterns,
  pagination, error handling/retry, gotchas). Not one of the skills that gated this repo's original
  build, but directly relevant: `src/New-EntraUsersFromCsv.ps1` is a Microsoft Graph script
  end to end (cert-based `Connect-MgGraph`, `New-MgUser`, group membership, Temporary Access Pass).

## Vendored from Superpowers (MIT License, Copyright (c) 2025 Jesse Vincent)

- `using-superpowers/`
- `brainstorming/`
- `writing-plans/`
- `executing-plans/`
- `subagent-driven-development/`

These five are copied verbatim, version 6.1.1, from the Superpowers plugin
(https://github.com/obra/superpowers), unmodified, so that what is in this repo matches exactly
what ran during the build. They are vendored rather than referenced by plugin install so a reader
can inspect them without installing anything.

Full license text:

```
MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
