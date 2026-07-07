# Design: Entra User-Provisioning Demo

**Date:** 2026-07-07
**Author:** Marcus Whitman (with Claude Opus 4.8)
**Repo:** `C:\Projects\Demo` → `thoumyvision/Demo` (private)
**Purpose:** A screenshare demo for the employer 2nd interview (Enterprise Applications Automation Engineer) that turns "skeptical of AI use" into a strength by showing that AI output quality is a function of the engineer directing it.

---

## 1. The narrative this demo must land

The hiring manager was skeptical of AI. The demo's job is to reframe that skepticism, not argue with it. The chain of evidence:

1. **`legacy/NewUsers.ps1`** — a real script Marcus wrote in 2019. Naive, but honest.
2. **`prompt/prompt.md`** — a deliberately crafted prompt. The judgment is front-loaded here by the human.
3. **`standards/pwsh-standards.SKILL.md`** — Marcus's codified engineering standards. Proof the quality is *his*, made repeatable.
4. **`src/New-EntraUsersFromCsv.ps1`** — the result: modern, cloud-first, config-driven, readable.

The message: *"I'm not outsourcing judgment to the AI. I codified what good looks like, I front-load the architecture into the prompt, and the AI scales my standards consistently. And I can spot when it's wrong."*

Secondary win: the pivot from on-prem `New-ADUser` to Graph `New-MgUser` is a **modernization story** that maps directly onto the employer stack (Graph, Entra, M365, licensing) and onto Marcus's two strongest technical-screen answers (Microsoft Graph, cert-based auth). It also quietly closes his two screen gaps by demonstrating adjacent competence.

---

## 2. Repository layout

```
Demo/
  README.md                          # the demo run-sheet: narration + old-vs-new table
  legacy/
    NewUsers.ps1                      # verbatim 2019 original (the "before")
  src/
    New-EntraUsersFromCsv.ps1         # the professional version (the "after")
    department-map.psd1               # config: department -> M365 group + license SKU
  data/
    new-hires.csv                     # fake test data, includes Department column
  standards/
    pwsh-standards.SKILL.md           # copy of the updated skill (the "why it's good")
  prompt/
    prompt.md                         # the crafted prompt that produced src/
  docs/superpowers/specs/
    2026-07-07-entra-user-provisioning-demo-design.md   # this document
  .gitignore
```

---

## 3. The "after" script — `src/New-EntraUsersFromCsv.ps1`

### 3.1 Behavior, mapped to each weakness in the original

| Legacy weakness (`NewUsers.ps1`) | New behavior |
|---|---|
| `New-ADUser` (on-prem only) | `New-MgUser` via Microsoft Graph |
| Hardcoded plaintext `"Summer2019!"` | **No password is set at all.** A one-time Temporary Access Pass (TAP) is issued per user (see 3.6); nothing secret is created, known, or logged |
| No collision handling | Checks `Get-MgUser` for the candidate UPN first; on collision derives `jdoe2`, `jdoe3`, … |
| One bad CSV row kills the whole loop | Per-row `try/catch`; failures collected into a results object and reported at the end; the run continues |
| `substring(0,1)` crashes on blank first name | Each row's required fields validated before an identity is built; invalid rows are skipped with a clear reason |
| Hardcoded path, domain, OU | `[CmdletBinding(SupportsShouldProcess = $true)]` with `-CsvPath`, `-MapPath`, `-TenantId`, `-ClientId`, `-CertificateThumbprint` parameters |
| Six near-identical hand-edited copies | One script + one `department-map.psd1` config file |
| No department logic | Department drives M365 **group membership**; license flows via **group-based licensing** |
| Ran blind against production | Full `-WhatIf` support that prints the intended plan and changes nothing |

### 3.2 Authentication

Cert-based app-only against Microsoft Graph — Marcus's strongest technical-screen answer, expressed in code:

```powershell
Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint
```

Least-privilege scopes documented in comment-based help as the app-registration permissions the script assumes: `User.ReadWrite.All`, `Group.ReadWrite.All`, and `UserAuthenticationMethod.ReadWrite.All` (for issuing the Temporary Access Pass, see 3.6).

### 3.3 Execution model — offline `-WhatIf` (confirmed)

- **`-WhatIf` runs fully offline.** It does **not** call `Connect-MgGraph` and needs no tenant. It reads the CSV and `department-map.psd1`, resolves each planned action, and prints lines like:
  `WOULD create user jdoe@contoso.com -> add to group "Attorneys-Users" -> license SPE_E5 flows via group-based licensing -> issue one-time Temporary Access Pass (valid 60 min)`.
- **A real run** (no `-WhatIf`) connects cert-based and performs the mutations, each wrapped in `$PSCmdlet.ShouldProcess(...)`.
- Consequence: the demo runs on **any** machine, needs **zero** tenant setup, and carries **zero** risk of creating stray users. This is itself a senior-engineer signal (a safe dry-run built before touching production identity).

### 3.4 Group-based licensing (the architectural talking point)

The script assigns the user to the department's M365 group and relies on **group-based licensing** to flow the SKU. It does **not** assign licenses per user by default. A commented-out `Set-MgUserLicense` block shows the explicit per-user alternative and a one-line note on why group-based licensing is preferred (single source of truth, deprovisioning by group removal, no per-user drift). This demonstrates "I know what good looks like," not just "I can call the API."

### 3.5 Readability (written for a human reviewer)

The script is generated under the human-readability standard (see section 5). Concretely:
- No aliases — full cmdlet names throughout (`Where-Object`, `ForEach-Object`, `Get-ChildItem`, `Select-Object`).
- Full parameter names, no positional arguments.
- Splatting for multi-parameter calls rather than backtick line-continuation.
- A guiding comment before each logical block, narrating intent so a reviewer can follow the flow without executing it.

