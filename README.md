# Redmine / ERPmine MCP Server

A [Model Context Protocol](https://modelcontextprotocol.io) server, packaged as a
Redmine plugin, that exposes the **Redmine and ERPmine REST API as MCP tools** an
AI agent can call. Each JSON endpoint of the REST API becomes one tool, so an
agent can read issues, projects, users, time entries, versions, wiki pages — and
query ERPmine modules (time, attendance, leave, payroll, CRM, billing,
accounting, surveys) — all through the same authenticated API.

> **Read-only by default.** Only data-fetching (GET) endpoints are active. Every
> write action (create / update / delete) is present but commented out in
> `lib/redmine_mcp/catalog.rb` — both to keep the connector safe and to stay
> under the MCP client's tool-count limit. Uncomment a row to enable a write
> tool.

---

## How it works

```
AI agent (Claude, etc.)
        │  JSON-RPC 2.0 over MCP
        ▼
/mcp  (McpController, Streamable HTTP)        or     stdio bridge
        │                                                   │
        └──────────────► RedmineMcp::Server ◄───────────────┘
                                │
                       RedmineMcp::Registry  (built from Catalog)
                                │
                     RedmineMcp::RestEndpoint (one per REST URL)
                                │
                     RedmineMcp::RestClient  ── HTTP ──►  Redmine REST API
                                                          (same instance)
```

* **Tools are the REST API.** `RedmineMcp::Catalog` lists every JSON endpoint as
  a `[name, method, path, description]` row. Each row is wrapped by a
  `RestEndpoint` and surfaced as an MCP tool. When a tool is called, `RestClient`
  performs a real HTTP request to this same Redmine instance, authenticated with
  the caller's own API key — so the call obeys exactly the permissions and JSON
  serialisation of the underlying REST endpoint.
* **Transport** – JSON-RPC 2.0. Two ways to connect:
  * **HTTP** (recommended): `POST /mcp` (Streamable HTTP).
  * **stdio**: `extra/mcp_stdio_server.rb` for clients that spawn a subprocess.
* **Auth** – a Redmine **REST API key**. Over HTTP send it as
  `Authorization: Bearer <key>` (or `X-Redmine-API-Key`, or `?key=`). The
  authenticated user becomes `User.current`, and tools call the REST API with
  that user's key (`User#api_key`).

### Tool inputs

Each tool's input schema is derived from its URL:

* **Path parameters** – every `:name` segment in the path is a required string
  argument (e.g. `get_issue` requires `id`).
* **`query`** – an object merged into the URL query string: filters, pagination
  (`offset`/`limit`), `include=...`, and any identifiers an ERPmine action reads
  from params. Array values are comma-joined (e.g. `issue_id: [1,2,3]`).
* **`body`** – for write methods (POST/PUT/PATCH), an object sent as the JSON
  request body, shaped exactly as the REST API expects, e.g.
  `{"issue": {"project_id": 1, "subject": "..."}}`.

A successful call returns `{ "status": <code>, "body": <parsed JSON> }`. A non-2xx
response is surfaced as a tool error with the status and response body.

---

## Install

1. The plugin lives in `plugins/redmine_mcp`. No migrations.
2. **Enable the REST API**: *Administration → Settings → API → Enable REST web
   service*. Tools call the REST API over HTTP, so it must be on.
3. Restart Redmine. The endpoint is then served at `/mcp`.
4. Each agent connects with the API key of the user it should act as (get it from
   *My account → API access key*). Tools run with that user's permissions.

### Base URL & TLS

`RestClient` sends requests to `"#{Setting.protocol}://#{Setting.host_name}"`.
If the server process cannot reach itself at that host (containers, reverse
proxies), set an override:

```bash
REDMINE_MCP_BASE_URL=http://127.0.0.1:3000     # call the app directly
REDMINE_MCP_VERIFY_SSL=0                        # skip TLS verify (self-signed)
```

---

## Connect a client

**Claude Code** (HTTP):

```bash
claude mcp add --transport http erpmine https://your-redmine.example.com/mcp \
  --header "Authorization: Bearer YOUR_API_KEY"
```

**Claude Desktop** (`claude_desktop_config.json`, stdio):

```json
{
  "mcpServers": {
    "erpmine": {
      "command": "bash",
      "args": [
        "-lc",
        "cd /path/to/redmine && REDMINE_API_KEY=YOUR_API_KEY RAILS_ENV=production bundle exec rails runner plugins/redmine_mcp/extra/mcp_stdio_server.rb"
      ]
    }
  }
}
```

**Quick smoke test with curl:**

```bash
# List the available REST tools
curl -s https://your-redmine.example.com/mcp \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq '.result.tools | length'

# Call a tool (GET /issues.json with filters)
curl -s https://your-redmine.example.com/mcp \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call",
       "params":{"name":"list_issues","arguments":{"query":{"limit":5,"status_id":"open"}}}}' | jq
```

---

## OAuth (claude.ai web connector)

Claude Code, Claude Desktop and curl/Postman authenticate with a **Redmine API
key** (above). The **claude.ai web custom connector** is different: it requires
**OAuth** and ignores a key in the URL. This plugin provides the OAuth layer on
top of Redmine's built-in OAuth2 provider (Doorkeeper), so the web connector can
connect without any per-user OAuth app setup.

**Prerequisites**

1. *Administration → Settings → API → Enable REST web service* (already required).
2. **Set the public URL.** *Administration → Settings → General → Host name and
   path* must be the exact host the connector reaches (e.g.
   `your-redmine.example.com`), and *Protocol* = HTTPS. The OAuth discovery
   documents advertise authorize/token URLs from this — if it's wrong, the
   browser login step can't be reached. Alternatively set
   `REDMINE_MCP_BASE_URL=https://your-host` in the server environment.

**How it works** — when the connector hits `/mcp` unauthenticated, it gets a
`401` whose `WWW-Authenticate` header points to:

```
GET  /.well-known/oauth-protected-resource     → resource + authorization server
GET  /.well-known/oauth-authorization-server    → Doorkeeper authorize/token URLs
POST /oauth/mcp_register                         → dynamic client registration
```

The connector registers a client automatically (RFC 7591), then runs the
Authorization Code + PKCE flow against Redmine's `/oauth/authorize` and
`/oauth/token`. The user logs into Redmine and approves; the resulting bearer
token is accepted at `/mcp` (validated via Doorkeeper, mapped to that user).
Just add the connector with the base URL `https://your-redmine.example.com/mcp`
(no `?key=` needed) and click **Connect**.

**Manual client (fallback).** If automatic registration is blocked, create an
OAuth application yourself at *Administration → OAuth applications* (redirect URI
= the connector's callback, e.g. `https://claude.ai/api/mcp/auth_callback`) and
paste its **Client ID** into the connector's "OAuth Client ID" field.

> Verify discovery once deployed:
> ```bash
> curl -s https://your-redmine.example.com/.well-known/oauth-authorization-server | jq
> ```

---

## Tools

Tools mirror the REST API. Names follow a predictable scheme:

| Group | Examples (active) |
|-------|----------|
| **Issues** | `list_issues`, `get_issue`, `list_issue_relations`, `get_issue_relation` |
| **Writes** | `create_issue`, `update_issue`, `create_time_entry`, `update_time_entry` |
| **Projects** | `list_projects`, `get_project`, `list_project_memberships`, `get_membership` |
| **Users / groups / roles** | `list_users`, `get_user`, `get_current_user`, `list_groups`, `get_group`, `list_roles` |
| **Time entries** | `list_time_entries`, `get_time_entry` |
| **Project files** | `list_files` |
| **Metadata** | `list_trackers`, `list_issue_statuses`, `list_issue_priorities`, `list_custom_fields`, `search` |
| **ERPmine** (`<controller>_<action>`) | `wktime_index`, `wkattendance_clockindex`, `wkleaverequest_index`, `wkpayroll_index`, `wklead_index`, `wkinvoice_index`, … |

Read tools across all modules plus create/update writes for issues and time
entries are active. Run `tools/list` for the full set with per-tool descriptions
and input schemas. The exact list is defined in `lib/redmine_mcp/catalog.rb`.

> Redmine REST tools return clean JSON. Write tools (and ERPmine actions) read
> identifiers from `query` and the JSON payload from `body` (e.g.
> `{"issue": {"subject": "..."}}`); consult the action's controller for the
> exact parameter shape.

---

## Adding (or removing) a tool

There are no per-tool classes. Add a row to the relevant list in
`lib/redmine_mcp/catalog.rb`:

```ruby
# [name, http_method, path_template, description]
['get_issue', :get, '/issues/:id.json', 'Get one issue. query include=journals,...'],
```

* `:param` segments in the path become required string arguments.
* `:get`/`:delete` get a `query` argument; `:post`/`:put`/`:patch` also get a
  `body` argument.

It then appears in `tools/list` and is callable — no other change needed.
Removing a tool is just deleting its row.
