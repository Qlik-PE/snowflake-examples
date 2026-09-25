-- =============================================================================
-- Pipeline Pre-Flight Validator Agent (Cortex Agent + REST API)
-- =============================================================================
--
-- SQL equivalent of cortex-code-sdk/sdk/preflight_validator_agent.py.
--
-- Before a Qlik Declarative Pipeline runs, this agent checks the Snowflake
-- side: target tables exist, the service account has required grants,
-- warehouses are running, and dynamic tables are healthy. Returns a
-- structured go/no-go report with remediation SQL.
--
-- SDK version:  Single-shot query() with PreToolUse audit hook and
--               structured output (JSON Schema)
-- This version: CREATE AGENT with code_toolset_all, callable via REST API
--               or DATA_AGENT_RUN SQL function. The PreToolUse audit hook
--               is not available server-side; use the agent's event table
--               or query history for audit logging instead.
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - The target database, schema, role, and warehouse must be specified
--     in the user message
--
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

CREATE OR REPLACE AGENT PREFLIGHT_VALIDATOR_AGENT
  COMMENT = 'Pre-flight validation for Qlik pipelines: checks objects, grants, warehouses, and dynamic tables'
  PROFILE = '{"display_name": "Pre-Flight Check", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake operations specialist embedded inside a Qlik integration.
      Your job is to perform pre-flight validation before a Qlik Declarative Pipeline
      runs. Check that all Snowflake prerequisites are met and report any blockers.

      Be thorough: check object existence, grants, warehouse state, and dynamic table
      health. For every issue found, provide remediation SQL.

      Pre-flight checklist:
      1. Verify the target database and schema exist.
      2. List tables, views, and dynamic tables in the target schema. Note any that
         are missing or in an error state.
      3. Check that the service role has USAGE on the database and schema, SELECT on
         tables, and USAGE on the warehouse. Use SHOW GRANTS TO ROLE.
      4. Check warehouse state (STARTED/SUSPENDED). If suspended, include RESUME SQL
         in remediations.
      5. For any dynamic tables in the schema, check their refresh status via
         SHOW DYNAMIC TABLES and DYNAMIC_TABLE_REFRESH_HISTORY. Flag any with
         UPSTREAM_FAILED or stale refreshes.
      6. Produce a GO / NO_GO verdict. NO_GO if any critical issue is found
         (missing objects, missing grants, warehouse suspended).

    response: |
      Present a structured pre-flight report:
      - GO / NO_GO verdict with one-sentence summary.
      - Object checks: each object with existence status and issues.
      - Grant checks: each privilege with granted status and issues.
      - Warehouse checks: state, size, and issues.
      - Dynamic table checks: refresh status, last refresh time, and issues.
      - Remediation SQL for every issue found.

    sample_questions:
      - question: "Run pre-flight checks for a pipeline targeting STAGING.RAW with role QLIK_ROLE and warehouse QLIK_WH."
      - question: "Validate that role ETL_SVC can read all tables in ANALYTICS.PUBLIC and that the warehouse is running."
      - question: "Check if dynamic tables in PROD.TRANSFORMS are healthy before the nightly pipeline runs."
      - question: "Pre-flight check: does LOADER_ROLE have the grants it needs for WAREHOUSE_XS on database INGEST?"

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
-- NOTE: The examples below call the agent at its default location
-- (CORTEX_CODE.PUBLIC). Adjust them if you changed TARGET_DATABASE/SCHEMA.

-- Option A: SQL via DATA_AGENT_RUN
--
-- SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--   'CORTEX_CODE.PUBLIC.PREFLIGHT_VALIDATOR_AGENT',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Run pre-flight checks for a pipeline targeting STAGING.RAW with role QLIK_ROLE and warehouse QLIK_WH."
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
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/PREFLIGHT_VALIDATOR_AGENT:run" \
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
--             "text": "Run pre-flight checks for a pipeline targeting STAGING.RAW with role QLIK_ROLE and warehouse QLIK_WH."
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — non-streaming JSON (for automated pipelines)
-- Use stream: false when the caller is a script or Qlik Automate action
-- that expects a complete JSON response rather than SSE.
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/PREFLIGHT_VALIDATOR_AGENT:run" \
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
--             "text": "Validate that role ETL_SVC can read all tables in ANALYTICS.PUBLIC and that the warehouse is running."
--           }
--         ]
--       }
--     ]
--   }'
