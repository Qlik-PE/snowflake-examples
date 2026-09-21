-- =============================================================================
-- Qlik Automate → Snowflake Cortex Agent Orchestration
-- =============================================================================
--
-- This script creates a Cortex Agent designed to be called by Qlik Automate
-- workflows via the Snowflake REST API. The agent monitors data freshness
-- across Qlik-managed tables in Snowflake and returns structured JSON that
-- Qlik Automate can parse and route (Slack, email, Qlik app reload, etc.).
--
-- What is created:
--   - Cortex Agent:  <AGENT_NAME>  (in TARGET_DATABASE.TARGET_SCHEMA)
--   - Snowflake Intelligence registration (optional)
--
-- How Qlik Automate calls this agent:
--   Qlik Automate uses its Generic REST connector (or Call URL block) to
--   POST to the Snowflake Cortex Agent REST API:
--
--     POST /api/v2/databases/{db}/schemas/{schema}/agents/{agent}:run
--
--   Authentication: Qlik Automate authenticates to Snowflake using a
--   key-pair-based PAT (Personal Access Token) stored as a Qlik Automate
--   connection credential.
--
-- Architecture:
--
--   Qlik Cloud Event (app reload, schedule)
--     |
--     v
--   Qlik Automate Workflow
--     |-- Start: scheduled / webhook / Qlik event trigger
--     |-- Step 1: Call Snowflake Cortex Agent REST API (Generic REST block)
--     |-- Step 2: Parse structured JSON response
--     |-- Step 3: Branch on SLA status
--     |     |-- All OK  → log success
--     |     |-- Breach  → notify (Slack/Teams/email) + trigger Qlik app reload
--     |-- Step 4: Write audit record back to Snowflake (native connector)
--     v
--   Done
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Access to INFORMATION_SCHEMA and SNOWFLAKE.ACCOUNT_USAGE views
--   - Qlik Cloud tenant with Qlik Automate enabled
--   - Snowflake PAT for Qlik Automate authentication (see README)
--
-- References:
--   - Cortex Agent REST API: POST /api/v2/databases/{db}/schemas/{schema}/agents/{name}:run
--   - Qlik Automate docs: https://help.qlik.com/en-US/cloud-services/Subsystems/Hub/Content/Sense_QlikAutomation/introduction/home-automation.htm
--   - Qlik Automate REST API: https://qlik.dev/apis/rest/automations/
--
-- =============================================================================

-- =============================================================================
-- Step 0: Configuration Parameters
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';
SET AGENT_NAME      = 'QLIK_AUTOMATE_FRESHNESS_AGENT';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

-- =============================================================================
-- Step 1: Create the audit table
-- =============================================================================
-- Qlik Automate writes results back here after each run. This provides a
-- historical record of freshness checks for dashboarding and trend analysis.
-- =============================================================================

CREATE TABLE IF NOT EXISTS FRESHNESS_AUDIT_LOG (
    run_id          STRING DEFAULT UUID_STRING(),
    run_timestamp   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source          STRING DEFAULT 'qlik_automate',
    schema_checked  STRING,
    sla_hours       NUMBER,
    total_tables    NUMBER,
    tables_ok       NUMBER,
    tables_breached NUMBER,
    breached_tables VARIANT,
    agent_response  VARIANT
);

-- =============================================================================
-- Step 2: Create the Cortex Agent
-- =============================================================================
-- This agent is optimized for machine consumption: it returns structured JSON
-- so Qlik Automate can parse fields directly without regex or text extraction.
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

      CRITICAL: Always return your final answer as a single JSON code block
      with this exact schema:

      ```json
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
      ```

      Workflow:
      1. Parse the user message to extract: target schema and SLA threshold hours.
      2. Query INFORMATION_SCHEMA.TABLES for TABLE_NAME, ROW_COUNT, LAST_ALTERED.
      3. Compute hours since last alteration for each table.
      4. Flag tables where staleness exceeds the SLA threshold.
      5. For breached tables, check SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY for the
         most recent task runs targeting that schema.
      6. Check SHOW TASKS IN SCHEMA for suspended tasks.
      7. Build the JSON response with remediation SQL for each breach.

      IMPORTANT:
      - Never return prose or commentary outside the JSON block.
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
-- Step 3: Register with Snowflake Intelligence (optional)
-- =============================================================================
-- Skip this step if you only need REST API / Qlik Automate access.
-- =============================================================================

-- CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
-- ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
--   ADD AGENT QLIK_AUTOMATE_FRESHNESS_AGENT;

-- =============================================================================
-- Step 4: Test the agent (SQL)
-- =============================================================================

-- Option A: SQL via DATA_AGENT_RUN
--
-- SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--   'CORTEX_CODE.PUBLIC.QLIK_AUTOMATE_FRESHNESS_AGENT',
--   $$
--   {
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
--   }
--   $$,
--   TRUE
-- ) AS response;

-- =============================================================================
-- Step 5: Test the agent (REST API — same call Qlik Automate will make)
-- =============================================================================
-- Replace $SNOWFLAKE_ACCOUNT_URL and $PAT with your values.
-- This is the exact HTTP call that Qlik Automate's Generic REST block executes.
-- =============================================================================

-- curl -X POST "$SNOWFLAKE_ACCOUNT_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/QLIK_AUTOMATE_FRESHNESS_AGENT:run" \
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
--             "text": "Check freshness for ANALYTICS.PUBLIC with a 4-hour SLA."
--           }
--         ]
--       }
--     ]
--   }'

-- =============================================================================
-- Step 6: Write audit record (Qlik Automate calls this via native connector)
-- =============================================================================
-- Qlik Automate's Snowflake connector executes this INSERT after parsing the
-- agent response. The workflow extracts fields from the JSON and passes them
-- as parameters.
-- =============================================================================

-- INSERT INTO FRESHNESS_AUDIT_LOG (schema_checked, sla_hours, total_tables, tables_ok, tables_breached, breached_tables, agent_response)
-- SELECT
--   :schema_checked,
--   :sla_hours,
--   :total_tables,
--   :tables_ok,
--   :tables_breached,
--   PARSE_JSON(:breached_tables_json),
--   PARSE_JSON(:full_agent_response);
