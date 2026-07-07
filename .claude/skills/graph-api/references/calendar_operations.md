# Calendar Operations

**Used by:** Work_Schedule.

## Read Events

```
GET /users/{user_email}/calendarView?startDateTime={iso}&endDateTime={iso}
```

**Required header:** `Prefer: outlook.timezone="America/Chicago"`

**Query params:** `$select=subject,start,end,categories` to limit fields.

## Create Event

```
POST /users/{user_email}/calendar/events
```

```json
{
  "subject": "Project Work: Audit",
  "start": { "dateTime": "2026-04-02T09:00:00", "timeZone": "America/Chicago" },
  "end": { "dateTime": "2026-04-02T10:00:00", "timeZone": "America/Chicago" },
  "categories": ["Audit"],
  "showAs": "busy",
  "isReminderOn": false
}
```

**GOTCHA:** Always include `timeZone` in start/end objects. Without it, Graph assumes UTC.

## Delete Event

```
DELETE /users/{user_email}/events/{event_id}
```

**GOTCHA — Eventual consistency:** After deleting, the event may still appear in calendarView for 3-5 seconds. The Work_Schedule scripts use a verify-and-retry loop (3-5 passes, 3s settle delay) to confirm deletion.

## Manage Categories

```
POST /users/{user_email}/outlook/masterCategories
```

```json
{ "displayName": "Audit", "color": "preset4" }
```

**Permission:** `Calendars.ReadWrite` (application)

## Group Calendars

For Microsoft 365 (Unified) group calendars, the endpoint shape is `/groups/{groupId}/...` instead of `/users/{upn}/...`:

```
GET    /groups/{groupId}/calendarView?startDateTime={iso}&endDateTime={iso}
GET    /groups/{groupId}/events
POST   /groups/{groupId}/events
DELETE /groups/{groupId}/events/{eventId}
```

**GOTCHA — delegated calls require group membership.** When using a delegated token (`az` CLI token, `Connect-MgGraph` interactive), the calling user must be a member of the group, even if the token's `scp` claim includes `Group.ReadWrite.All`. Non-members get `403 ErrorAccessDenied` with no clearer signal that membership is the issue. This bites admin accounts (e.g. `admin@`) that hold the scope via GA but aren't in the group's membership; switch to a regular member account (e.g. `user@`) or add the admin as a group member temporarily.

**App-only auth** (cert-based with `Group.ReadWrite.All` application permission) bypasses the membership requirement — the SP doesn't need to be a member.

**Permission (delegated):** `Group.ReadWrite.All` *and* group membership.
**Permission (application):** `Group.ReadWrite.All` admin-consented.
