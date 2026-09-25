-- =============================================================================
-- Qlik Automate → Snowflake Cortex Agent Orchestration
-- =============================================================================
--
-- Creates a Cortex Agent that checks data freshness across Qlik-managed tables
-- and answers with one machine-readable JSON object, plus a procedure that
-- Qlik Automate calls to run the agent and get the result back as flat columns.
--
-- What is created (in TARGET_DATABASE.TARGET_SCHEMA):
--   - Table      FRESHNESS_AUDIT_LOG            one row per freshness check
--   - Agent      <AGENT_NAME>                   the freshness agent
--   - Procedure  RUN_FRESHNESS_CHECK(...)       runs the agent, extracts its
--                                               JSON, writes the audit row, and
--                                               returns STATUS / counts
--   - Snowflake Intelligence registration (optional, commented out)
--
-- How Qlik Automate uses it:
--   The workflow's Snowflake connector block runs
--     CALL <db>.<schema>.RUN_FRESHNESS_CHECK('<agent fqn>', '<schema to check>', <sla hours>);
--   and branches on the returned STATUS column ('ok' | 'breach' | 'error').
--   Parsing happens here, in SQL, because the agent's JSON arrives as text
--   inside the agent response envelope, which is awkward to unpack in Automate.
--
--   You can also call the agent directly over the REST API
--   (POST /api/v2/databases/{db}/schemas/{schema}/agents/{agent}:run) with a
--   Programmatic Access Token; see Step 6. You then have to extract the JSON
--   from the final message text yourself.
--
-- Architecture:
--
--   Trigger (schedule, webhook, or Qlik event such as an app reload)
--     |
--     v
--   Qlik Automate workflow
--     |-- Snowflake connector: CALL RUN_FRESHNESS_CHECK(...)
--     |      |-- DATA_AGENT_RUN → Cortex Agent (INFORMATION_SCHEMA, TASK_HISTORY)
--     |      |-- extract the JSON answer, INSERT into FRESHNESS_AUDIT_LOG
--     |      '-- return STATUS, TOTAL_TABLES, TABLES_OK, TABLES_BREACHED, ...
--     |-- Branch on STATUS
--     |     |-- ok     → done
--     |     |-- breach → notify (Slack/Teams/email) + reload the Qlik app
--     |     '-- error  → notify that the check itself failed
--     v
--   Done
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - For the role that runs the check (the Qlik Automate service user's role):
--       SNOWFLAKE.CORTEX_USER database role, USAGE on the agent and procedure,
--       INSERT on FRESHNESS_AUDIT_LOG, read access to the monitored schemas'
--       INFORMATION_SCHEMA and to SNOWFLAKE.ACCOUNT_USAGE, a default warehouse
--   - Qlik Cloud tenant with Qlik Automate enabled
--
-- References:
--   - DATA_AGENT_RUN: https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex
--   - Cortex Agent REST API: POST /api/v2/databases/{db}/schemas/{schema}/agents/{name}:run
--   - Qlik Automate docs: https://help.qlik.com/en-US/cloud-services/Subsystems/Hub/Content/Sense_QlikAutomation/introduction/home-automation.htm
--
-- =============================================================================

-- =============================================================================
-- Step 0: Configuration Parameters
-- =============================================================================
-- NOTE: The test calls below and the defaults in qlik-automate-workflow.json
-- use CORTEX_CODE.PUBLIC. Update them too if you change these values.

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';
SET AGENT_NAME      = 'QLIK_AUTOMATE_FRESHNESS_AGENT';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

-- =============================================================================
-- Step 1: Create the audit table
-- =============================================================================
-- RUN_FRESHNESS_CHECK writes one row here per run: a history of freshness
-- checks for dashboards and trend analysis.
-- =============================================================================

CREATE TABLE IF NOT EXISTS FRESHNESS_AUDIT_LOG (
    run_id          STRING DEFAULT UUID_STRING(),
    run_timestamp   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source          STRING DEFAULT 'qlik_automate',
    schema_checked  STRING,
    sla_hours       NUMBER(10,2),
    total_tables    NUMBER,
    tables_ok       NUMBER,
    tables_breached NUMBER,
    breached_tables VARIANT,
    agent_response  VARIANT      -- parsed agent JSON, or the raw response if parsing failed
);

-- =============================================================================
-- Step 2: Create the Cortex Agent
-- =============================================================================
-- The agent is built for machine consumption: its final answer is a single
-- JSON object with a fixed schema.
-- =============================================================================

CREATE OR REPLACE AGENT IDENTIFIER($TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME)
  COMMENT = 'Freshness SLA agent designed for Qlik Automate orchestration — returns structured JSON'
  PROFILE = '{"display_name": "Qlik Automate Freshness", "color": "orange"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake data freshness monitor designed to be called by
      Qlik Automate workflows. Your responses MUST be machine-parseable.

      CRITICAL: Always return your final answer as a single JSON object
      with this exact schema:

      {
        "status": "ok" | "breach",
        "schema_checked": "<database>.<schema>",
        "sla_hours": <number>,
        "checked_at": "<ISO 8601 timestamp>",
        "summary": {
          "total_tables": <number>,
          "tables_ok": <number>,
          "tables_breached": <number>
        },
        "tables": [
          {
            "table_name": "<name>",
            "last_altered": "<ISO 8601>",
            "hours_stale": <number>,
            "sla_status": "ok" | "breach",
            "row_count": <number>
          }
        ],
        "breaches": [
          {
            "table_name": "<name>",
            "hours_stale": <number>,
            "cause": "task_failed" | "task_suspended" | "no_task" | "unknown",
            "task_name": "<name or null>",
            "error_message": "<message or null>",
            "remediation_sql": "<SQL statement>"
          }
        ]
      }

      Workflow:
      1. Parse the user message to extract: target schema and SLA threshold hours.
      2. Query INFORMATION_SCHEMA.TABLES for TABLE_NAME, ROW_COUNT, LAST_ALTERED.
      3. Compute hours since last alteration for each table.
      4. Flag tables where staleness exceeds the SLA threshold.
      5. For breached tables, find the most recent task runs targeting that
         schema. Use the INFORMATION_SCHEMA.TASK_HISTORY() table function for
         the last few hours (it is real-time), and
         SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY for older runs (it lags by up to
         about 45 minutes).
      6. Check SHOW TASKS IN SCHEMA for suspended tasks.
      7. Build the JSON response with remediation SQL for each breach.

      IMPORTANT:
      - Output only the JSON object: no prose, no commentary, no Markdown fences.
      - The "status" field is "breach" if ANY table exceeds the SLA, "ok" otherwise.
      - Always include ALL tables in the "tables" array, not just breached ones.
      - Use CURRENT_TIMESTAMP() for the checked_at field.

    sample_questions:
      - question: "Check freshness for ANALYTICS.PUBLIC with a 4-hour SLA."
      - question: "Monitor STAGING.RAW with a 1-hour SLA."
      - question: "Check all tables in REPORTING.QLIK_MANAGED with a 2-hour SLA."

  tools:
    - tool_spec:
        type: code_toolset_all
        name: code_toolset_all

  tool_resources:
    code_toolset_all:
      permission_policy:
        type: always_allow
  $$;

-- =============================================================================
-- Step 3: Create the procedure Qlik Automate calls
-- =============================================================================
-- RUN_FRESHNESS_CHECK(AGENT_FQN, TARGET_SCHEMA, SLA_HOURS)
--   1. Sends the agent the same request body the REST API would.
--   2. Finds the agent's JSON answer. It is text somewhere inside the response
--      envelope, so the procedure scans every "text" value, cuts out the
--      {...} object, and keeps the one that parses and has a "status" field.
--   3. Inserts one row into FRESHNESS_AUDIT_LOG (next to the agent).
--   4. Returns one row of flat columns. STATUS is 'error' when no valid JSON
--      answer was found; AGENT_JSON then holds the raw response for debugging.
--
-- Runs with caller's rights, so the agent's SQL runs as the calling role (the
-- Qlik Automate service user), not as the procedure owner.
-- =============================================================================

CREATE OR REPLACE PROCEDURE RUN_FRESHNESS_CHECK(
    AGENT_FQN     VARCHAR,   -- e.g. 'CORTEX_CODE.PUBLIC.QLIK_AUTOMATE_FRESHNESS_AGENT'
    TARGET_SCHEMA VARCHAR,   -- schema to check, e.g. 'ANALYTICS.PUBLIC'
    SLA_HOURS     FLOAT      -- maximum acceptable staleness in hours
)
RETURNS TABLE (
    STATUS          VARCHAR,
    TOTAL_TABLES    NUMBER,
    TABLES_OK       NUMBER,
    TABLES_BREACHED NUMBER,
    BREACHES        VARCHAR,
    AGENT_JSON      VARCHAR
)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_request  VARCHAR;
    v_response VARIANT;
    v_json     VARIANT;
    v_audit    VARCHAR;
    res        RESULTSET;
BEGIN
    v_request := TO_JSON(OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
        'role', 'user',
        'content', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT(
            'type', 'text',
            'text', 'Check freshness for ' || TARGET_SCHEMA || ' with a '
                    || SLA_HOURS || '-hour SLA.'))))));

    SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(:AGENT_FQN, :v_request))
      INTO :v_response;

    -- Longest candidate wins, in case earlier text (e.g. a draft) also parsed.
    SELECT MAX_BY(j, LENGTH(TO_JSON(j)))
      INTO :v_json
      FROM (
        SELECT TRY_PARSE_JSON(REGEXP_SUBSTR(f.value::VARCHAR, '\\{.*\\}', 1, 1, 's')) AS j
          FROM TABLE(FLATTEN(input => :v_response, recursive => TRUE)) f
         WHERE f.key = 'text'
           AND IS_VARCHAR(f.value)
      )
     WHERE j:status IS NOT NULL;

    -- The audit table lives in the same schema as the agent.
    v_audit := SPLIT_PART(AGENT_FQN, '.', 1) || '.' || SPLIT_PART(AGENT_FQN, '.', 2)
               || '.FRESHNESS_AUDIT_LOG';

    INSERT INTO IDENTIFIER(:v_audit)
        (schema_checked, sla_hours, total_tables, tables_ok, tables_breached,
         breached_tables, agent_response)
    SELECT :TARGET_SCHEMA,
           :SLA_HOURS,
           j:summary:total_tables::NUMBER,
           j:summary:tables_ok::NUMBER,
           j:summary:tables_breached::NUMBER,
           j:breaches,
           COALESCE(j, :v_response)
      FROM (SELECT :v_json AS j);

    res := (
        SELECT COALESCE(j:status::VARCHAR, 'error')  AS STATUS,
               j:summary:total_tables::NUMBER        AS TOTAL_TABLES,
               j:summary:tables_ok::NUMBER           AS TABLES_OK,
               j:summary:tables_breached::NUMBER     AS TABLES_BREACHED,
               TO_JSON(j:breaches)                   AS BREACHES,
               TO_JSON(COALESCE(j, :v_response))     AS AGENT_JSON
          FROM (SELECT :v_json AS j)
    );
    RETURN TABLE(res);
