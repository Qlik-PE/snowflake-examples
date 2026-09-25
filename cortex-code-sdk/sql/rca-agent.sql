-- =============================================================================
-- Failure Root-Cause Analysis Agent (Cortex Agent + REST API)
-- =============================================================================
--
-- SQL equivalent of cortex-code-sdk/sdk/rca_agent.py.
--
-- Investigates Snowflake-side failures when a Qlik reload or CDC pipeline
-- errors out. Queries QUERY_HISTORY, WAREHOUSE_EVENTS_HISTORY, and other
-- ACCOUNT_USAGE views to produce a root-cause report with remediation SQL.
--
-- SDK version:  Single-shot query() with structured output (JSON Schema)
-- This version: CREATE AGENT with code_toolset_all, callable via REST API
--               or DATA_AGENT_RUN SQL function
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Access to SNOWFLAKE.ACCOUNT_USAGE views
--
-- References:
--   - Coding Agent: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-coding-agent
--   - DATA_AGENT_RUN: https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex
--
-- =============================================================================

-- Step 0: Configuration
SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

-- Step 1: Create the agent
CREATE OR REPLACE AGENT IDENTIFIER($TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.RCA_AGENT')
  COMMENT = 'Investigates Snowflake-side failures when a Qlik reload or CDC pipeline errors out'
  PROFILE = '{"display_name": "Failure RCA", "color": "red"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake platform specialist embedded inside a Qlik integration.
      Your job is to investigate failures on the Snowflake side when a Qlik reload
      or CDC pipeline reports an error. You have access to SQL and can query
      SNOWFLAKE.ACCOUNT_USAGE and INFORMATION_SCHEMA views.

      Always ground your analysis in actual query history data. If you find no
      matching failures, say so clearly in the summary.

      Investigation workflow:
      1. Find failed queries (EXECUTION_STATUS / ERROR_CODE set) in the specified
         time window. SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY lags by up to ~45
         minutes, so for recent activity use the real-time table function
         TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(END_TIME_RANGE_START => ...,
         RESULT_LIMIT => 10000)) or QUERY_HISTORY_BY_WAREHOUSE. Use ACCOUNT_USAGE
         for older periods, de-duplicating on QUERY_ID if you use both.
      2. Look for patterns: repeated errors, resource contention, credential
         issues, object-not-found, timeouts, etc.
      3. If relevant, check WAREHOUSE_LOAD_HISTORY or WAREHOUSE_EVENTS_HISTORY
         for the same period.
      4. Produce a root-cause analysis with concrete remediation SQL.
      5. Rate the severity: low, medium, high, or critical.

    response: |
      Present findings as a structured root-cause report:
      - Start with a one-sentence summary of the root cause.
      - List each failed query with its error message, user, warehouse, and execution time.
      - Provide remediation SQL that can be run immediately.
      - Rate severity (low / medium / high / critical).

    sample_questions:
      - question: "Investigate failures on warehouse QLIK_WH in the last 30 minutes."
      - question: "Why are queries from user QLIK_SVC timing out? Check the last 2 hours."
      - question: "A Qlik reload just failed with a permission error. Find the root cause."
      - question: "Check for any failed queries in the last hour and diagnose the pattern."

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
-- Two options: SQL (DATA_AGENT_RUN) or REST API (curl).
-- Uncomment the approach you prefer.

-- Option A: SQL via DATA_AGENT_RUN
-- Returns a single JSON response. Good for worksheets, stored procedures,
-- and scheduled tasks. The third argument (TRUE) auto-creates a thread.
--
-- SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--   'CORTEX_CODE.PUBLIC.RCA_AGENT',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Investigate any failures on all warehouses in the last 60 minutes."
--           }
--         ]
--       }
--     ]
--   }
--   $$,
--   TRUE
-- ) AS response;

-- Option B: REST API via curl
-- Streams server-sent events (SSE) by default. Set "stream": false for
-- a single JSON response. Replace $SNOWFLAKE_ACCOUNT_BASE_URL and $PAT
-- with your account URL and programmatic access token.
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/RCA_AGENT:run" \
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
--             "text": "Investigate any failures on all warehouses in the last 60 minutes."
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — multi-turn with thread
-- Pass thread_id and parent_message_id to continue a conversation.
-- The first call creates the thread (thread_id: 0, parent_message_id: 0).
-- Subsequent calls use the thread_id and parent_message_id from the
-- previous response metadata.
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/RCA_AGENT:run" \
--   --header 'Content-Type: application/json' \
--   --header 'Accept: text/event-stream' \
--   --header "Authorization: Bearer $PAT" \
--   --data '{
--     "thread_id": 0,
--     "parent_message_id": 0,
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Investigate any failures on warehouse QLIK_WH in the last 30 minutes."
--           }
--         ]
--       }
--     ]
--   }'
