# Cortex Code Desktop (Windows) → Qlik MCP: Public Client (PKCE-only) Setup

Reference for connecting Snowflake Cortex Code Desktop (VS Code-based IDE) on Windows to the Qlik MCP server using a public OAuth client — no client secret to manage or rotate. Authorization Code flow with PKCE (S256) only.

**Tenant:** `<your-tenant>.us.qlikcloud.com`
**MCP endpoint:** `https://<your-tenant>.us.qlikcloud.com/api/ai/mcp`
**Discovery doc:** `https://<your-tenant>.us.qlikcloud.com/.well-known/oauth-authorization-server`

---
## Prerequisites

- Cortex Code Desktop installed on Windows (download from Snowflake).
- A Snowflake account connected in Cortex Code (required before MCP servers can be used).
- Tenant admin has activated Qlik MCP server for the tenant.
- Your user role has **Qlik MCP** set to **Allowed** under *Features and actions → Agentic AI*.
- If this is the first LLM client of its kind connecting, a tenant admin must perform the first connection to establish tenant-level trust.

---

## Step 1 — Create a public OAuth client in Qlik

Public clients (Native / SPA) don't hold a client secret — proof of possession is PKCE only. This avoids the confidential-client `client_secret` exchange entirely, and the `OAUTH-22 Invalid client_secret` failure mode that comes with it.

1. **Administration activity center → OAuth → Create new**
2. **Client type:** `Native` (preferred for CLI tools and desktop apps). Use `Single-page application` if `Native` isn't offered on your tenant — both are public-client types with no secret.
3. **Name:** `cortex-code-windows` (or any descriptive name)
4. **Scopes:** select
   - `user_default`
   - `mcp:execute`
   - `offline_access` (enables refresh tokens — reduces re-auth to roughly once every 30 days)
5. **Redirect URL:** add exactly one:
   ```
   http://localhost:33418/callback
   ```
   The port must match the `redirect_port` you configure in `mcp.json`. Cortex Code Desktop appends `/callback` automatically — registering just the bare `http://localhost:33418` will fail with `OAUTH-1 Invalid redirect_uri`.
6. Do **not** enable Machine-to-Machine (M2M) — that's for `client_credentials` flow, not the interactive user-auth flow Cortex Code uses.
7. Click **Create**.
8. Copy the **Client ID**. No client secret is issued for this client type — that's expected and correct.

---

## Step 2 — Configure Cortex Code Desktop's MCP settings

On Windows, Cortex Code Desktop stores its MCP configuration at:

```
%APPDATA%\Cortex Code\User\mcp.json
```

Which typically resolves to:

```
C:\Users\<username>\AppData\Roaming\Cortex Code\User\mcp.json
```

Open this file (create it if it doesn't exist) and add the `qlik` server entry:

```json
{
  "servers": {
    "qlik": {
      "type": "http",
      "url": "https://<your-tenant>.us.qlikcloud.com/api/ai/mcp",
      "oauth": {
        "client_id": "<your-public-client-id>",
        "client_name": "cortex-code-windows",
        "redirect_port": 33418,
        "scope": "user_default mcp:execute offline_access"
      }
    }
  }
}
```

Key points:
- **No `client_secret` field.** Its presence/absence determines whether Cortex Code attempts a confidential-client token exchange. Omitting it is correct for a public client.
- `redirect_port: 33418` must stay in sync with the registered redirect URL's port.
- The top-level key is `"servers"` (not `"mcpServers"` as in the CLI variant).

### Opening the file quickly

From within Cortex Code Desktop, open the Command Palette (`Ctrl+Shift+P`) and run:

```
Preferences: Open MCP Configuration
```

Or navigate directly in Explorer to `%APPDATA%\Cortex Code\User\mcp.json`.

---

## Step 3 — Clear stale OAuth state (if retrying)

If you previously attempted connection with a different client type or credentials, clear the cached OAuth tokens. On Windows, delete the cached token files:

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.snowflake\cortex\mcp_oauth\qlik*"
```

If the above path doesn't contain the tokens, check:

```powershell
Remove-Item -Recurse -Force "$env:APPDATA\Cortex Code\mcp_oauth\qlik*"
```

After clearing, restart Cortex Code Desktop (or reload the window with `Ctrl+Shift+P` → `Developer: Reload Window`).

---

## Step 4 — Verify

After saving `mcp.json` and reloading, Cortex Code Desktop will attempt to connect to the Qlik MCP server.

**Expected flow:**
1. A browser window opens to `https://<your-tenant>.us.qlikcloud.com/oauth/authorize` with `code_challenge_method=S256`.
2. Sign in and click **Approve**.
3. Browser redirects to `http://localhost:33418/callback`.
4. Cortex Code captures the authorization code and completes the PKCE token exchange — no secret involved.

**Confirm in Cortex Code Desktop:**
- Open the MCP panel via the sidebar (look for the MCP icon or use `/mcp` in chat).
- The `qlik` server should show as **Connected** with a nonzero tool count.
- Test with a real call in chat, e.g. ask the agent to list Qlik apps or search resources.

---

## Troubleshooting reference

| Symptom | Cause | Fix |
|---|---|---|
| `OAUTH-1 Invalid redirect_uri: not registered` | Registered redirect URL doesn't match what Cortex Code sends | Register `http://localhost:33418/callback` exactly (with `/callback`) |
| `OAUTH-22 Invalid client_secret` with no `client_secret` in config | Qlik client registered as confidential (Web) but config omits secret | Recreate the Qlik client as public (Native/SPA) per this doc |
| Server shows as "Disconnected" after reload | Stale cached tokens from a prior client | Clear OAuth state (Step 3) and reload |
| Browser never opens for auth | Port conflict — another process is using `33418` | Change `redirect_port` in `mcp.json` and update the registered redirect URL to match |
| Tools show `0` after connecting | User role doesn't have Qlik MCP allowed | Check *Admin → Features and actions → Agentic AI* permissions |
| `the max number of redirect URIs is 5` | Too many redirect URIs accumulated on the OAuth client | Remove unused redirect URIs in Qlik Admin, keeping only the one you need |

---

## Notes

- MCP tool calls draw from the tenant's monthly question quota (shared with Qlik Answers, if licensed). Watch consumption in *Administration → Home* if agent usage is heavy.
- The `offline_access` scope enables refresh tokens so you won't be prompted to re-authenticate on every session — only roughly every 30 days.
- If your org ships Cortex Code managed settings with an admin URL allowlist, `<your-tenant>.us.qlikcloud.com` must be on it or the server will be silently dropped after config merge.
- Unlike the CLI variant (`~/.snowflake/cortex/mcp.json` with `"mcpServers"`), Cortex Code Desktop uses `%APPDATA%\Cortex Code\User\mcp.json` with `"servers"` as the top-level key.
