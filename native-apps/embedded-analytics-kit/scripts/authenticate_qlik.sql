-- =============================================================================
-- Authenticate with Qlik MCP Server
-- =============================================================================
--
-- Run this script to start the OAuth flow for the Qlik MCP server.
-- After running, a URL will be returned. Open it in your browser to
-- authorize the connection to Qlik Cloud.
--
-- Prerequisites:
--   - USAGE grant on the MCP server (CORTEX_APP.PUBLIC.QLIK_MCP_SERVER)
--   - USAGE grant on the API integration (QLIK_MCP_INTEGRATION)
--   - A Qlik Cloud account on partner-engineering-saas.us.qlikcloud.com
--
-- =============================================================================

-- Step 1: Start the OAuth flow
-- This returns an authorization URL. Open it in your browser.
SELECT SYSTEM$START_USER_OAUTH_FLOW('QLIK_MCP_INTEGRATION') AS auth_url;

-- Step 2: After completing authorization in your browser, you will be
-- redirected to a callback URL. Copy the FULL callback URL (including
-- the query string) and paste it below:
--
-- SELECT SYSTEM$FINISH_OAUTH_FLOW('<paste_full_callback_url_here>');
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
