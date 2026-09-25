# MCP Integrations

Scripts and guides for connecting Snowflake to [Qlik Cloud](https://www.qlik.com/us/products/qlik-cloud) through the Model Context Protocol (MCP). With these, a Cortex Agent (or Cortex Code) can search Qlik apps, compute measures with the Qlik engine, and create sheets, charts, bookmarks and master items.

## Contents

| File | What it creates or explains | Run order |
|---|---|---|
| [create-mcp-agent.sql](create-mcp-agent.sql) | The OAuth2 **API integration**, the **External MCP Server**, a general-purpose **Qlik MCP agent**, and its Snowflake Intelligence registration. | **1st.** The other scripts reuse its MCP server. |
| [create-dual-source-agent.sql](create-dual-source-agent.sql) | An agent that answers every question from **both** Qlik MCP and a Semantic View, then returns only a comparison table. | After step 1 |
| [create-mcp-first-fallback-agent.sql](create-mcp-first-fallback-agent.sql) | An agent that tries **Qlik MCP first** and falls back to a Semantic View only when Qlik can't answer. | After step 1 |
| [create-multi-mcp-agent.sql](create-multi-mcp-agent.sql) | An agent wired to **two MCP servers** (Qlik plus e.g. Salesforce, GitHub or Jira), with routing rules. The appendix shows how to add a Semantic View as a third source. | After step 1, plus a second MCP server |
| [coco-qlik-mcp-public-client-setup.md](coco-qlik-mcp-public-client-setup.md) | How to connect the **Cortex Code CLI** to Qlik MCP with a public OAuth client (Authorization Code + PKCE, no client secret). | Independent |
| [coco-desktop-qlik-mcp-public-client-setup-windows.md](coco-desktop-qlik-mcp-public-client-setup-windows.md) | The same setup for **Cortex Code Desktop** on Windows. | Independent |

## Prerequisites

- A Snowflake account with Cortex Agents enabled.
- A Qlik Cloud tenant where a tenant admin has turned on MCP.
- Every Qlik user who will authenticate needs **Qlik MCP → Allowed** in their role (*Management Console → Features and actions → Agentic AI*).
- For `create-mcp-agent.sql`: `ACCOUNTADMIN` (or `CREATE INTEGRATION`, `CREATE MCP SERVER`, `CREATE AGENT` and `MANAGE GRANTS`), plus a Qlik OAuth client (below).
- For the dual-source and fallback agents: a Semantic View over the same data as the Qlik app.
- For the multi-MCP agent: a second External MCP Server, with OAuth completed.

## Set Up the Qlik OAuth Client

`create-mcp-agent.sql` needs an OAuth client in Qlik Cloud. Snowflake uses it to get a token for each user.

1. Sign in to Qlik Cloud as a **tenant admin** and open **Management Console → OAuth → Create new**.
2. Configure the client:

   | Setting | Value |
   |---|---|
   | Client name | `SnowflakeMCP` (any name works) |
   | App type | `Web` (confidential client, which has a secret) |
   | Consent method | `Required` |
   | Redirect URI | `https://identity.snowflake.com/oauth2/callback` |
   | Allowed scopes | `user_default`, `mcp:execute`, `offline_access` |

   > **`offline_access` is required.** Without it, Snowflake can't store a refresh token. The browser still shows "OAuth Flow Completed", but the agent can't discover or call any MCP tool.

3. Click **Create** and copy the **Client ID** and **Client Secret**.
4. Under **Settings → Feature control** (or **Features and actions**), confirm that **Agentic AI / MCP** is enabled.

## Run `create-mcp-agent.sql`

1. Fill in the `SET` block at the top: `TENANT`, `CLIENT_ID`, `CLIENT_SECRET`, `ALLOWED_ROLE`, `TARGET_DATABASE`, `TARGET_SCHEMA`, and optionally the object names.
2. Run the whole script in a worksheet, or with `snow sql -f mcp/create-mcp-agent.sql`.
3. **Each user** then completes the OAuth flow once:
   ```sql
   SELECT SYSTEM$START_USER_OAUTH_FLOW('<INTEGRATION_NAME>');
   ```
   Open the returned URL, sign in to Qlik and approve. When the browser shows "OAuth Flow Completed", the MCP tools are available to that user's agent calls.

> Re-running the script drops and recreates the API integration, which **invalidates every user's OAuth token**. Every user must then repeat step 3.

## The Three Agent Patterns

All three scripts share the same `SET` block at the top: target database/schema, agent name, `QLIK_MCP_SERVER_FQN`, `QLIK_APP_ID`, and, for the Semantic View scripts, `SEMANTIC_VIEW_FQN` and `ANALYST_WAREHOUSE`. Each agent is scoped to one Qlik app ID, so it doesn't search for apps.

### Dual-source comparison: `create-dual-source-agent.sql`

The agent sends every question to **both** Qlik MCP and Cortex Analyst. It returns **only** comparison metadata, never data rows. This is useful for checking that the two semantic layers agree, or for benchmarking them.

| Row in the output | Meaning |
|---|---|
| Expression / SQL | The Qlik expression used vs. the SQL that Cortex Analyst generated |
| Tool calls | Number of tool invocations on each path |
| Duration (seconds) | Wall-clock time from the first tool call to the last result |
| Token consumption (est.) | The agent's own **estimate** of input + output tokens (not metered) |
| Status | success / error / auth required |

Example output:

```
## Comparison: How many customers per market segment?

| Metric | Qlik MCP | Semantic View |
|--------|----------|---------------|
| Expression / SQL | Dim: C_MKTSEGMENT, Measure: Count(C_CUSTKEY) | SELECT c_mktsegment, COUNT(c_custkey) FROM ... |
| Tool calls | 3 | 2 |
| Duration (seconds) | 2.1 | 1.8 |
| Token consumption (est.) | ~4,200 | ~3,800 |
| Status | success | success |
```

The agent ships with ten TPC-H sample questions, for example *"How many customers are there per market segment (c_mktsegment)?"*. To see real, metered token usage per agent, use [`sql/cortex-agent-token-usage.sql`](../sql/cortex-agent-token-usage.sql).

### MCP-first with fallback: `create-mcp-first-fallback-agent.sql`

```
User question
     │
     ▼
┌─────────────┐   success   ┌────────────────────────────┐
│  Qlik MCP   │────────────▶│ Answer (Source: Qlik MCP)  │
│  (primary)  │             └────────────────────────────┘
└──────┬──────┘
       │ auth error / tool error / field not in app / empty result
       ▼
┌─────────────┐   success   ┌────────────────────────────┐
│  Semantic   │────────────▶│ Answer (Source: Snowflake  │
│  View       │             │ Semantic View (fallback))  │
└─────────────┘             └────────────────────────────┘
```

The agent:
1. Always tries Qlik MCP first, and prefers governed master items tagged `MCP`.
2. Falls back to Cortex Analyst only on an authentication error, a tool failure, a field that doesn't exist in the app, or an empty result.
3. Never queries both sources for the same question.
4. Starts every answer with the source that produced it, and gives a one-line reason whenever it falls back.

Use this pattern when Qlik is the governed source of truth, but the agent must keep working when a user's Qlik OAuth token has expired or the MCP server is unreachable.

### Multi-MCP: `create-multi-mcp-agent.sql`

The agent is wired to the Qlik MCP server and one other MCP server. Set `SECOND_MCP_SERVER_FQN`, a short `SECOND_MCP_LABEL`, and a `SECOND_MCP_DESCRIPTION` of what that server holds; the routing instructions are generated from these. Every user must complete OAuth for **both** servers.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Warning `003001` "User authentication required" even though the OAuth flow completed | `offline_access` scope is missing | Add `offline_access` to the Qlik OAuth client **and** to `OAUTH_ALLOWED_SCOPES` in the API integration, then authenticate again |
| Server error during the OAuth redirect | Wrong client secret, or the tenant is unreachable | Check the client secret and the tenant hostname |
| `SYSTEM$FINISH_OAUTH_FLOW` fails with "Authorization code is not present" | Wrong function | Use `SYSTEM$START_USER_OAUTH_FLOW` only. The browser redirect finishes the flow automatically. |
| OAuth works in Snowsight but not from the CLI | Tokens are stored per user, and the CLI connects as a different user | Run `SYSTEM$START_USER_OAUTH_FLOW` as the CLI user |
| New Qlik MCP tools don't appear | The tool list is cached per user | Sign out of Qlik and authenticate again |

## Try Qlik Cloud

Don't have a Qlik Cloud tenant yet? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics) to try the MCP integrations.

## License

See [LICENSE](../LICENSE).
