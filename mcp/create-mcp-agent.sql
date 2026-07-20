-- =============================================================================
-- Qlik MCP Server Connection Setup for Snowflake Cortex Agent
-- =============================================================================
--
-- This script provisions a complete Qlik Cloud MCP integration in Snowflake:
--   1. Creates an API Integration with OAuth2 client credentials
--   2. Creates an External MCP Server pointing to the Qlik MCP endpoint
--   3. Grants access to the specified role
--   4. Creates a Cortex Agent wired to the MCP server
--   5. Registers the agent with Snowflake Intelligence
--
-- What is created:
--   - API Integration:       <INTEGRATION_NAME>  (OAuth2, external_mcp provider)
--   - External MCP Server:   <MCP_SERVER_NAME>   (in current DB/schema)
--   - Cortex Agent:          <AGENT_NAME>        (in current DB/schema)
--   - Snowflake Intelligence: SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT (if not exists)
--
-- Prerequisites:
--   - ACCOUNTADMIN role (or a custom role with CREATE INTEGRATION, CREATE MCP
--     SERVER, CREATE AGENT, and MANAGE GRANTS privileges)
--   - A Qlik Cloud tenant with MCP enabled
--   - OAuth client credentials (Client ID and Client Secret) from Qlik
--     (created in Qlik Management Console > OAuth)
--   - The ALLOWED_ROLE must exist before running this script
--
-- Usage:
--   1. Fill in the parameters below (TENANT, CLIENT_ID, CLIENT_SECRET, etc.)
--   2. Run the entire script in a Snowflake worksheet or via SnowSQL
--   3. After completion, each user must authenticate individually:
--        SELECT SYSTEM$START_USER_OAUTH_FLOW('<INTEGRATION_NAME>');
--
-- Idempotency:
--   This script uses CREATE OR REPLACE and is safe to re-run. However,
--   re-running will invalidate existing OAuth tokens for the integration.
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Step 0: Configuration Parameters
-- =============================================================================
-- Customize these values for your environment. Everything below this section
-- is derived from these parameters and should not need modification.
-- =============================================================================

