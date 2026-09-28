-- =============================================================================
-- Teardown: Qlik MCP examples
-- =============================================================================
--
-- Removes every object created by the create-*.sql scripts in this folder.
-- Drop the agents first; the MCP server and integration from
-- create-mcp-agent.sql are shared by all of them, so they are dropped last.
-- Leave an agent name as-is if you never ran that script.
-- Set the parameters below to the SAME values you used in setup, then run the
-- whole script. Every statement uses IF EXISTS, so it is safe to re-run.
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

SET TARGET_DATABASE = '<your-database>';
SET TARGET_SCHEMA   = '<your-schema>';

-- Agent names (defaults from each create-*.sql script)
SET QLIK_MCP_AGENT     = 'qlik_mcp';            -- create-mcp-agent.sql
SET DUAL_SOURCE_AGENT  = 'DUAL_SOURCE_AGENT';   -- create-dual-source-agent.sql
SET MCP_FIRST_AGENT    = 'MCP_FIRST_AGENT';     -- create-mcp-first-fallback-agent.sql
SET MULTI_MCP_AGENT    = 'MULTI_MCP_AGENT';     -- create-multi-mcp-agent.sql

-- Shared objects from create-mcp-agent.sql
SET MCP_SERVER_NAME  = 'qlik_mcp_server';
SET INTEGRATION_NAME = 'qlik_mcp_integration';
SET DROP_SHARED      = TRUE;   -- set FALSE to keep the MCP server + integration

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

EXECUTE IMMEDIATE
$$
DECLARE
    v_prefix VARCHAR DEFAULT GETVARIABLE('TARGET_DATABASE') || '.' || GETVARIABLE('TARGET_SCHEMA') || '.';
    v_agents ARRAY DEFAULT ARRAY_CONSTRUCT(
        GETVARIABLE('QLIK_MCP_AGENT'), GETVARIABLE('DUAL_SOURCE_AGENT'),
        GETVARIABLE('MCP_FIRST_AGENT'), GETVARIABLE('MULTI_MCP_AGENT'));
    v_fqn VARCHAR;
BEGIN
    FOR i IN 0 TO ARRAY_SIZE(v_agents) - 1 DO
        v_fqn := v_prefix || v_agents[i]::VARCHAR;
        BEGIN
            EXECUTE IMMEDIATE 'ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT ' || v_fqn;
        EXCEPTION
            WHEN OTHER THEN NULL;
        END;
        EXECUTE IMMEDIATE 'DROP AGENT IF EXISTS ' || v_fqn;
    END FOR;

    IF (GETVARIABLE('DROP_SHARED')::BOOLEAN) THEN
        EXECUTE IMMEDIATE 'DROP EXTERNAL MCP SERVER IF EXISTS ' || v_prefix || GETVARIABLE('MCP_SERVER_NAME');
        EXECUTE IMMEDIATE 'DROP API INTEGRATION IF EXISTS ' || GETVARIABLE('INTEGRATION_NAME');
    END IF;
    RETURN 'teardown complete';
END;
$$;