END;
$$;

-- Grant the Qlik Automate service role what it needs (replace the role name):
-- GRANT USAGE ON AGENT QLIK_AUTOMATE_FRESHNESS_AGENT TO ROLE <service_role>;
-- GRANT USAGE ON PROCEDURE RUN_FRESHNESS_CHECK(VARCHAR, VARCHAR, FLOAT) TO ROLE <service_role>;
-- GRANT INSERT, SELECT ON TABLE FRESHNESS_AUDIT_LOG TO ROLE <service_role>;

-- =============================================================================
-- Step 4: Register with Snowflake Intelligence (optional)
-- =============================================================================
-- Skip this step if the agent is only used by Qlik Automate.
-- =============================================================================

-- CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
-- ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
--   ADD AGENT QLIK_AUTOMATE_FRESHNESS_AGENT;

-- =============================================================================
-- Step 5: Test (the same call the Qlik Automate workflow makes)
-- =============================================================================
-- Returns one row; STATUS should be 'ok' or 'breach', and a new row appears
-- in FRESHNESS_AUDIT_LOG.

-- CALL CORTEX_CODE.PUBLIC.RUN_FRESHNESS_CHECK(
--   'CORTEX_CODE.PUBLIC.QLIK_AUTOMATE_FRESHNESS_AGENT', 'ANALYTICS.PUBLIC', 4);
--
-- SELECT * FROM CORTEX_CODE.PUBLIC.FRESHNESS_AUDIT_LOG ORDER BY run_timestamp DESC LIMIT 5;

-- =============================================================================
-- Step 6 (alternative): Call the agent directly over the REST API
-- =============================================================================
-- For callers other than the procedure. Replace $SNOWFLAKE_ACCOUNT_URL
-- (https://<account>.snowflakecomputing.com) and $PAT (a Programmatic Access
-- Token). "stream": false returns one JSON document instead of server-sent
-- events; the agent's answer is the text of the final message in it.
-- =============================================================================

-- curl -X POST "$SNOWFLAKE_ACCOUNT_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/QLIK_AUTOMATE_FRESHNESS_AGENT:run" \
--   --header 'Content-Type: application/json' \
--   --header 'Accept: application/json' \
--   --header "Authorization: Bearer $PAT" \
--   --data '{
--     "stream": false,
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Check freshness for ANALYTICS.PUBLIC with a 4-hour SLA."
--           }
--         ]
--       }
--     ]
--   }'
