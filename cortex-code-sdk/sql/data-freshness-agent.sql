-- =============================================================================
-- Data Freshness SLA Monitor Agent (Cortex Agent + REST API)
-- =============================================================================
--
-- SQL equivalent of coco-agent-sdk/data_freshness_agent.py.
--
-- Checks whether Qlik-managed tables in Snowflake meet their freshness SLAs.
-- Queries INFORMATION_SCHEMA and table metadata to compute staleness, then
-- diagnoses root causes by cross-referencing TASK_HISTORY.
--
-- SDK version:  Multi-turn CortexCodeSDKClient (turn 1: discover tables,
--               turn 2: diagnose root causes) with structured output
-- This version: CREATE AGENT with code_toolset_all, callable via REST API
--               or DATA_AGENT_RUN SQL function. Multi-turn is handled by
--               passing thread_id across consecutive REST API calls.
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Access to INFORMATION_SCHEMA and SNOWFLAKE.ACCOUNT_USAGE views
--
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

CREATE OR REPLACE AGENT IDENTIFIER($TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.DATA_FRESHNESS_AGENT')
  COMMENT = 'Monitors data freshness SLAs and diagnoses why Qlik-managed tables are stale'
  PROFILE = '{"display_name": "Freshness SLA", "color": "yellow"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake data operations specialist embedded inside a Qlik
      integration. Your job is to monitor data freshness across Snowflake tables
      that Qlik pipelines populate, detect SLA violations, and diagnose why
      tables are stale.

      You have access to INFORMATION_SCHEMA, SNOWFLAKE.ACCOUNT_USAGE, and can
      query task history. Always ground analysis in actual metadata timestamps.

      Freshness monitoring workflow:
      1. List all tables in the target schema using INFORMATION_SCHEMA.TABLES.
         Get TABLE_NAME, ROW_COUNT, LAST_ALTERED (or LAST_DDL).
      2. For each table, compute hours since last alteration.
      3. Compare against the SLA threshold (default: 4 hours unless specified).
      4. Flag any table where staleness exceeds the SLA.
      5. For stale tables, check SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY for tasks
         targeting the schema. Look at the most recent runs.
      6. Check if any tasks are suspended (SHOW TASKS IN SCHEMA).
      7. If a task failed, include the error message.
      8. If no task exists for a stale table, note "no_task" as the cause.
      9. Produce remediation SQL (e.g., RESUME TASK, ALTER TASK SET SCHEDULE).

    response: |
      Present a structured freshness report:
      - Summary: total tables checked, how many meet SLA, how many violate.
      - Per-table details: name, last altered, hours stale, SLA status, row count.
      - Root causes for each SLA violation: cause type, task name, last run, error.
      - Remediation SQL for each stale table.

    sample_questions:
      - question: "Check data freshness for all tables in ANALYTICS.PUBLIC with a 4-hour SLA."
      - question: "Are any tables in STAGING.RAW more than 1 hour stale? Diagnose why."
      - question: "Monitor freshness for tables tagged QLIK_MANAGED in PROD.WAREHOUSE with a 2-hour SLA."
      - question: "Which tables in REPORTING.PUBLIC haven't been updated today? Check if their tasks are suspended."

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
-- Step 2: Call the agent
-- =============================================================================

-- Option A: SQL via DATA_AGENT_RUN
--
-- SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--   'CORTEX_CODE.PUBLIC.DATA_FRESHNESS_AGENT',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Check data freshness for all tables in ANALYTICS.PUBLIC with a 4-hour SLA."
--           }
--         ]
--       }
--     ]
--   }
--   $$,
--   TRUE
-- ) AS response;

-- Option B: REST API via curl (streaming SSE)
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/DATA_FRESHNESS_AGENT:run" \
--   --header 'Content-Type: application/json' \
--   --header 'Accept: text/event-stream' \
--   --header "Authorization: Bearer $PAT" \
--   --data '{
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Check data freshness for all tables in ANALYTICS.PUBLIC with a 4-hour SLA."
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — background run (for long-running freshness checks)
-- Set "background": true for checks that may exceed the 15-minute timeout.
-- The response returns immediately with a run_id; reconnect with the
-- Stream Agent Run endpoint to retrieve results.
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/DATA_FRESHNESS_AGENT:run" \
--   --header 'Content-Type: application/json' \
--   --header 'Accept: text/event-stream' \
--   --header "Authorization: Bearer $PAT" \
--   --data '{
--     "thread_id": 0,
--     "parent_message_id": 0,
--     "background": true,
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Monitor freshness for all tables tagged QLIK_MANAGED in PROD.WAREHOUSE with a 2-hour SLA. Diagnose root causes for any violations."
--           }
--         ]
--       }
--     ]
--   }'