### 3.6 First-time credential — Temporary Access Pass (no password)

The script never sets a password. After the user and group membership are created, it issues a one-time **Temporary Access Pass** via Graph:

```powershell
New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $upn -BodyParameter @{
    isUsableOnce      = $true
    lifetimeInMinutes = 60
}
```

- The TAP is time-limited and single-use, so the new hire signs in once and is forced to register their own strong auth (MFA / passwordless). No shared or known password ever exists.
- The TAP value is returned exactly once at creation and must reach the user **out-of-band** (typical: relayed by the hiring manager or IT). The script surfaces it to the operator for that handoff; it is never written to the log.
- Requires the **Temporary Access Pass** authentication-method policy to be enabled in the tenant and the user in scope — noted in the script's comment-based help as a prerequisite.
- A commented-out fallback block shows the "random password, forced change at first sign-in, relayed out-of-band" approach for tenants where TAP is not enabled — present to show the tradeoff, not as the default.
- In offline `-WhatIf` mode the script issues nothing; it prints `WOULD issue a one-time Temporary Access Pass for <upn> (valid 60 min)`.

---

## 4. Fake data and department map

### 4.1 `data/new-hires.csv`

Columns: `First,Last,Department,JobTitle`. ~8–10 fake rows across the legal-firm departments below, deliberately including at least one **name collision** (two people who resolve to the same username) and one **blank/invalid row** so the collision-handling and per-row error-handling are visibly exercised in the `-WhatIf` output.

### 4.2 `src/department-map.psd1`

Legal-firm flavored (confirmed) — a deliberate "I tailored this to your world" touch. Fake group names, **real** SKU part numbers:

| Department | M365 group | License SKU |
|---|---|---|
| Attorney | `Attorneys-Users` | `SPE_E5` (Microsoft 365 E5) |
| Paralegal | `Legal-Support-Users` | `SPE_E3` |
| Legal Support | `Legal-Support-Users` | `SPE_E3` |
| IT | `IT-Staff` | `SPE_E5` |
| Finance | `Finance-Users` | `SPE_E3` |
| Marketing | `Marketing-Users` | `SPE_E3` |
| HR | `HR-Users` | `SPE_E3` |

An unmapped department is a per-row error (reported, row skipped), not a silent pass.

---

## 5. pwsh-standards skill update

Update the real skill at `~/.claude/skills/pwsh-standards/` (SKILL.md and/or `references/patterns.md`), then copy the updated `SKILL.md` into `Demo/standards/pwsh-standards.SKILL.md` as the shown artifact. The skill improvement outlives the interview.

Five additions, each of which the demo script then visibly honors:

1. **Microsoft Graph authentication** — cert-based app-only `Connect-MgGraph`, least-privilege scopes, `Microsoft.Graph` module hygiene (use `Microsoft.Graph.Authentication` + the specific sub-modules, not the whole meta-module).
2. **`ShouldProcess` usage** — how to actually wrap a mutation in `if ($PSCmdlet.ShouldProcess($target, $action))`, so `-WhatIf`/`-Confirm` work. (The template already declares `SupportsShouldProcess`; this shows using it.)
3. **Config-driven / mapping-table pattern** — externalize environment-specific data (like department → group → license) into a `.psd1`/JSON config instead of hardcoding, so one script replaces many copies.
4. **Idempotency / existence checks** — check before create (`Get-MgUser` before `New-MgUser`), derive non-colliding identities, make reruns safe.
5. **Written for a human reviewer** — no aliases, full parameter names, splatting over line-continuation, block-level guiding comments. Reconciles with the existing "explain why not what" guidance by commenting at the *block* level (intent of each step) while still avoiding line-noise comments.

---

## 6. `prompt/prompt.md`

The crafted prompt that produces `src/`. It demonstrates *how Marcus directs*, and is the thing the interviewer sees to understand that judgment is front-loaded by the human. It will:
- State the goal and point at `legacy/NewUsers.ps1` as the artifact to modernize.
- Name the constraints explicitly: Graph not AD, cert-based app-only auth, config-driven via `department-map.psd1`, group-based licensing, idempotent/collision-safe, full `-WhatIf`, and **written for a human reviewer**.
- Explicitly instruct: "follow my pwsh-standards skill."

---

## 7. Hybrid live segment (the "C" choice)

Everything above is **pre-built** and committed — the guaranteed artifact.

The single live action on the call: with the finished script open, Marcus prompts Claude to make one small, safe, additive change — e.g. "also set each user's `OfficeLocation` from a new CSV column." The interviewer watches a real change land cleanly under Marcus's direction. It is contained enough that it cannot derail the interview, and the already-finished script is the fallback if the room's connectivity or time doesn't allow it.

---

## 8. README.md (the run-sheet)

`README.md` doubles as Marcus's demo run-sheet and the repo's front door:
- One-paragraph framing of the before/after.
- The old-vs-new weakness table (section 3.1).
- A short "how the pieces relate" list (legacy → prompt → standards → result).
- The exact `-WhatIf` command to run live, and the expected output shape.
- Talking points: group-based licensing, cert-based auth, Temporary Access Pass (no password ever set), "written for a human reviewer," one-config-replaces-six.

---

## 9. Out of scope (YAGNI)

- No real tenant integration, no live user creation (offline `-WhatIf` only).
- No Pester tests (this is a demo artifact, not a maintained product; readability and correctness of the dry-run are what's demonstrated).
- No CI/CD, no module packaging.
- No deprovisioning/offboarding counterpart (the onboarding story is enough to make the point).
- No `.docx`/HTML rendering — the artifacts are the code and Markdown themselves.
