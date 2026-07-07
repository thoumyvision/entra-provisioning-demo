---
name: graph-api
description: Microsoft Graph API reference for this repo's integrations — cert-based and delegated auth patterns, SharePoint search, file downloads, calendar operations, M365 tenant queries, and Entra directory administration (role assignments, role-assignable groups, sign-in logs, OAuth2 grants, app role assignments, service-principal audits). Use this skill whenever writing or modifying scripts that call Graph endpoints, auditing customer tenants via GDAP, enumerating or removing directory roles, building role-assignable groups, checking sign-in logs, investigating OAuth consent or app-permission grants, looking up role template IDs, or working with `Connect-MgGraph` / `az rest` / `Invoke-MgGraphRequest` — even when the user doesn't explicitly say "Graph API."
---

# Microsoft Graph API Reference

Covers the Graph API patterns used across this repo. For endpoint-specific details, also check the project's own SESSION_CONTEXT.md. Topic detail lives in `references/`; this file holds the auth decision guidance, cross-cutting request patterns, and the gotchas list.

## Topic Index

| Topic | Reference file |
|-------|----------------|
| Auth setup detail: cert-based Python (MSAL), cert-based PowerShell (`Connect-MgGraph` app-only), delegated `az` token for GDAP writes, interactive browser; Key Vault secret names; per-project permissions summary | [references/auth_patterns.md](references/auth_patterns.md) |
| SharePoint search (`POST /search/query`, KQL syntax, pagination, response shape) and file downloads (`/shares/{token}/driveItem/content`, sharing-token encoding) | [references/sharepoint_files.md](references/sharepoint_files.md) |
| Calendar operations: read/create/delete events, master categories, group calendars and their membership requirement | [references/calendar_operations.md](references/calendar_operations.md) |
| M365 tenant inventory cmdlets, Entra directory administration (role template IDs, role holders, assign/remove roles, role-assignable groups, sign-in logs, OAuth2 grants, app role assignments), PATCH with ETag on `tenantRelationships` | [references/entra_admin.md](references/entra_admin.md) |

## Base URL

```
https://graph.microsoft.com/v1.0
```

## Choosing an Auth Pattern

Pick by task; full setup detail for each is in [references/auth_patterns.md](references/auth_patterns.md).

| Situation | Pattern |
|-----------|---------|
| Python scripts against the Fabrikam tenant (SharePoint search, calendar, downloads) | Certificate-based MSAL (Python). Primary pattern; used by Work_Schedule, SharePoint_Customer_Search, audit scripts |
| Read-only audits of customer tenants | Certificate-based `Connect-MgGraph` app-only with the `Fabrikam-ScubaGear-Audit` app (admin-consented per tenant) |
| Write operations in a customer tenant (role removal, membership changes) | Delegated token from the operator's `az login` session via GDAP. Needs a GDAP role covering the operation; role management needs Privileged Role Administrator |
| One-off interactive tenant queries | `Connect-MgGraph -Scopes ...` interactive browser flow (PS 7+, `Microsoft.Graph.Authentication` module) |

### When to use `Connect-MgGraph` vs `az rest`

Prefer `az rest` for Graph calls only when the required scope is on this list:
`Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`, `AuditLog.Read.All`, `DelegatedPermissionGrant.ReadWrite.All`, `Directory.AccessAsUser.All`, `Group.ReadWrite.All`, `User.ReadWrite.All` (check with `az account get-access-token --resource https://graph.microsoft.com | jq -R 'split(".")[1] | @base64d | fromjson | .scp'`).

**The az CLI client does NOT carry partner/admin scopes** like `DelegatedAdminRelationship.*`, `Partner.ReadWrite.All`, `DeviceManagement*`, etc. For those, use `Connect-MgGraph -Scopes ...` — `az rest` will silently return empty arrays rather than error, so this is easy to miss.

## Pagination

Graph API uses `@odata.nextLink` for continuation:

```python
results = []
url = "https://graph.microsoft.com/v1.0/users"
while url:
    resp = requests.get(url, headers=headers)
    data = resp.json()
    results.extend(data.get("value", []))
    url = data.get("@odata.nextLink")
```

For search endpoint: use `from`/`size` params instead (no nextLink).

PowerShell equivalent:

```powershell
function Invoke-GraphPaged {
    param([string]$Uri, [hashtable]$Headers)
    $all = @(); $next = $Uri
    while ($next) {
        $r = Invoke-RestMethod -Method GET -Uri $next -Headers $Headers
        if ($r.value) { $all += $r.value }
        $next = $r.'@odata.nextLink'
    }
    ,$all
}
```

