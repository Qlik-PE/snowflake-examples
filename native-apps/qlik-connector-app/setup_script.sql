-- =============================================================================
-- Qlik Connector App - Setup Script (Boilerplate)
-- =============================================================================
--
-- This is a template Native App setup script for Qlik + Snowflake integrations.
-- Replace the placeholder sections with your own data model, semantic view,
-- and agent configuration.
--
-- Sections:
--   1. Application role and schema
--   2. Reference callback (for warehouse binding)
--   3. Data tables (replace with your own)
--   4. Semantic View (replace with your own)
--   5. Cortex Agent (update instructions and tools)
--   6. Grants and profile
--
-- =============================================================================

-- =============================================================================
-- 1. Application Role & Schema
-- =============================================================================

CREATE APPLICATION ROLE IF NOT EXISTS app_user;
CREATE SCHEMA IF NOT EXISTS core;
GRANT USAGE ON SCHEMA core TO APPLICATION ROLE app_user;

-- =============================================================================
-- 2. Reference Registration Callback
-- =============================================================================

CREATE OR REPLACE PROCEDURE core.register_reference(ref_name STRING, operation STRING, ref_or_alias STRING)
    RETURNS STRING
    LANGUAGE SQL
AS
BEGIN
    CASE (operation)
        WHEN 'ADD' THEN SELECT SYSTEM$SET_REFERENCE(:ref_name, :ref_or_alias);
        WHEN 'REMOVE' THEN SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
        WHEN 'CLEAR' THEN SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
    END CASE;
    RETURN 'OK';
END;

GRANT USAGE ON PROCEDURE core.register_reference(STRING, STRING, STRING)
    TO APPLICATION ROLE app_user;

-- =============================================================================
-- 3. Data Tables (REPLACE WITH YOUR OWN)
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.my_table (
    id INT,
    name VARCHAR(100),
    category VARCHAR(50),
    value DECIMAL(10,2),
    created_at DATE
);

-- INSERT your seed data here or load from a stage

GRANT SELECT ON ALL TABLES IN SCHEMA core TO APPLICATION ROLE app_user;

-- =============================================================================
-- 4. Semantic View (REPLACE WITH YOUR OWN)
-- =============================================================================

-- CREATE OR REPLACE SEMANTIC VIEW core.my_semantic_view
--   TABLES (
--     core.my_table primary key (id) comment='Description of your table'
--   )
--   FACTS (
--     MY_TABLE.name as name,
--     MY_TABLE.category as category,
--     MY_TABLE.value as value,
--     MY_TABLE.created_at as created_at
--   )
--   METRICS (
--     MY_TABLE.total_value as SUM(MY_TABLE.value)
--       with synonyms=('total', 'sum of values'),
--     MY_TABLE.avg_value as AVG(MY_TABLE.value)
--       with synonyms=('average', 'mean value'),
--     MY_TABLE.record_count as COUNT(DISTINCT MY_TABLE.id)
--       with synonyms=('count', 'number of records')
--   );

-- GRANT SELECT ON SEMANTIC VIEW core.my_semantic_view TO APPLICATION ROLE app_user;

-- =============================================================================
-- 5. Cortex Agent (UPDATE INSTRUCTIONS AND TOOLS)
-- =============================================================================

CREATE OR REPLACE AGENT core.my_agent
    FROM SPECIFICATION $$
models:
  orchestration: auto

instructions:
  response: |
    You are an analytics assistant. You have access to:
    1. A Snowflake semantic view for structured data queries via Cortex Analyst.
    2. Qlik Cloud analytics via MCP server for dashboards and visualizations.

    Route data questions to the semantic view tool.
    Route visualization requests to Qlik MCP tools.
  orchestration: |
    Route data questions to the semantic view tool.
    Route dashboard and chart requests to Qlik MCP tools.
  sample_questions:
    - question: "What is the total value by category?"
    - question: "Show me a trend of values over time"
    - question: "Create a chart in Qlik showing the breakdown"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "MyData"
      description: "Query your data model. Replace this description with specifics about your domain."

tool_resources:
  MyData:
    semantic_view: "core.my_semantic_view"
    execution_environment:
      type: warehouse
      warehouse: "REPLACE_WITH_YOUR_WAREHOUSE"

mcp_servers:
  - server_spec:
      name: "REPLACE_DB.REPLACE_SCHEMA.YOUR_QLIK_MCP_SERVER"
$$;

GRANT USAGE ON AGENT core.my_agent TO APPLICATION ROLE app_user;

-- =============================================================================
-- 6. Agent Profile (for CoWork visibility)
-- =============================================================================

ALTER AGENT core.my_agent SET
    COMMENT = 'Replace with your agent description',
    PROFILE = '{"display_name": "My App Agent", "avatar": "SparklesAgentIcon"}';

-- =============================================================================
-- Post-Install Checklist:
-- =============================================================================
-- After installing, the consumer admin must:
--   1. Grant caller privileges:
--      GRANT CALLER USAGE ON WAREHOUSE <wh> TO APPLICATION <app>;
--      GRANT CALLER USAGE ON DATABASE <db> TO APPLICATION <app>;
--      GRANT CALLER USAGE ON SCHEMA <db.schema> TO APPLICATION <app>;
--      GRANT CALLER USAGE ON EXTERNAL MCP SERVER <mcp> TO APPLICATION <app>;
--   2. Grant application role to user role:
--      GRANT APPLICATION ROLE <app>.APP_USER TO ROLE <role>;
--   3. Register with Snowflake Intelligence:
--      ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
--        ADD AGENT <app>.CORE.MY_AGENT;
--   4. Authenticate with Qlik:
--      SELECT SYSTEM$START_USER_OAUTH_FLOW('<integration_name>');
-- =============================================================================
