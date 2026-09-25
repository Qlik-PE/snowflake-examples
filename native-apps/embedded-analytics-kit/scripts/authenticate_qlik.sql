-- =============================================================================
-- Authenticate with Qlik MCP Server
-- =============================================================================
--
-- Run this script to start the OAuth flow for the Qlik MCP server.
-- After running, a URL will be returned. Open it in your browser to
-- authorize the connection to Qlik Cloud.
--
-- Prerequisites:
--   - USAGE on the Qlik External MCP Server and on its API integration
--     (created by mcp/create-mcp-agent.sql; default integration name
--     QLIK_MCP_INTEGRATION, so replace it below if yours differs)
--   - A user on the Qlik Cloud tenant that the integration points to, with
--     Qlik MCP allowed for their role
--
-- =============================================================================

-- Step 1: Start the OAuth flow
-- This returns an authorization URL. Open it in your browser.
SELECT SYSTEM$START_USER_OAUTH_FLOW('QLIK_MCP_INTEGRATION') AS auth_url;

-- Step 2: Open the URL, sign in to Qlik and approve. Snowflake completes the
-- flow automatically when the browser shows "OAuth Flow Completed". Do NOT
-- call SYSTEM$FINISH_OAUTH_FLOW; it fails with "Authorization code is not
-- present" for this flow.
--
-- Once complete, the agent can access Qlik Cloud tools on your behalf.

-- =============================================================================
-- Verify authentication status
-- =============================================================================
-- After authenticating, test the agent with a Qlik-specific question:

-- SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--     'EMBEDDED_ANALYTICS_KIT.CORE.ANALYTICS_AGENT',
--     '{"messages": [{"role": "user", "content": [{"type": "text", "text": "List my Qlik apps"}]}]}'
-- );
