-- =============================================================================
-- Multi-MCP Agent: Qlik + Second MCP Server
-- =============================================================================
--
-- This script creates a Cortex Agent wired to TWO external MCP servers,
-- demonstrating multi-MCP orchestration. The agent routes questions to the
-- appropriate server based on the domain of the question.
--
-- Default configuration: Qlik MCP + a second MCP server (e.g., Salesforce,
-- GitHub, Jira, or any MCP-compatible endpoint). Adapt the second server
-- configuration to your use case.
--
-- What is created:
--   - Cortex Agent with two MCP server connections
--   - Orchestration instructions for routing between servers
--
-- Prerequisites:
--   - Two existing External MCP Servers (created via CREATE EXTERNAL MCP SERVER
--     or the Snowflake UI)
--   - OAuth authentication completed for both servers (Step 4)
--   - ACCOUNTADMIN or a role with CREATE AGENT on the target schema
--
-- Architecture:
--
--   ┌─────────────────────────────────────────────────────────┐
--   │  Cortex Agent: MULTI_MCP_AGENT                          │
--   │  (orchestrates across both MCP servers)                 │
--   ├───────────────────────────┬─────────────────────────────┤
--   │                           │                             │
--   │  MCP Server 1: Qlik       │  MCP Server 2: <Second>     │
--   │  (analytics & dashboards) │  (CRM, issues, repos, etc.) │
--   │                           │                             │
--   │  Tools (examples):        │  Tools:                     │
--   │  • qlik_get_fields        │  • (varies by provider)     │
--   │  • qlik_create_data_object│  • search, create, update   │
--   │  • qlik_get_chart_data    │  • list, describe, etc.     │
--   │  • qlik_list_measures     │                             │
--   │  • qlik_create_sheet      │                             │
--   └───────────────────────────┴─────────────────────────────┘
--
-- Usage:
--   1. Fill in the parameters in Step 0
--   2. Run the entire script in a Snowflake worksheet
--   3. The agent will appear in Snowflake Intelligence (CoWork)
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Step 0: Configuration Parameters
-- =============================================================================

-- Target location for the agent
SET TARGET_DATABASE    = 'CORTEX_DEMOS';
SET TARGET_SCHEMA      = 'PUBLIC';
SET AGENT_NAME         = 'MULTI_MCP_AGENT';
SET AGENT_DISPLAY_NAME = 'Multi-MCP Agent';
SET WAREHOUSE          = 'COMPUTE';

-- MCP Server 1: Qlik Cloud
SET QLIK_MCP_SERVER_FQN = 'QLIK_MCP_DB.PUBLIC.qlik_mcp_server';    -- Your Qlik MCP server FQN
SET QLIK_APP_ID         = '<your-qlik-app-id>';                      -- Qlik Cloud app ID

-- MCP Server 2: Second provider (replace with your server)
-- Examples: Salesforce, GitHub, Jira, Slack, or any custom MCP server
SET SECOND_MCP_SERVER_FQN  = '<DB>.<SCHEMA>.<YOUR_SECOND_MCP_SERVER>';  -- FQN of your second MCP server
SET SECOND_MCP_LABEL       = 'SecondMCP';                               -- Short label used in instructions
SET SECOND_MCP_DESCRIPTION = 'CRM data, tickets, and customer records'; -- What the second server provides

-- =============================================================================
-- Step 1: Create the Multi-MCP Agent
-- =============================================================================

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

EXECUTE IMMEDIATE
$$
DECLARE
    v_agent_name VARCHAR;
    v_display_name VARCHAR;
    v_warehouse VARCHAR;
    v_qlik_mcp VARCHAR;
    v_qlik_app_id VARCHAR;
    v_second_mcp VARCHAR;
    v_second_label VARCHAR;
    v_second_desc VARCHAR;
    v_spec VARCHAR;
    v_sql VARCHAR;
    -- The spec must be dollar-quoted, but a literal double-dollar anywhere in
    -- this block (even in a comment) would end the block early, so the
    -- delimiter is assembled at runtime.
    v_dq VARCHAR DEFAULT '$' || '$';
