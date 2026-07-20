-- =============================================================================
-- Consumer Setup: Connect Qlik MCP Server to the Embedded Analytics Agent
-- =============================================================================
--
-- Run this script AFTER installing the Native App.
--
-- This script:
--   1. Grants the app caller privileges on your warehouse
--   2. Alters the agent to include your Qlik MCP server
--   3. Registers the agent with Snowflake Intelligence
--   4. Verifies the setup with a test query
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
SET USER_ROLE = 'ACCOUNTADMIN';                    -- Role that will use the agent

-- =============================================================================
-- Step 1: Grant Caller Privileges
-- =============================================================================
-- The agent runs under restricted caller's rights. It needs caller grants on
-- your warehouse to execute queries.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Grant warehouse access to the app
GRANT CALLER USAGE ON WAREHOUSE IDENTIFIER($WAREHOUSE)
    TO APPLICATION IDENTIFIER($APP_NAME);

-- Grant access to the MCP server
GRANT CALLER USAGE ON EXTERNAL MCP SERVER IDENTIFIER($QLIK_MCP_SERVER)
    TO APPLICATION IDENTIFIER($APP_NAME);

-- =============================================================================
-- Step 2: Wire the Qlik MCP Server to the Agent
-- =============================================================================
-- This alters the agent spec to add your Qlik MCP server as a tool source.
-- After this, the agent can access Qlik Cloud tools alongside the Semantic View.
-- =============================================================================

ALTER AGENT IDENTIFIER($APP_NAME || '.CORE.ANALYTICS_AGENT')
    MODIFY LIVE VERSION SET SPECIFICATION $$
models:
  orchestration: auto

instructions:
  response: |
    You are an embedded analytics assistant for SaaS companies. You have access to:

    1. **SaaS Metrics (Snowflake)** - Query subscription data, revenue metrics (MRR, ARR,
       churn, NRR, expansion), account details, and usage analytics directly from Snowflake
       via Cortex Analyst.

    2. **Qlik Cloud Analytics** - Explore Qlik applications, dashboards, master items,
       create visualizations, manage bookmarks, and investigate data using Qlik's
       associative engine.

    ## When to use each tool:

    **Use SaaS Metrics (Cortex Analyst) when:**
    - User asks about specific metrics: MRR, ARR, churn, retention, revenue
    - User wants data by segment, region, plan tier, time period
    - User needs ad-hoc analysis or custom aggregations

    **Use Qlik MCP tools when:**
    - User asks about existing dashboards or visualizations
    - User wants to create/modify charts or sheets
    - User asks to explore apps or find specific Qlik content
    - User wants governed master items (dimensions/measures)

    **Use both when:**
    - User wants to analyze data AND visualize it
    - User asks a metric question and wants a dashboard created

  orchestration: |
    Route questions about data metrics to SaaSMetrics.
    Route questions about dashboards and visualizations to Qlik MCP tools.
    For hybrid requests, query the data first, then create visualizations.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "SaaSMetrics"
      description: "Query SaaS subscription metrics including MRR, ARR, churn rate, net revenue retention, expansion revenue, account details, usage patterns, and customer segments."

tool_resources:
  SaaSMetrics:
    semantic_view: "core.saas_metrics_sv"
    execution_environment:
      type: warehouse
$$;

-- Note: The MCP server is added separately via ALTER AGENT ... ADD MCP SERVER
-- because it references a consumer-owned object.
-- If your Snowflake version supports mcp_servers in the spec directly, use:
--
-- mcp_servers:
--   - server_spec:
--       name: "<your_qlik_mcp_server_fqn>"
--
-- appended to the specification above.

-- =============================================================================
-- Step 3: Register with Snowflake Intelligence
-- =============================================================================
-- This makes the agent discoverable in the Snowflake Intelligence / CoWork UI.
-- =============================================================================

-- Create the Intelligence object if it doesn't exist
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS;

-- Register the agent (may require specific syntax depending on account setup)
-- The agent will appear in Snowflake Intelligence automatically if it has a profile.

ALTER AGENT IDENTIFIER($APP_NAME || '.CORE.ANALYTICS_AGENT')
    SET PROFILE = (
        DISPLAY_NAME = 'SaaS Analytics Kit (Qlik + Snowflake)'
    );

-- =============================================================================
-- Step 4: Grant Access to User Roles
-- =============================================================================

GRANT APPLICATION ROLE IDENTIFIER($APP_NAME || '.APP_USER')
    TO ROLE IDENTIFIER($USER_ROLE);

-- =============================================================================
-- Step 5: Verify Setup
-- =============================================================================

-- Test the agent with a simple query
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $APP_NAME || '.CORE.ANALYTICS_AGENT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is total MRR by segment?"}]}]}'
) AS agent_response;
