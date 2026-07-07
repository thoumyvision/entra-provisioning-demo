# SharePoint Search and File Downloads

## SharePoint Search (KQL)

**Used by:** SharePoint_Customer_Search, contract-analysis skill.

```
POST /search/query
```

```json
{
  "requests": [{
    "entityTypes": ["driveItem"],
    "query": { "queryString": "contoso AND filetype:pdf" },
    "from": 0,
    "size": 200,
    "region": "US"
  }]
}
```

**KQL query syntax:**
- Customer name: `"Contoso"` (quoted for exact match)
- File type: `filetype:pdf`, `filetype:docx`
- Date range: `LastModifiedTime>=2025-01-01`
- Path scope: `path:"https://fabrikamtech.sharepoint.com/sites/Sales"`
- Combine: `"Contoso" AND filetype:pdf AND LastModifiedTime>=2025-01-01`

**Pagination:** Use `from` and `size` (max 500 per request). Loop until results < size.

**Response normalization:** Results are in `value[0].hitsContainers[0].hits[]`, each with `resource` containing `name`, `webUrl`, `size`, `lastModifiedDateTime`.

**Permission:** `Sites.Read.All` (application)

## File Downloads (SharePoint)

**Used by:** SharePoint_Customer_Search, contract download scripts.

```
GET /shares/{sharing_token}/driveItem/content
```

**Sharing token encoding:**
```python
import base64
encoded = base64.urlsafe_b64encode(web_url.encode()).decode().rstrip("=")
sharing_token = f"u!{encoded}"
```

**Response:** Returns `@microsoft.graph.downloadUrl` — follow that URL to get binary content. Some responses redirect directly (302).

**Permission:** `Files.Read.All` (application)