BEGIN
    SELECT GETVARIABLE('AGENT_NAME') INTO v_agent_name;
    SELECT GETVARIABLE('AGENT_DISPLAY_NAME') INTO v_display_name;
    SELECT GETVARIABLE('WAREHOUSE') INTO v_warehouse;
    SELECT GETVARIABLE('QLIK_MCP_SERVER_FQN') INTO v_qlik_mcp;
    SELECT GETVARIABLE('QLIK_APP_ID') INTO v_qlik_app_id;
    SELECT GETVARIABLE('SECOND_MCP_SERVER_FQN') INTO v_second_mcp;
    SELECT GETVARIABLE('SECOND_MCP_LABEL') INTO v_second_label;
    SELECT GETVARIABLE('SECOND_MCP_DESCRIPTION') INTO v_second_desc;

    v_spec := 'models:\n'
        || '  orchestration: auto\n'
        || '\n'
        || 'instructions:\n'
        || '  response: |\n'
        || '    You are a multi-source assistant with access to TWO external tool providers.\n'
        || '    Always identify which source you used when answering.\n'
        || '\n'
        || '    When presenting data from Qlik, show the Qlik expression used.\n'
        || '    When presenting data from ' || v_second_label || ', note the specific tool and query.\n'
        || '    If a question requires data from both sources, query each separately and synthesize.\n'
        || '\n'
        || '  orchestration: |\n'
        || '    You have access to two MCP tool providers. Route questions as follows:\n'
        || '\n'
        || '    ## Qlik MCP (analytics & dashboards)\n'
        || '    Use Qlik tools when the user asks about:\n'
        || '    - Business metrics, KPIs, revenue, counts, aggregations\n'
        || '    - Dashboards, charts, sheets, visualizations\n'
        || '    - Data exploration, field values, master items\n'
        || '    - Bookmarks, selections, associative analysis\n'
        || '\n'
        || '    Qlik tool usage:\n'
        || '    - ALWAYS use app ID ' || v_qlik_app_id || '. Do NOT search for apps.\n'
        || '    - Use qlik_get_fields to discover available fields.\n'
        || '    - Use qlik_create_data_object to build hypercube queries.\n'
        || '    - Use qlik_get_chart_data to retrieve computed results.\n'
        || '    - Check qlik_list_measures and qlik_list_dimensions for governed master items.\n'
        || '    - Qlik performs ALL calculations server-side. Never re-aggregate returned data.\n'
        || '\n'
        || '    ## ' || v_second_label || ' (' || v_second_desc || ')\n'
        || '    Use ' || v_second_label || ' tools when the user asks about:\n'
        || '    - ' || v_second_desc || '\n'
        || '    - Records, items, or entities from the second system\n'
        || '    - Creating, updating, or searching external objects\n'
        || '\n'
        || '    ## Cross-source questions\n'
        || '    When a question spans both sources:\n'
        || '    1. Identify which parts map to which source\n'
        || '    2. Query each source separately\n'
        || '    3. Synthesize the results into a unified answer\n'
        || '    4. Clearly label which data came from which source\n'
        || '\n'
        || '  sample_questions:\n'
        || '    - question: "What is total revenue by region?" \n'
        || '    - question: "Show me the latest records from ' || v_second_label || '"\n'
        || '    - question: "Compare the Qlik dashboard data with ' || v_second_label || ' records"\n'
        || '    - question: "Create a chart showing revenue trends in Qlik"\n'
        || '    - question: "Search ' || v_second_label || ' for recent items and summarize"\n'
        || '\n'
        || 'mcp_servers:\n'
        || '  - server_spec:\n'
        || '      name: "' || v_qlik_mcp || '"\n'
        || '  - server_spec:\n'
        || '      name: "' || v_second_mcp || '"\n'
        || '\n'
        || 'execution_environment:\n'
        || '  type: warehouse\n'
        || '  warehouse: "' || v_warehouse || '"\n';

    v_sql := 'CREATE OR REPLACE AGENT ' || v_agent_name
        || ' PROFILE = ''{"display_name": "' || v_display_name || '", "avatar": "SparklesAgentIcon"}'''
        || ' FROM SPECIFICATION ' || v_dq || v_spec || v_dq;
    EXECUTE IMMEDIATE v_sql;
