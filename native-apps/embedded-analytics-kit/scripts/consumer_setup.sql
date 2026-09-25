-- =============================================================================
-- Consumer Setup: Connect Qlik MCP Server to the Embedded Analytics Agent
-- =============================================================================
--
-- Run this script AFTER installing the Native App.
--
-- This script:
--   1. Grants the app caller USAGE on your warehouse and Qlik MCP server
--   2. Replaces the agent spec to add the Cortex Analyst warehouse and your
--      Qlik MCP server
--   3. Sets the agent's Snowflake Intelligence profile
--   4. Grants the app's APP_USER role to USER_ROLE
--   5. Verifies the setup with a test query
--
-- Prerequisites:
--   - The Native App is installed (e.g., as EMBEDDED_ANALYTICS_KIT)
--   - You have an existing Qlik MCP server (created via mcp/create-mcp-agent.sql
--     or through the Snowflake UI)
--   - You have completed Qlik OAuth flow for your user
--   - ACCOUNTADMIN or a role with MANAGE GRANTS
--
-- =============================================================================

-- =============================================================================
-- Step 0: Configuration
-- =============================================================================

SET APP_NAME = 'EMBEDDED_ANALYTICS_KIT';           -- Name of installed Native App
SET WAREHOUSE = 'CORTEX';                          -- Warehouse for agent execution
SET QLIK_MCP_SERVER = 'CORTEX_APP.PUBLIC.QLIK_MCP_SERVER';  -- Your Qlik MCP server FQN
SET USER_ROLE = 'ACCOUNTADMIN';                    -- Role that will use the agent (prefer a non-admin role)

-- IDENTIFIER() takes a literal or a bare variable, never a concatenation.
SET AGENT_FQN     = $APP_NAME || '.CORE.ANALYTICS_AGENT';
SET APP_USER_ROLE = $APP_NAME || '.APP_USER';

-- =============================================================================
-- Step 1: Grant Caller Privileges
-- =============================================================================
-- The agent runs with restricted caller's rights: it can only use consumer
-- objects that are explicitly granted to the app with GRANT CALLER.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Grant warehouse access to the app
GRANT CALLER USAGE ON WAREHOUSE IDENTIFIER($WAREHOUSE)
    TO APPLICATION IDENTIFIER($APP_NAME);

-- Grant access to the MCP server
GRANT CALLER USAGE ON EXTERNAL MCP SERVER IDENTIFIER($QLIK_MCP_SERVER)
    TO APPLICATION IDENTIFIER($APP_NAME);

-- =============================================================================
-- Step 2: Wire the Warehouse and Qlik MCP Server into the Agent
-- =============================================================================
-- Replaces the agent's live spec with one that adds:
--   - the warehouse Cortex Analyst uses ($WAREHOUSE), and
--   - your Qlik MCP server ($QLIK_MCP_SERVER) as a tool source.
-- The spec is built inside a scripting block so both session variables can be
-- concatenated in. A literal double-dollar would end the block, so the spec
-- delimiter is assembled at runtime.
-- =============================================================================

EXECUTE IMMEDIATE
$$
DECLARE
    v_agent VARCHAR;
    v_wh    VARCHAR;
    v_mcp   VARCHAR;
    v_dq    VARCHAR DEFAULT '$' || '$';
    v_spec  VARCHAR;
BEGIN
    SELECT GETVARIABLE('APP_NAME') || '.CORE.ANALYTICS_AGENT' INTO v_agent;
    SELECT GETVARIABLE('WAREHOUSE') INTO v_wh;
    SELECT GETVARIABLE('QLIK_MCP_SERVER') INTO v_mcp;

    v_spec := '
models:
  orchestration: auto

instructions:
  response: |
    You are an embedded analytics assistant for SaaS companies. You have access to:

    1. **SaaS Metrics (Snowflake)** - Query subscription data, revenue metrics (MRR, ARR,
       churn, NRR, expansion), account details, and usage analytics directly from Snowflake
       via Cortex Analyst.

    2. **Qlik Cloud Analytics** - Explore Qlik applications, dashboards, master items,
       create visualizations, manage bookmarks, and investigate data using Qlik''s
       associative engine.

    ## When to use each tool:

    **Use SaaS Metrics (Cortex Analyst) when:**
    - User asks about specific metrics: MRR, ARR, churn, retention, revenue
    - User wants data by segment, region, plan tier, time period
    - User needs ad-hoc analysis or custom aggregations
    - User asks "what is..." or "how much..." type questions about the data

    **Use Qlik MCP tools when:**
    - User asks about existing dashboards or visualizations
    - User wants to create/modify charts or sheets
    - User asks to explore apps or find specific Qlik content
    - User wants governed master items (dimensions/measures)
    - User asks "show me..." or "create a chart..." type requests

    **Use both when:**
    - User wants to analyze data AND visualize it
    - User asks a metric question and wants a dashboard created
    - User needs to compare Snowflake data with Qlik dashboard findings

    ## Response guidelines:
    - Be concise and data-driven
    - When presenting metrics, include the time period and any filters applied
    - When creating Qlik visualizations, confirm the app ID with the user first
    - Format numbers clearly (e.g., $45,000 MRR, 95.2% NRR)

  orchestration: |
    Route questions about data metrics to SaaSMetrics.
    Route questions about dashboards and visualizations to Qlik MCP tools.
    For hybrid requests, query the data first, then create visualizations.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "SaaSMetrics"
      description: "Query SaaS subscription metrics including MRR, ARR, churn rate, net revenue retention, expansion revenue, account details, usage patterns, and customer segments from Snowflake."

tool_resources:
  SaaSMetrics:
    semantic_view: "core.saas_metrics_sv"
    execution_environment:
      type: warehouse
      warehouse: "' || v_wh || '"

mcp_servers:
  - server_spec:
      name: "' || v_mcp || '"
';

    EXECUTE IMMEDIATE 'ALTER AGENT ' || v_agent
        || ' MODIFY LIVE VERSION SET SPECIFICATION = ' || v_dq || v_spec || v_dq;
END;
$$;

-- =============================================================================
-- Step 3: Snowflake Intelligence Profile
-- =============================================================================
-- The agent appears in Snowflake Intelligence once it has a profile and the
-- user's role has been granted APP_USER (Step 4).
-- =============================================================================

-- Create the Intelligence object if it doesn't exist
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

ALTER AGENT IDENTIFIER($AGENT_FQN)
    SET PROFILE = '{"display_name": "SaaS Analytics Kit (Qlik + Snowflake)", "avatar": "SparklesAgentIcon"}';

-- =============================================================================
-- Step 4: Grant Access to User Roles
-- =============================================================================

GRANT APPLICATION ROLE IDENTIFIER($APP_USER_ROLE)
    TO ROLE IDENTIFIER($USER_ROLE);

-- =============================================================================
-- Step 5: Verify Setup
-- =============================================================================

-- Test the agent with a simple query
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $APP_NAME || '.CORE.ANALYTICS_AGENT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is total MRR by segment?"}]}]}'
) AS agent_response;