## Advanced Query Parameters

Some filters and operators require the `ConsistencyLevel: eventual` header plus `$count=true`:

- `$search` on any collection
- `$count=true`
- `$filter` with `endsWith`, `not`, `ne`, `in`, or `contains()` on some collections

Without the header, the query returns 400 or a misleading empty result. Affected endpoints: `users`, `groups`, `applications`, `servicePrincipals`, `devices`, `organizationalContacts`, `directoryObjects`.

```powershell
$headers = @{
    Authorization      = "Bearer $token"
    'ConsistencyLevel' = 'eventual'
}
Invoke-RestMethod -Headers $headers `
    -Uri "https://graph.microsoft.com/v1.0/users?`$count=true&`$search=`"displayName:admin`""
```

When in doubt, prefer `startswith()` — it works without advanced query headers.

## Error Handling & Retry

| Status | Meaning | Action |
|--------|---------|--------|
| 401 | Token expired or bad auth | Re-acquire token, do not retry |
| 403 | Missing permissions | Check app registration scopes |
| 404 | Resource not found | Check endpoint/ID |
| 429 | Throttled | Retry after `Retry-After` header value |
| 5xx | Server error | Exponential backoff (max 3 retries, cap 60s) |

Standard retry pattern used across repo:

```python
import time

def graph_request(method, url, headers, max_retries=3, **kwargs):
    for attempt in range(max_retries):
        resp = requests.request(method, url, headers=headers, **kwargs)
        if resp.status_code == 429:
            wait = int(resp.headers.get("Retry-After", 2 ** attempt))
            time.sleep(wait)
            continue
        if resp.status_code >= 500:
            time.sleep(2 ** attempt)
            continue
        resp.raise_for_status()
        return resp.json()
    raise Exception(f"Graph API failed after {max_retries} retries")
```

## Gotchas Summary

1. **Always specify timezone** in calendar start/end objects — Graph defaults to UTC
2. **Eventual consistency** — calendar deletes take 3-5s to propagate; use verify loops
3. **SharePoint search indexing lag** — new files may not appear for 15-60 minutes
4. **Sharing token encoding** — must use `base64.urlsafe_b64encode` with `u!` prefix and strip trailing `=`
5. **KQL quoted strings** — wrap customer names in quotes for exact match
6. **Teams calendar lag** — Teams shows deleted events longer than Outlook
7. **`Prefer` header required** for calendarView timezone — without it you get UTC times
8. **Certificate PEM format** — must include private key, not just the public cert
9. **`az rest` silently returns `[]` for unscoped queries** — admin/partner endpoints (e.g. `DelegatedAdminRelationship.*`) need `Connect-MgGraph` with explicit `-Scopes`; az CLI's pre-consented scope list is limited
10. **ETag/If-Match required** on `delegatedAdminRelationships` PATCH (and possibly other partner endpoints) — GET first, pass `@odata.etag` as `If-Match` header
11. **`az rest` stderr contamination** — az emits warnings on stderr that poison JSON when merged via `2>&1`. Use `2>$null` for normal runs; re-run with `2>&1` only on non-zero exit for diagnostics
12. **`pwsh -File` doesn't deserialize array args from bash** — a comma-separated value becomes one string. Use `pwsh -Command "& './script.ps1' -Param 'a','b'"` instead
13. **`contains()` unsupported** on `servicePrincipals` filter without advanced query headers — prefer `startswith()` which works without them
14. **Restricted-assignment roles can't be assigned manually** — e.g. Directory Synchronization Accounts (`d29b2b05-...`) is reserved for wizard-provisioned `Sync_*` accounts; POST returns an error
15. **`/directoryRoles/.../members` returns thin objects** — only `id` and `displayName`. Follow up per member with `/users/{id}?$select=...` to get `accountEnabled`, `onPremisesSyncEnabled`, `lastPasswordChangeDateTime`, `createdDateTime`
16. **Role management via `az rest` requires delegated PRA** — app-only Graph token lacks role scopes; the user behind `az login` needs Privileged Role Administrator in the customer tenant (not Exchange Admin / Global Reader), typically via GDAP `Lighthouse-Escalation`
17. **Delegated group-calendar calls require group membership** — `/groups/{id}/calendar/...`, `/groups/{id}/events`, `/groups/{id}/calendarView` return `403 ErrorAccessDenied` if the calling user isn't a member of the group, even with `Group.ReadWrite.All` on the token. Admin accounts (admin@, GA accounts) typically aren't in business-function groups; use a regular member account or app-only auth.
