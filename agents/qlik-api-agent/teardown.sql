-- =============================================================================
-- Teardown: Qlik API Agent
-- =============================================================================
--
-- Removes every object created by setup.sql.
-- Set the parameters below to the SAME values you used in setup, then run the
-- whole script. Every statement uses IF EXISTS, so it is safe to re-run.
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

SET TARGET_DB     = '<your-database>';
SET TARGET_SCHEMA = 'PUBLIC';

SET AGENT_FQN = $TARGET_DB || '.' || $TARGET_SCHEMA || '.QLIK_API_AGENT';
USE DATABASE IDENTIFIER($TARGET_DB);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

-- Unregister from Snowflake Intelligence (ignored if it was never registered)
EXECUTE IMMEDIATE
$$
BEGIN
    EXECUTE IMMEDIATE 'ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT '
        || GETVARIABLE('AGENT_FQN');
EXCEPTION
    WHEN OTHER THEN NULL;
END;
$$;

DROP AGENT IF EXISTS QLIK_API_AGENT;

DROP PROCEDURE IF EXISTS CREATE_QLIK_APP(VARCHAR, VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS SET_QLIK_APP_SCRIPT(VARCHAR, VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS GET_SEMANTIC_VIEW_DDL(VARCHAR);
DROP PROCEDURE IF EXISTS GET_TABLE_COLUMNS(VARCHAR, VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS CREATE_QLIK_DATASET(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS LINK_GLOSSARY_TO_DATA_PRODUCT(VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS RELOAD_QLIK_APP(VARCHAR);

DROP STAGE IF EXISTS AGENT_SKILLS_STAGE;

-- The integration must go before the secrets and network rule it references
DROP INTEGRATION IF EXISTS QLIK_CLOUD_EAI;
DROP SECRET IF EXISTS QLIK_API_KEY_SECRET;
DROP SECRET IF EXISTS QLIK_TENANT_SECRET;
DROP NETWORK RULE IF EXISTS QLIK_CLOUD_NETWORK_RULE;

-- The Qlik MCP server referenced by QLIK_MCP_SERVER is NOT dropped here;
-- remove it with mcp/teardown.sql if you no longer need it.