SET
    TENANT = '<your-tenant>.us.qlikcloud.com'; -- Qlik Cloud hostname (no https:// prefix)
SET
    CLIENT_ID = '<your-oauth-client-id>'; -- From Qlik Management Console > OAuth
SET
    CLIENT_SECRET = '<your-oauth-client-secret>'; -- From Qlik Management Console > OAuth
SET 
    ALLOWED_ROLE  = 'QLIK_MCP_USER';  -- Role granted access (create this role first; avoid PUBLIC)
SET
    MCP_SERVER_NAME = 'qlik_mcp_server'; -- Name for the MCP server object
SET
    INTEGRATION_NAME = 'qlik_mcp_integration'; -- Name for the API integration object
SET
    AGENT_NAME = 'qlik_mcp'; -- Name for the Cortex Agent object

-- =============================================================================
-- Derived values (no changes needed below this line)
-- =============================================================================

SET MCP_URL = 'https://' || $TENANT || '/api/ai/mcp';

-- =============================================================================
-- Step 1: Create the API Integration (OAuth2)
-- =============================================================================
-- This integration stores OAuth credentials and authorizes Snowflake to call
-- the Qlik MCP endpoint. The API_PROVIDER = external_mcp tells Snowflake this
-- integration is specifically for MCP server communication.
-- =============================================================================

EXECUTE IMMEDIATE
$$
DECLARE
    v_tenant VARCHAR;
    v_client_id VARCHAR;
    v_client_secret VARCHAR;
    v_mcp_url VARCHAR;
    v_integration_name VARCHAR;
    sql_stmt VARCHAR;
BEGIN
    SELECT GETVARIABLE('TENANT') INTO v_tenant;
    SELECT GETVARIABLE('CLIENT_ID') INTO v_client_id;
    SELECT GETVARIABLE('CLIENT_SECRET') INTO v_client_secret;
    SELECT GETVARIABLE('INTEGRATION_NAME') INTO v_integration_name;
    v_mcp_url := 'https://' || v_tenant || '/api/ai/mcp';

    sql_stmt := 'CREATE OR REPLACE API INTEGRATION ' || v_integration_name
        || ' COMMENT = ''API integration for Qlik MCP server with OAuth2 authentication'''
        || ' API_PROVIDER = external_mcp'
        || ' API_ALLOWED_PREFIXES = (''' || v_mcp_url || ''')'
        || ' API_USER_AUTHENTICATION = ('
        || '   TYPE = OAUTH2'
        || '   OAUTH_CLIENT_ID = ''' || v_client_id || ''''
        || '   OAUTH_CLIENT_SECRET = ''' || v_client_secret || ''''
        || '   OAUTH_TOKEN_ENDPOINT = ''https://' || v_tenant || '/oauth/token'''
        || '   OAUTH_CLIENT_AUTH_METHOD = CLIENT_SECRET_POST'
        || '   OAUTH_AUTHORIZATION_ENDPOINT = ''https://' || v_tenant || '/oauth/authorize'''
        || '   OAUTH_REFRESH_TOKEN_VALIDITY = 86400'
        || '   OAUTH_ALLOWED_SCOPES = (''user_default'', ''mcp:execute'')'
        || ' )'
        || ' ENABLED = TRUE';
    EXECUTE IMMEDIATE sql_stmt;
END;
$$;

SHOW API INTEGRATIONS LIKE '%qlik%';

-- =============================================================================
-- Step 2: Create the External MCP Server
-- =============================================================================
-- The MCP server object is the Snowflake-side representation of the remote Qlik
-- MCP endpoint. It references the API integration for authentication and defines
-- the URL that Cortex Agents will call to invoke MCP tools.
-- =============================================================================

SET DISPLAY = 'Qlik MCP server ' || $TENANT;

EXECUTE IMMEDIATE
$$
DECLARE
    v_server_name VARCHAR;
    v_display VARCHAR;
    v_integration_name VARCHAR;
    v_mcp_url VARCHAR;
    v_allowed_role VARCHAR;
    sql_stmt VARCHAR;
BEGIN
    SELECT GETVARIABLE('MCP_SERVER_NAME') INTO v_server_name;
    SELECT GETVARIABLE('DISPLAY') INTO v_display;
    SELECT GETVARIABLE('INTEGRATION_NAME') INTO v_integration_name;
    SELECT GETVARIABLE('MCP_URL') INTO v_mcp_url;
    SELECT GETVARIABLE('ALLOWED_ROLE') INTO v_allowed_role;

    -- Escape single quotes in display name
    v_display := REPLACE(v_display, '''', '''''');

    sql_stmt := 'CREATE OR REPLACE EXTERNAL MCP SERVER ' || v_server_name
        || ' WITH DISPLAY_NAME = ''' || v_display || ''''
        || ' API_INTEGRATION = ' || v_integration_name;
    EXECUTE IMMEDIATE sql_stmt;

    EXECUTE IMMEDIATE 'ALTER EXTERNAL MCP SERVER ' || v_server_name || ' SET URL = ''' || v_mcp_url || '''';

    EXECUTE IMMEDIATE 'GRANT USAGE ON INTEGRATION ' || v_integration_name || ' TO ROLE IDENTIFIER(''' || v_allowed_role || ''')';
    EXECUTE IMMEDIATE 'GRANT USAGE ON MCP SERVER ' || v_server_name || ' TO ROLE IDENTIFIER(''' || v_allowed_role || ''')';
END;
$$;

-- =============================================================================
-- Step 3: Verification
-- =============================================================================
-- Confirm that both the integration and MCP server were created successfully.
-- =============================================================================

SHOW EXTERNAL MCP SERVERS;
DESCRIBE EXTERNAL MCP SERVER IDENTIFIER($MCP_SERVER_NAME);
SHOW API INTEGRATIONS LIKE '%qlik%';

-- =============================================================================
-- Step 4: Create a Cortex Agent wired to the Qlik MCP Server
-- =============================================================================
-- This creates a Cortex Agent with instructions for using Qlik MCP tools,
-- sets a display name for the Snowflake Intelligence UI, and registers
-- the agent with Snowflake Intelligence so it appears in the agent picker.
-- =============================================================================

SET AGENT_MCP_REF = CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() || '.' || $MCP_SERVER_NAME;
SET AGENT_FQN = CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() || '.' || $AGENT_NAME;
SET AGENT_DISPLAY_NAME = 'Qlik MCP ' || $TENANT;

EXECUTE IMMEDIATE
$$
DECLARE
    v_agent_fqn VARCHAR;
    v_agent_mcp_ref VARCHAR;
    v_agent_display_name VARCHAR;
    v_allowed_role VARCHAR;
    sql_stmt VARCHAR;
    spec VARCHAR;
BEGIN
    SELECT GETVARIABLE('AGENT_FQN') INTO v_agent_fqn;
    SELECT GETVARIABLE('AGENT_MCP_REF') INTO v_agent_mcp_ref;
    SELECT GETVARIABLE('AGENT_DISPLAY_NAME') INTO v_agent_display_name;
    SELECT GETVARIABLE('ALLOWED_ROLE') INTO v_allowed_role;

    -- Escape single quotes in display name
    v_agent_display_name := REPLACE(v_agent_display_name, '''', '''''');

    spec := 'models:\n'
        || '  orchestration: auto\n'
        || 'instructions:\n'
        || '  response: |\n'
        || '    You are a Qlik-powered analytics agent. You have access to the Qlik MCP server tools\n'
        || '    to help users discover, explore, analyze, and visualize data in Qlik Cloud applications.\n'
        || '\n'
        || '    Use the appropriate Qlik MCP tools based on the user''s request. Below is a summary\n'
        || '    of available tool categories and how to use them.\n'
        || '\n'
        || '    ## Available Qlik MCP Tool Categories\n'
        || '\n'
        || '    ### 1. App Discovery & Metadata\n'
        || '    Find applications, explore structure, understand what data is available.\n'
        || '    Tools: qlik_search, qlik_describe_app, qlik_get_fields, qlik_list_sheets,\n'
        || '           qlik_get_sheet_details, qlik_search_spaces\n'
        || '\n'
        || '    Workflow example:\n'
        || '    - Use qlik_search to find applications related to a topic.\n'
        || '    - Use qlik_describe_app to confirm it''s the correct application.\n'
        || '    - Use qlik_get_fields to list available fields (dimensions/measures).\n'
        || '    - Use qlik_list_sheets to see existing dashboards.\n'
        || '    - Use qlik_get_sheet_details to summarize charts on a sheet.\n'
        || '\n'
        || '    ### 2. Bookmarks\n'
        || '    View, create, apply, and delete bookmarks (saved selection states).\n'
        || '    Tools: qlik_list_bookmarks, qlik_create_bookmark, qlik_select_bookmark, qlik_delete_bookmark\n'
        || '\n'
        || '    Note: You can only delete bookmarks created using Qlik MCP tools.\n'
        || '\n'
        || '    ### 3. Business Glossary\n'
        || '    Manage business terms, definitions, categories, and linkages to data assets.\n'
        || '    Tools: qlik_create_glossary, qlik_get_full_glossary_export, qlik_get_glossary_categories,\n'
        || '           qlik_create_glossary_category, qlik_search_glossary_terms, qlik_get_glossary_term,\n'
        || '           qlik_create_glossary_term, qlik_update_glossary_term, qlik_delete_glossary_term,\n'
        || '           qlik_update_term_status, qlik_get_glossary_term_links, qlik_create_glossary_term_links\n'
        || '\n'
        || '    Term statuses (case-sensitive): draft, verified, deprecated.\n'
        || '    Only a steward can verify a term. Once verified, only a steward can modify it.\n'
        || '\n'
        || '    ### 4. Datasets & Data Quality\n'
        || '    Inspect datasets, schemas, profiles, trust scores, and quality metrics.\n'
        || '    Tools: qlik_get_dataset, qlik_get_dataset_schema, qlik_get_dataset_profile,\n'
        || '           qlik_get_dataset_sample, qlik_get_dataset_freshness, qlik_get_dataset_trust_score,\n'
        || '           qlik_get_dataset_memberships, qlik_update_dataset_metadata,\n'
        || '           qlik_update_dataset_quality, qlik_get_dataset_quality_computation_status\n'
        || '\n'
        || '    ### 5. Data Exploration & Analysis\n'
        || '    Query data, build calculations, explore field values.\n'
        || '    Tools: qlik_create_data_object, qlik_get_field_values, qlik_search_field_values,\n'
        || '           qlik_get_chart_data, qlik_get_chart_info\n'
        || '\n'
        || '    IMPORTANT RULES:\n'
        || '    - Qlik performs ALL calculations. Never aggregate or compute on returned data.\n'
        || '    - For different calculations, call the tool again with new expressions.\n'
        || '    - Always apply filters/selections to limit data size.\n'
        || '    - Always use qlik_get_field_values or qlik_search_field_values BEFORE applying\n'
        || '      selections to verify values exist.\n'
        || '    - For high cardinality fields, use qlik_search_field_values instead of qlik_get_field_values.\n'
        || '    - For single analytical queries, prefer set analysis over app-level selections.\n'
        || '\n'
        || '    ### 6. Data Products\n'
        || '    Create, manage, activate, and distribute curated data products.\n'
        || '    Tools: qlik_create_data_product, qlik_get_data_product, qlik_get_data_product_documentation,\n'
        || '           qlik_update_data_product, qlik_update_data_product_space,\n'
        || '           qlik_update_activate_data_product, qlik_update_deactivate_data_product,\n'
        || '           qlik_delete_data_product\n'
        || '\n'
        || '    ### 7. Knowledge Bases\n'
        || '    Search knowledge bases and use their contents to get answers.\n'
        || '    Tools: qlik_search_knowledgebase_chunks\n'
        || '\n'
        || '    ### 8. Lineage\n'
        || '    Trace data origins and transformations. Call recursively for full chain.\n'
        || '    Tools: qlik_get_lineage\n'
        || '\n'
        || '    ### 9. Master Items (Dimensions & Measures)\n'
        || '    Manage reusable governed dimensions and measures.\n'
        || '    Tools: qlik_list_dimensions, qlik_create_dimension, qlik_update_dimension,\n'
        || '           qlik_delete_dimension, qlik_list_measures, qlik_create_measure,\n'
        || '           qlik_update_measure, qlik_delete_measure\n'
        || '\n'
        || '    Note: You can only update/delete master items created using Qlik MCP tools.\n'
        || '\n'
        || '    ### 10. Selections & Filtering\n'
        || '    Apply and manage filters that affect all visualizations.\n'
        || '    Tools: qlik_select_values, qlik_clear_selections, qlik_get_current_selections\n'
        || '\n'
        || '    IMPORTANT RULES:\n'
        || '    - Selections persist across all operations until cleared.\n'
        || '    - Always verify values exist before selecting (use qlik_get_field_values or qlik_search_field_values).\n'
        || '    - For single analytical queries, prefer set analysis in expressions over app-level selections.\n'
        || '    - When to use selections: filtering the entire app for multiple subsequent operations.\n'
        || '    - When to use set analysis: one-time filter for a specific calculation.\n'
        || '\n'
        || '    ### 11. Visualization & Sheets\n'
        || '    Create dashboards and add charts, filters, KPIs.\n'
        || '    Tools: qlik_create_sheet, qlik_add_chart, qlik_add_filter\n'
        || '\n'
        || '    Best practices:\n'
        || '    - Test date/value existence with qlik_search_field_values first.\n'
        || '    - Use set analysis over app-level selections for one-off queries.\n'
        || '\n'
        || '    ## General Best Practices\n'
        || '    1. Always start by discovering available apps with qlik_search.\n'
        || '    2. Verify field values exist before using them in selections or set analysis.\n'
        || '    3. Let Qlik handle all calculations - never re-aggregate returned data.\n'
        || '    4. Use selections for persistent cross-operation filters; use set analysis for one-off queries.\n'
        || '    5. Clear selections when done to avoid affecting subsequent operations.\n'
        || '    6. For lineage, call qlik_get_lineage recursively to build the full upstream chain.\n'
        || '\n'
        || '  orchestration: |\n'
        || '    Use the Qlik MCP tools to answer questions about data, analytics, and visualizations.\n'
        || '    Follow the best practices outlined in the response instructions.\n'
        || '    When exploring data, always verify field values before applying selections.\n'
        || 'mcp_servers:\n'
        || '  - server_spec:\n'
        || '      name: "' || v_agent_mcp_ref || '"\n';

    sql_stmt := 'CREATE OR REPLACE AGENT ' || v_agent_fqn
        || ' COMMENT = ''Qlik MCP agent for Snowflake Intelligence'''
        || ' FROM SPECIFICATION $$ ' || spec || ' $$';
    EXECUTE IMMEDIATE sql_stmt;

    -- Set the agent display name for Snowflake Intelligence
    sql_stmt := 'ALTER AGENT ' || v_agent_fqn || ' SET PROFILE = ''{"display_name": "' || v_agent_display_name || '"}''';
    EXECUTE IMMEDIATE sql_stmt;

    -- Add agent to Snowflake Intelligence
    EXECUTE IMMEDIATE 'CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT';
    EXECUTE IMMEDIATE 'ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT ' || v_agent_fqn;
    EXECUTE IMMEDIATE 'GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE IDENTIFIER(''' || v_allowed_role || ''')';
END;
$$;

-- =============================================================================
-- Step 5: User Authentication (manual, per-user)
-- =============================================================================
-- Each user who wants to use the Qlik MCP tools must complete the OAuth flow
-- once. This opens a browser window to authenticate with Qlik Cloud.
--
-- Run this in a worksheet:
--   SELECT SYSTEM$START_USER_OAUTH_FLOW('<INTEGRATION_NAME>');
--
-- After authenticating, new MCP tools become available in the agent. If tools
-- are added to the Qlik MCP server later, users must sign out and back in to
-- refresh their available tool set.
-- =============================================================================

