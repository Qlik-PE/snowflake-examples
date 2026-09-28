-- =============================================================================
-- Teardown: Cortex Search RAG demo
-- =============================================================================
--
-- Removes every object created by cortex-search-rag.sql (cortex-ai-functions.sql uses only a
-- temporary table and cortex-agent-token-usage.sql creates nothing).
-- Set the parameters below to the SAME values you used in setup, then run the
-- whole script. Every statement uses IF EXISTS, so it is safe to re-run.
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

SET TARGET_DATABASE = 'CORTEX_DEMOS';
SET TARGET_SCHEMA   = 'PUBLIC';
SET AGENT_NAME      = 'PRODUCT_DOCS_AGENT';

SET AGENT_FQN = $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME;
USE DATABASE IDENTIFIER($TARGET_DATABASE);
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

DROP AGENT IF EXISTS IDENTIFIER($AGENT_FQN);
DROP CORTEX SEARCH SERVICE IF EXISTS product_docs_search;
DROP TABLE IF EXISTS product_docs;
