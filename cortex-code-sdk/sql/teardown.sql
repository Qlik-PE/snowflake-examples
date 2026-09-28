-- =============================================================================
-- Teardown: Cortex Code SDK SQL agents
-- =============================================================================
--
-- Removes every object created by the *-agent.sql scripts in this folder.
-- Set the parameters below to the SAME values you used in setup, then run the
-- whole script. Every statement uses IF EXISTS, so it is safe to re-run.
--
-- =============================================================================

SET TARGET_ROLE     = 'ACCOUNTADMIN';
SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE ROLE IDENTIFIER($TARGET_ROLE);
USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

-- Only DOC_INTELLIGENCE offers (optional) Snowflake Intelligence registration
SET DOC_AGENT_FQN = $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.DOC_INTELLIGENCE';
-- Unregister from Snowflake Intelligence (ignored if it was never registered)
EXECUTE IMMEDIATE
$$
BEGIN
    EXECUTE IMMEDIATE 'ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT '
        || GETVARIABLE('DOC_AGENT_FQN');
EXCEPTION
    WHEN OTHER THEN NULL;
END;
$$;

DROP AGENT IF EXISTS ACCESS_AUDIT_AGENT;
DROP AGENT IF EXISTS DATA_FRESHNESS_AGENT;
DROP AGENT IF EXISTS DOC_INTELLIGENCE;
DROP AGENT IF EXISTS PREFLIGHT_VALIDATOR_AGENT;
DROP AGENT IF EXISTS RCA_AGENT;
DROP AGENT IF EXISTS SEMANTIC_DRIFT_AGENT;
DROP AGENT IF EXISTS SQL_OPTIMIZER_AGENT;
DROP AGENT IF EXISTS WORKLOAD_COST_AGENT;
