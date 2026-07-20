# Qlik MCP Chat Interface

A Streamlit in Snowflake app that provides a conversational chat UI for interacting with Qlik Cloud through the Snowflake Cortex Agent + MCP server connection.

## Features

- Chat interface with full conversation history
- Connects to Qlik Cloud via the MCP server connection (no raw REST calls)
- Access to 70+ Qlik tools: app discovery, data analysis, chart creation, bookmarks, glossary, datasets, lineage
- Configurable agent and MCP server selection
- OAuth error handling with clear remediation steps

## Prerequisites

- Qlik MCP server and Cortex Agent created via `mcp/create-mcp-agent.sql`
- User has completed the OAuth flow: `SELECT SYSTEM$START_USER_OAUTH_FLOW('<integration>')`
- Streamlit in Snowflake enabled
- A role with USAGE on the agent, MCP server, and a warehouse

## Deployment

### Option 1: Snowflake CLI

```bash
snow streamlit deploy \
  --database QLIK_MCP \
  --schema PUBLIC \
  --name cortex_agent_chat \
  --file app.py \
  --env-file environment.yml
```

### Option 2: SQL

```sql
CREATE OR REPLACE STREAMLIT QLIK_MCP.PUBLIC.cortex_agent_chat
  ROOT_LOCATION = '@QLIK_MCP.PUBLIC.streamlit_stage/cortex-agent-chat'
  MAIN_FILE = 'app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH';
```

Upload `app.py` and `environment.yml` to the stage path above before running.

### Option 3: Snowsight UI

1. Navigate to Streamlit in Snowsight
2. Click "Create Streamlit App"
3. Paste the contents of `app.py`
4. Add packages from `environment.yml` in the package manager

## Configuration

After deploying, use the sidebar in the app to configure:

- **Database** - The database containing your Cortex Agent and MCP server
- **Schema** - The schema containing your Cortex Agent and MCP server
- **Agent Name** - The name of the Cortex Agent (wired to the MCP server)
- **MCP Server** - The name of the Qlik MCP server object

The defaults point to the objects created by `mcp/create-mcp-agent.sql`.

## How It Works

1. The Streamlit app uses a Snowpark session to call the Cortex Agent via SQL
2. The Cortex Agent routes requests through the Qlik MCP server connection
3. The MCP server authenticates to Qlik Cloud via OAuth2 (per-user tokens)
4. Qlik Cloud executes the requested tool (search, describe, create chart, etc.)
5. Results flow back through the MCP connection to the chat UI

## Usage

1. Open the Streamlit app in Snowsight
2. Verify the agent and MCP server configuration in the sidebar
3. Type a question (e.g., "List my Qlik apps" or "Show me the fields in app X")
4. The agent will call Qlik MCP tools and return results
