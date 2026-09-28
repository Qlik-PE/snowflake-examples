-- =============================================================================
-- Teardown: Qlik Automate agent orchestration
-- =============================================================================
--
-- Removes every object created by setup.sql.
-- Set the parameters below to the SAME values you used in setup, then run the
-- whole script. Every statement uses IF EXISTS, so it is safe to re-run.
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';
SET AGENT_NAME      = 'QLIK_AUTOMATE_FRESHNESS_AGENT';
SET DROP_AUDIT_LOG  = FALSE;   -- set TRUE to also delete FRESHNESS_AUDIT_LOG history

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

DROP PROCEDURE IF EXISTS RUN_FRESHNESS_CHECK(VARCHAR, VARCHAR, FLOAT);
DROP AGENT IF EXISTS IDENTIFIER($AGENT_FQN);

EXECUTE IMMEDIATE
$$
BEGIN
    IF (GETVARIABLE('DROP_AUDIT_LOG')::BOOLEAN) THEN
        DROP TABLE IF EXISTS FRESHNESS_AUDIT_LOG;
    END IF;
END;
$$;

-- Also delete or disable the imported workflow in Qlik Automate.
