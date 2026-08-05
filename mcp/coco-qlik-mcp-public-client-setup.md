# CoCo → Qlik MCP: Public Client (PKCE-only) Setup

Reference for connecting Snowflake CoCo (Cortex Code CLI) to the Qlik MCP server using a public OAuth client — no client secret to manage or rotate. Authorization Code flow with PKCE (S256) only.

**Tenant:** `<your-tenant>.us.qlikcloud.com`
**MCP endpoint:** `https://<your-tenant>.us.qlikcloud.com/api/ai/mcp`
**Discovery doc:** `https://<your-tenant>.us.qlikcloud.com/.well-known/oauth-authorization-server`

---
## Prerequisites

- Tenant admin has activated Qlik MCP server for the tenant.
- Your user role has **Qlik MCP** set to **Allowed** under *Features and actions → Agentic AI*.
- If this is the first LLM client of its kind connecting, a tenant admin must perform the first connection to establish tenant-level trust.

---

## Step 2 — Create a public OAuth client in Qlik

Public clients (Native / SPA) don't hold a client secret — proof of possession is PKCE only. This avoids the confidential-client `client_secret` exchange entirely, and the `OAUTH-22 Invalid client_secret` failure mode that comes with it.

1. **Administration activity center → OAuth → Create new**
2. **Client type:** `Native` (preferred for CLI tools). Use `Single-page application` if `Native` isn't offered on your tenant — both are public-client types with no secret.
3. **Name:** `cortex-code-qlik`
4. **Scopes:** select
   - `user_default`
   - `mcp:execute`
   - `offline_access` (enables refresh tokens — reduces re-auth to roughly once every 30 days)
5. **Redirect URL:** add exactly one:
   ```
   http://localhost:8585/callback
   ```
   This must match **exactly** what CoCo sends — confirmed from CoCo's logs (`~/.snowflake/cortex/logs/coco.log`), where the authorize request includes `redirect_uri=http%3A%2F%2Flocalhost%3A8585%2Fcallback`. CoCo appends `/callback` to the configured `redirect_port` automatically; the bare `http://localhost:8585` is **not** sufficient and will fail with `OAUTH-1 Invalid redirect_uri`.
6. Do **not** enable Machine-to-Machine (M2M) — that's for `client_credentials` flow, not the interactive user-auth flow CoCo uses.
7. Click **Create**.
8. Copy the **Client ID**. No client secret is issued for this client type — that's expected and correct.

If a prior confidential (`Web`) client of the same name exists (e.g. `cortex-code-qlik` created earlier with a secret), delete it or rename it to avoid confusion — don't leave two clients with overlapping names/purposes on the tenant.

---

## Step 3 — Update CoCo's MCP config

Edit `~/.snowflake/cortex/mcp.json`:

```json
{
  "mcpServers": {
    "qlik": {
      "type": "http",
      "url": "https://<your-tenant>.us.qlikcloud.com/api/ai/mcp",
      "oauth": {
        "client_id": "<new-public-client-id>",
        "client_name": "cortex-code-qlik",
        "redirect_port": 8585,
        "scope": "user_default mcp:execute offline_access"
      }
    }
  }
}
```

Key points:
- **No `client_secret` field.** Its presence/absence is what determines whether CoCo attempts a confidential-client token exchange. Omitting it is correct for a public client.
- `redirect_port: 8585` must stay in sync with the registered redirect URL's port.

Clear any stale OAuth state from prior attempts (confidential client, DCR, or earlier failed auths) before retrying:

```bash
rm -rf ~/.snowflake/cortex/mcp_oauth/qlik*
```

---

## Verify

```bash
cortex mcp start
```

Expected: browser opens to `https://<your-tenant>.us.qlikcloud.com/oauth/authorize` with `code_challenge_method=S256`. Sign in, click **Approve**. Browser redirects to `http://localhost:8585/callback`, CoCo captures the code and completes the PKCE exchange at `/oauth/token` — no secret involved, so `OAUTH-22` cannot recur via this path.

Confirm:

```bash
cortex mcp list
cortex mcp get qlik
```

`cortex mcp get qlik` should show:
- `Status: Connected`
- `Client ID:` matching the new public client
- `Tools: Valid: <nonzero>`
- No `client_secret` reference anywhere in output

Inside a CoCo session:

```
/mcp
```

should show `qlik` as `connected` with its tool count. Test with a real call, e.g. `mcp__qlik__list_apps`.

---

## Troubleshooting reference

| Symptom | Cause | Fix |
|---|---|---|
| `Unknown argument: qlik` on `cortex mcp start qlik` | `start` takes no server-name argument | Run `cortex mcp start` (no args) |
| `the max number of redirect URIs is 5` | DCR re-registering a new client (or accumulating redirect URIs) on repeated `add`/`start` cycles | Abandon DCR; use a manually pinned `client_id` as above |
| `OAUTH-1 Invalid redirect_uri: not registered` | Registered redirect URL doesn't match what CoCo sends | Register the exact string from CoCo's logs — `http://localhost:8585/callback`, not the bare host:port |
| `OAUTH-22 Invalid client_secret` with `client_secret` present in config | Wrong/stale secret, mismatched client_id, or trailing whitespace in the env var | Regenerate secret, re-export cleanly, or switch to public client (this doc) |
| `OAUTH-22 Invalid client_secret` with **no** `client_secret` in config | Qlik client registered as confidential (Web) but config omits secret | Either add `client_secret` back, or recreate the Qlik client as public (Native/SPA) — this doc |

## Notes

- Env keys, header keys, and OAuth secrets: verify with `cortex mcp get <name>` — the MCP Manager panel (`/mcp` inside a session) shows `Env Keys` / `Header Keys` as `None` if nothing is actually resolving, which is the fastest way to catch a broken variable reference before it manifests as a Qlik-side 400.
- MCP tool calls draw from the tenant's monthly question quota (shared with Qlik Answers, if licensed). Watch consumption in *Administration → Home* if agent usage is heavy.
- If your org later ships CoCo managed settings with an admin URL allowlist, `<your-tenant>.us.qlikcloud.com` must be on it or the server will be silently dropped after config merge.
