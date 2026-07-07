# Authentication Patterns

Full setup detail for each Graph auth flow used in this repo. The decision guidance for which pattern to pick lives in SKILL.md.

## Certificate-Based (Python — primary pattern)

Used by: Work_Schedule, SharePoint_Customer_Search, customer audit scripts.

```python
import msal

authority = f"https://login.microsoftonline.com/{tenant_id}"
app = msal.ConfidentialClientApplication(
    client_id=client_id,
    authority=authority,
    client_credential={
        "thumbprint": cert_thumbprint,
        "private_key": pem_content,  # Full PEM with private key
    },
)
result = app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
access_token = result["access_token"]
```

**Azure Key Vault secrets:**
- `graph-tenant-id`
- `graph-client-id`
- `graph-cert-thumbprint`

**Certificate:** PEM file with private key, path configured in project's `config/config.json`.

## Certificate-Based (PowerShell — app-only against customer tenants)

Used by: `Customer_Security_Infrastructure_Audit` cert-based multi-tenant audit scripts.

```powershell
Connect-MgGraph `
    -ClientId $appId `
    -TenantId $customerTenantId `
    -CertificateThumbprint $thumbprint `
    -NoWelcome
```

**Prereq:** cert installed in `Cert:\LocalMachine\My` with matching thumbprint. The `Fabrikam-ScubaGear-Audit` app (`11111111-2222-3333-4444-555555555555`) must be admin-consented in each customer tenant — run `scripts/scubagear/Grant-AdminConsentUrls.ps1` when scopes change.

**Key Vault secrets (vault `fabrikam-scripts-secrets`):**
- `scubagear-audit-client-id`
- `scubagear-audit-cert-thumbprint`
- `scubagear-audit-cert-password` (for initial install only)

For endpoints not covered by `Get-Mg*` cmdlets, use `Invoke-MgGraphRequest` — it reuses the same token.

## Delegated Graph Token via az CLI (PowerShell — for write ops in customer tenants)

The cert-based audit app is read-only. For write operations (role removal, membership changes) in a customer tenant, use the operator's `az login` session with GDAP delegation:

```powershell
$token = az account get-access-token `
    --tenant $CustomerTenantId `
    --resource https://graph.microsoft.com `
    --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
Invoke-RestMethod -Method DELETE `
    -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$id" `
    -Headers $headers
```

**Requires:** GDAP role in the customer tenant that covers the operation. Role management (assign/remove directory roles) requires **Privileged Role Administrator** — Exchange Admin and Global Reader are insufficient and return 403. The `Lighthouse-ServiceDesk` mapping typically doesn't include PRA; use `Lighthouse-Escalation` or assign in the portal per operator.

**Reference script:** `Customer_Security_Infrastructure_Audit/scripts/remediation/Remove-DirectoryRoleFromPrincipal.ps1`.

## Interactive Browser (PowerShell — for one-off tenant queries)

Used by: Customer_Domain_Consolidation, CSP_GDAP_Enrollment.

```powershell
Connect-MgGraph -Scopes @("User.Read.All", "Directory.Read.All", "Organization.Read.All", "Group.Read.All") -NoWelcome
# ... then use Invoke-MgGraphRequest for arbitrary endpoints
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me'
```

Requires: `Microsoft.Graph.Authentication` module (PS 7+).

**Token-based, not session-based** (unlike the deprecated `Connect-MsolService`): `Connect-MgGraph` acquires an OAuth access+refresh token via MSAL and caches it on disk. Subsequent calls in the same process reuse the token silently; across processes the MSAL cache skips re-prompting while the refresh token is valid. Adding a new scope requires a fresh `Connect-MgGraph` — scopes are fixed at connect time.

## Permissions Summary

| Project | Permissions | Auth Type |
|---------|------------|-----------|
| SharePoint search | `Sites.Read.All`, `Files.Read.All` | Certificate |
| Calendar (Work Schedule) | `Calendars.ReadWrite` | Certificate |
| Contract downloads | `Sites.Read.All`, `Files.Read.All` | Certificate |
| Tenant inventory | `User.Read.All`, `Directory.Read.All`, `Organization.Read.All`, `Group.Read.All` | Interactive |
| Entra audit (roles, grants, sign-ins) | `Directory.Read.All`, `AuditLog.Read.All`, `RoleManagement.Read.Directory` | Certificate (Fabrikam-ScubaGear-Audit) |
| Entra write (role assign/remove) | (delegated) `RoleManagement.ReadWrite.Directory` via GDAP + PRA | Delegated token from `az` session |

All application permissions require **admin consent** in the Azure AD app registration.
