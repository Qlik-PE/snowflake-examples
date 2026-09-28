-- =============================================================================
-- Consumer Setup: Connect Qlik MCP Server to the Embedded Analytics Agent
-- =============================================================================
--
-- Run this script AFTER installing the Native App.
--
-- This script:
--   1. Grants the app caller USAGE on your warehouse and Qlik MCP server
--   2. Grants the app's APP_USER role to USER_ROLE (needed before Step 3,
--      which calls a procedure owned by the app)
--   3. Calls the app's core.configure_agent procedure to add the Cortex
--      Analyst warehouse and your Qlik MCP server to the agent spec
--   4. Creates the Snowflake Intelligence object, if needed
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
SET CONFIGURE_PROC = $APP_NAME || '.CORE.CONFIGURE_AGENT';
SET APP_USER_ROLE   = $APP_NAME || '.APP_USER';

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
-- Step 2: Grant Access to User Roles
-- =============================================================================
-- Must happen before Step 3: calling a procedure owned by the app requires
-- the caller's role to hold an application role with USAGE on it, and that
-- grant takes effect immediately for the role active in this session (no
-- re-login needed, unlike granting a role to a user).
-- =============================================================================

GRANT APPLICATION ROLE IDENTIFIER($APP_USER_ROLE)
    TO ROLE IDENTIFIER($USER_ROLE);

-- =============================================================================
-- Step 3: Wire the Warehouse and Qlik MCP Server into the Agent
-- =============================================================================
-- The app owns the agent; a consumer role only ever gets USAGE on it, never
-- MODIFY (SHOW GRANTS confirms this), so ALTER AGENT from here always fails
-- with "Insufficient privileges ... must have MODIFY granted on AGENT". The
-- app instead exposes core.configure_agent, an owner's-rights procedure that
-- does the ALTER AGENT on the consumer's behalf.
-- =============================================================================

CALL IDENTIFIER($CONFIGURE_PROC)($WAREHOUSE, $QLIK_MCP_SERVER);

-- =============================================================================
-- Step 4: Snowflake Intelligence Profile
-- =============================================================================
-- The agent appears in Snowflake Intelligence once it has a profile and the
-- user's role has been granted APP_USER (Step 2). The profile is already set
-- at install time by setup_script.sql (and would hit the same MODIFY
-- privilege error as Step 3 if repeated here), so only the Intelligence
-- object itself needs creating.
-- =============================================================================

-- Create the Intelligence object if it doesn't exist
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- =============================================================================
-- Step 5: Verify Setup
-- =============================================================================

-- Test the agent with a simple query
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $APP_NAME || '.CORE.ANALYTICS_AGENT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is total MRR by segment?"}]}]}'
) AS agent_response;
