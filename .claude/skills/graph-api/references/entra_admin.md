# Entra Directory Administration and Tenant Queries

## M365 Tenant Inventory (PowerShell)

**Used by:** Customer_Domain_Consolidation.

```powershell
# Organization + verified domains
Get-MgOrganization | Select-Object DisplayName, VerifiedDomains

# All users with licenses
Get-MgUser -All -Property DisplayName, UserPrincipalName, Mail, AssignedLicenses, ProxyAddresses, Department, JobTitle

# License SKU summary
Get-MgSubscribedSku | Select-Object SkuPartNumber, ConsumedUnits, PrepaidUnits

# All groups
Get-MgGroup -All -Property DisplayName, GroupTypes, SecurityEnabled, MailEnabled, Mail
```

**Permissions:** `User.Read.All`, `Directory.Read.All`, `Organization.Read.All`, `Group.Read.All`

## Entra Directory Administration

Role assignments, role-assignable groups, sign-in logs, OAuth2/app grants. Used by: `Customer_Security_Infrastructure_Audit`, `Fabrikam_Internal_Administration`.

### Role Template IDs

Built-in role templates are stable GUIDs. Catalog for roles we use:

| Role | Template ID |
|------|-------------|
| Global Administrator | `62e90394-69f5-4237-9190-012177145e10` |
| Global Reader | `f2ef992c-3afb-46b9-b7cf-a126ee74c451` |
| Privileged Role Administrator | `e8611ab8-c189-46e8-94e1-60213ab1f814` |
| User Administrator | `fe930be7-5e62-47db-91af-98c3a49a38b1` |
| Helpdesk Administrator | `729827e3-9c14-49f7-bb1b-9608f156bbb8` |
| Exchange Administrator | `29232cdf-9323-42fd-ade2-1d097af3e4de` |
| SharePoint Administrator | `f28a1f50-f6e7-4571-818b-6a12f2af6b6c` |
| Teams Administrator | `69091246-20e8-4a56-aa4d-066075b2a7a8` |
| Service Support Administrator | `f023fd81-a637-4b56-95fd-791ac0226033` |
| Directory Synchronization Accounts | `d29b2b05-8046-44ba-8758-1e26182fcf32` |

Full catalog: `GET /roleManagement/directory/roleDefinitions?$filter=isBuiltIn eq true`.

**Restricted-assignment roles** (e.g. Directory Synchronization Accounts) cannot be manually assigned — only wizard-provisioned `Sync_*` accounts receive them. Attempting POST returns an error.

### Enumerate role holders

```
GET /directoryRoles(roleTemplateId='{templateId}')/members
```

Returns thin `directoryObject` entries. To enrich (`accountEnabled`, `lastPasswordChangeDateTime`, `onPremisesSyncEnabled`, `userType`, `createdDateTime`), follow up per member:

```
GET /users/{id}?$select=id,displayName,userPrincipalName,accountEnabled,userType,onPremisesSyncEnabled,lastPasswordChangeDateTime,createdDateTime
```

### List a principal's role assignments

```
GET /roleManagement/directory/roleAssignments?$filter=principalId eq '{id}'&$expand=roleDefinition
```

For transitive role membership (via groups):

```
GET /users/{id}/transitiveMemberOf
```

### Assign / remove a role

```
POST /roleManagement/directory/roleAssignments
{
  "principalId": "<user or SP id>",
  "roleDefinitionId": "<template id or role definition id>",
  "directoryScopeId": "/"
}

DELETE /roleManagement/directory/roleAssignments/{assignmentId}
```

**Permission (app):** `RoleManagement.ReadWrite.Directory` — rarely granted; most scripts use the delegated token pattern (operator's `az` session) instead.

### Role-assignable groups

Security/M365 groups with `isAssignableToRole: true` can hold directory roles, so one group membership covers multiple roles. Constraints:

- Must be created with `isAssignableToRole = true` — cannot flip later
- Cloud-only: no AD sync, no dynamic membership
- Requires **Entra ID P1**
- Only GA / Privileged Role Administrator can manage membership

```
POST /groups
{
  "displayName": "Fabrikam-L2-Tech",
  "mailEnabled": false,
  "mailNickname": "fabrikam-l2-tech",
  "securityEnabled": true,
  "isAssignableToRole": true
}
```

Then POST role assignments with `principalId` = group id.

**Reference script:** `Fabrikam_Internal_Administration/scripts/New-FabrikamL2TechGroup.ps1`.

### Sign-in logs

```
GET /auditLogs/signIns?$filter=userId eq '{id}' and createdDateTime ge {iso}&$top=50
```

**Permission (app):** `AuditLog.Read.All`. Added to `Fabrikam-ScubaGear-Audit` 2026-04-17 — each customer tenant must re-consent to pick up the scope.

For break-glass accounts, **zero sign-ins is the goal, not a red flag** — the absence of activity is the control working.

### OAuth2 permission grants (delegated)

Grants made by a user to an app (on their behalf):

```
GET /oauth2PermissionGrants?$filter=principalId eq '{userId}'
```

Tenant-wide admin grants:

```
GET /oauth2PermissionGrants?$filter=consentType eq 'AllPrincipals'
```

### App role assignments (application permissions)

What a service principal has been granted against other resource SPs (Graph, EXO, SPO):

```
GET /servicePrincipals/{spId}/appRoleAssignments
```

Entries include `resourceId` (target SP) and `appRoleId` (role GUID on that resource). Cross-reference against the resource SP's `appRoles` collection to resolve human names.

**Reference script:** `Customer_Security_Infrastructure_Audit/scripts/remediation/Get-PrincipalScope.ps1` (handles users and SPs: roles + grants + sign-ins).

## PATCH with ETag (tenantRelationships, some admin endpoints)

Some Graph endpoints require optimistic concurrency via `If-Match`. Notable example: `tenantRelationships/delegatedAdminRelationships/{id}`. Without it, PATCH returns `428 preconditionRequired` / `entityTagMissing`. Pattern: GET first, extract `@odata.etag`, pass it as `If-Match`.

```powershell
$current = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships/$id"
Invoke-MgGraphRequest -Method PATCH `
    -Uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships/$id" `
    -Body @{ autoExtendDuration = 'P180D' } `
    -ContentType 'application/json' `
    -Headers @{ 'If-Match' = $current.'@odata.etag' }
```

Reference script: `CSP_GDAP_Enrollment/scripts/Set-GdapAutoExtend.ps1`.
