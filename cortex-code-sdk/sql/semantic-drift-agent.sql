-- =============================================================================
-- Semantic View Drift Checker Agent (Cortex Agent + REST API)
-- =============================================================================
--
-- SQL equivalent of cortex-code-sdk/sdk/semantic_drift_agent.py.
--
-- Compares a Qlik Data Product definition against a Snowflake semantic view.
-- Detects column drift, type mismatches, and broken verified queries, then
-- produces reconciliation DDL.
--
-- SDK version:  Multi-turn CortexCodeSDKClient with structured output
-- This version: CREATE AGENT with code_toolset_all, callable via REST API
--               or DATA_AGENT_RUN SQL function. Multi-turn is handled by
--               passing thread_id across consecutive REST API calls.
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents and Semantic Views enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

CREATE OR REPLACE AGENT IDENTIFIER($TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.SEMANTIC_DRIFT_AGENT')
  COMMENT = 'Detects drift between Qlik Data Product definitions and Snowflake semantic views'
  PROFILE = '{"display_name": "Semantic Drift", "color": "purple"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake semantic layer specialist embedded inside a Qlik integration.
      Your job is to inspect Snowflake semantic views, compare them against expected
      data product definitions, and detect drift. You can query INFORMATION_SCHEMA,
      DESCRIBE semantic views, and run verified queries to validate correctness.

      When drift is detected, produce ALTER/CREATE OR REPLACE DDL to reconcile.

      Investigation workflow:
      1. Run DESCRIBE SEMANTIC VIEW on the target to get its current definition.
      2. Identify the underlying table(s) it references.
      3. Run DESCRIBE TABLE on the underlying table(s) to get current column types.
      4. Compare: find columns added/removed/type-changed between the semantic view
         and its underlying table, or between the semantic view and expected fields.
      5. Run any verified queries defined on the semantic view. Record pass/fail/error.
      6. Produce reconciliation DDL (ALTER SEMANTIC VIEW or CREATE OR REPLACE) for
         any issues found.

    response: |
      Present a structured drift report:
      - Summary: whether drift was detected.
      - Column drifts: each with name, drift type (added/removed/type_changed), expected vs actual.
      - Verified query results: each with name, status (passed/failed/error), error message, row count.
      - Reconciliation DDL: ready-to-run SQL to fix each issue.

    sample_questions:
      - question: "Check ANALYTICS.PUBLIC.SALES_SV for drift against its underlying tables."
      - question: "Compare semantic view REPORTING.PUBLIC.REVENUE_SV against expected fields: revenue:NUMBER, customer_id:VARCHAR, order_date:DATE."
      - question: "Run all verified queries on ANALYTICS.PUBLIC.INVENTORY_SV and report any failures."
      - question: "Is the semantic view MARKETING.PUBLIC.CAMPAIGNS_SV in sync with its base table? Generate fix DDL if not."

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
--   'CORTEX_CODE.PUBLIC.SEMANTIC_DRIFT_AGENT',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Check ANALYTICS.PUBLIC.SALES_SV for drift against its underlying tables."
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
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/SEMANTIC_DRIFT_AGENT:run" \
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
--             "text": "Check ANALYTICS.PUBLIC.SALES_SV for drift against its underlying tables."
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — multi-turn with thread (mirrors the SDK multi-turn pattern)
-- Turn 1: Discover drift
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/SEMANTIC_DRIFT_AGENT:run" \
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
--             "text": "Investigate semantic view ANALYTICS.PUBLIC.SALES_SV. Compare against expected fields: revenue:NUMBER, customer_id:VARCHAR, order_date:DATE."
--           }
--         ]
--       }
--     ]
--   }'
--
-- Turn 2: Validate verified queries (use thread_id and parent_message_id from Turn 1 response)
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/SEMANTIC_DRIFT_AGENT:run" \
--   --header 'Content-Type: application/json' \
--   --header 'Accept: text/event-stream' \
--   --header "Authorization: Bearer $PAT" \
--   --data '{
--     "thread_id": <thread_id_from_turn_1>,
--     "parent_message_id": <message_id_from_turn_1>,
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Now run all verified queries and produce reconciliation DDL for any issues."
--           }
--         ]
--       }
--     ]
--   }'
