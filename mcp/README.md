# MCP Integrations

Guides and scripts for connecting Snowflake to [Qlik Cloud](https://www.qlik.com/us/products/qlik-cloud) via the Model Context Protocol (MCP).

## Contents

| File | Description |
|------|-------------|
| [create-mcp-agent.sql](create-mcp-agent.sql) | End-to-end SQL script that provisions a Qlik Cloud MCP integration in Snowflake — creates an OAuth2 API integration, an external MCP server, a Cortex Agent wired to that server, and registers it with Snowflake Intelligence. |
| [coco-qlik-mcp-public-client-setup.md](coco-qlik-mcp-public-client-setup.md) | Setup guide for connecting **Cortex Code CLI** to the Qlik MCP server using a public OAuth client (Authorization Code + PKCE, no client secret). |
| [coco-desktop-qlik-mcp-public-client-setup-windows.md](coco-desktop-qlik-mcp-public-client-setup-windows.md) | Same as above, tailored for **Cortex Code Desktop** (VS Code-based IDE) on Windows. |

## Prerequisites

- A Snowflake account with Cortex AI enabled.
- A Qlik Cloud tenant with MCP activated by a tenant admin.
- For `create-mcp-agent.sql`: ACCOUNTADMIN (or equivalent privileges) and OAuth client credentials from Qlik.
- For the CoCo/Desktop guides: your user role must have **Qlik MCP → Allowed** under Qlik's *Features and actions → Agentic AI*.

## Qlik OAuth App Setup (Step-by-Step)

Before running `create-mcp-agent.sql`, you must create an OAuth app in Qlik Cloud. Follow these steps:

### Step 1: Navigate to OAuth settings

1. Log in to your Qlik Cloud tenant as a **tenant admin**.
2. Go to **Management Console** (gear icon in the top-right).
3. In the left sidebar, select **OAuth**.
4. Click **Create new**.

### Step 2: Configure the OAuth app

Set the following values:

| Setting | Value |
|---------|-------|
| **Client name** | `SnowflakeMCP` (or any descriptive name) |
| **App type** | `Web` |
| **Consent method** | `Required` |
| **Redirect URIs** | `https://identity.snowflake.com/oauth2/callback` |
| **Allowed scopes** | `user_default`, `mcp:execute`, `offline_access` |

> **Important:** The `offline_access` scope is **required** for Snowflake to persist refresh tokens. Without it, the OAuth flow appears to succeed (browser shows "OAuth Flow Completed") but the Cortex Agent cannot discover or invoke MCP tools.

### Step 3: Save and copy credentials

1. Click **Create** to save the OAuth app.
2. Copy the **Client ID** and **Client Secret** — you will need these for the `CLIENT_ID` and `CLIENT_SECRET` parameters in `create-mcp-agent.sql`.

### Step 4: Verify MCP is enabled

1. In the Management Console, go to **Settings** > **Feature control** (or **Features and actions**).
2. Confirm that **Agentic AI / MCP** is enabled for the tenant.
3. Ensure the users who will authenticate have the **Qlik MCP → Allowed** permission under their assigned role.

### Step 5: Run the SQL script

1. Open `create-mcp-agent.sql` and fill in the configuration parameters (tenant, client ID, client secret, etc.).
2. Run the script in a Snowflake worksheet or via SnowSQL.
3. Each user must then complete the OAuth flow individually:

```sql
SELECT SYSTEM$START_USER_OAUTH_FLOW('<INTEGRATION_NAME>');
```

This returns a URL. Open it in a browser, authenticate with Qlik Cloud, and authorize the connection. Once the browser shows "OAuth Flow Completed", the MCP tools become available to the Cortex Agent.

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Agent returns warning 003001 "User authentication required" after OAuth flow completes | Missing `offline_access` scope | Add `offline_access` to both the Qlik OAuth app and the Snowflake API Integration scopes, then re-authenticate |
| Server error during OAuth redirect | Wrong client secret, or Qlik tenant is unreachable | Verify the client secret matches, check tenant availability |
| `SYSTEM$FINISH_OAUTH_FLOW` fails with "Authorization code is not present" | Using the wrong function | Use `SYSTEM$START_USER_OAUTH_FLOW` (not `SYSTEM$START_OAUTH_FLOW`); the callback is handled automatically by the browser |
| OAuth flow succeeds in Snowsight but not via CLI | Token is per-user; CLI may use a different user | Run `SYSTEM$START_USER_OAUTH_FLOW` from the CLI session and complete the flow for that user |

## Try Qlik Cloud

Don't have a Qlik Cloud tenant yet? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics) to get started with MCP integrations.

## License

See [LICENSE](../LICENSE) for details.