END;
$$;

-- =============================================================================
-- Step 2: Verify the Agent
-- =============================================================================

SELECT GET_DDL('CORTEX_AGENT', $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME);
SET TARGET_SCHEMA_FQN = $TARGET_DATABASE || '.' || $TARGET_SCHEMA;
SHOW AGENTS IN SCHEMA IDENTIFIER($TARGET_SCHEMA_FQN);

-- =============================================================================
-- Step 3: Register with Snowflake Intelligence (Optional)
-- =============================================================================

CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

EXECUTE IMMEDIATE
$$
DECLARE
    v_agent_fqn VARCHAR;
BEGIN
    SELECT GETVARIABLE('TARGET_DATABASE') || '.' || GETVARIABLE('TARGET_SCHEMA') || '.' || GETVARIABLE('AGENT_NAME') INTO v_agent_fqn;
    EXECUTE IMMEDIATE 'ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT ' || v_agent_fqn;
END;
$$;

-- =============================================================================
-- Step 4: Authenticate MCP Servers
-- =============================================================================
-- Each user must complete OAuth for BOTH MCP servers before the agent can
-- invoke their tools. Run these one at a time and follow the browser prompts.
-- =============================================================================

-- Authenticate Qlik MCP (replace with your integration name)
-- SELECT SYSTEM$START_USER_OAUTH_FLOW('<QLIK_API_INTEGRATION_NAME>');

-- Authenticate second MCP server (replace with your integration name)
-- SELECT SYSTEM$START_USER_OAUTH_FLOW('<SECOND_API_INTEGRATION_NAME>');

-- =============================================================================
-- Step 5: Test the Agent
-- =============================================================================

-- 5a. Test routing to Qlik MCP
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What fields are available in the Qlik app?"}]}]}',
    TRUE
  )
):status::VARCHAR AS test_status_qlik;

-- 5b. Test routing to the second MCP server
-- (Uncomment and adjust once your second MCP server is connected)
-- SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--     $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME,
--     '{"messages": [{"role": "user", "content": [{"type": "text", "text": "Search for recent items in ' || $SECOND_MCP_LABEL || '"}]}]}'
-- ) AS test_response_second;

-- =============================================================================
-- Appendix: Adding a Semantic View as a Third Tool
-- =============================================================================
-- You can combine MCP servers with a Cortex Analyst semantic view to create
-- a triple-source agent. Add this block to the specification:
--
--   tools:
--     - tool_spec:
--         type: "cortex_analyst_text_to_sql"
--         name: "SnowflakeData"
--         description: "Query structured Snowflake data via semantic view"
--
--   tool_resources:
--     SnowflakeData:
--       semantic_view: "<DB>.<SCHEMA>.<SEMANTIC_VIEW>"
--       execution_environment:
--         type: warehouse
--         warehouse: "<WAREHOUSE>"
--
-- Then update the orchestration instructions to include routing rules for
-- the third source, e.g.:
--   "Use SnowflakeData for structured SQL analytics (trends, aggregations)."
--   "Use Qlik MCP for dashboard exploration and governed metrics."
--   "Use SecondMCP for CRM/ticket/external data."
--
-- =============================================================================

-- =============================================================================
-- Cleanup (run manually when done)
-- =============================================================================
-- DROP AGENT MULTI_MCP_AGENT;   -- default AGENT_NAME; adjust if you changed it
