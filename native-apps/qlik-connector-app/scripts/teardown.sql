-- =============================================================================
-- Teardown: Qlik Connector App
-- =============================================================================
--
-- Removes every object created by the README install steps and scripts/consumer_setup.sql.
-- Set the parameters below to the SAME values you used in setup, then run the
-- whole script. Every statement uses IF EXISTS, so it is safe to re-run.
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

SET APP_NAME     = 'my_app';   -- installed application
SET PACKAGE_NAME = 'my_app_pkg';   -- provider-side application package
SET DROP_PACKAGE = TRUE;         -- set FALSE on a consumer account (no package there)

-- CASCADE also drops objects the app created outside itself
DROP APPLICATION IF EXISTS IDENTIFIER($APP_NAME) CASCADE;

EXECUTE IMMEDIATE
$$
BEGIN
    IF (GETVARIABLE('DROP_PACKAGE')::BOOLEAN) THEN
        EXECUTE IMMEDIATE 'DROP APPLICATION PACKAGE IF EXISTS ' || GETVARIABLE('PACKAGE_NAME');
    END IF;
END;
$$;
