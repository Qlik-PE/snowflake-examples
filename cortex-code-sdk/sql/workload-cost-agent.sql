-- =============================================================================
-- Workload Cost Attribution Agent (Cortex Agent + REST API)
-- =============================================================================
--
-- SQL equivalent of cortex-code-sdk/sdk/workload_cost_agent.py.
--
-- Attributes Snowflake credit consumption to Qlik-originated workloads.
-- Breaks down costs by warehouse, surfaces the most expensive queries, and
-- recommends scheduling or sizing optimizations.
--
-- SDK version:  Single-shot query() with structured output (JSON Schema)
-- This version: CREATE AGENT with code_toolset_all, callable via REST API
--               or DATA_AGENT_RUN SQL function
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Access to SNOWFLAKE.ACCOUNT_USAGE views (QUERY_HISTORY,
--     WAREHOUSE_METERING_HISTORY, WAREHOUSE_LOAD_HISTORY)
--
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

CREATE OR REPLACE AGENT WORKLOAD_COST_AGENT
  COMMENT = 'Attributes Snowflake credit consumption to Qlik-originated workloads with optimization recommendations'
  PROFILE = '{"display_name": "Workload Cost", "color": "green"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake FinOps specialist embedded inside a Qlik integration.
      Your job is to analyze Snowflake credit consumption for Qlik-originated
      workloads and produce actionable cost optimization recommendations.

      Use SNOWFLAKE.ACCOUNT_USAGE views: QUERY_HISTORY, WAREHOUSE_METERING_HISTORY,
      and WAREHOUSE_LOAD_HISTORY. Always base recommendations on actual data.

      Analysis workflow:
      1. Query WAREHOUSE_METERING_HISTORY for total credits by warehouse in the period.
      2. Query QUERY_HISTORY to get query counts, avg execution time, and peak usage
         hours, filtered by user/warehouse as specified.
      3. Identify the top 5 most expensive queries by credits_used_cloud_services +
         estimated compute cost (execution_time * warehouse credit rate).
      4. Recommend optimizations: warehouse resizing, multi-cluster scaling, query
         caching, scheduling off-peak, dropping unused objects consuming storage.
      5. Estimate savings percentage for each recommendation.

    response: |
      Present a structured cost attribution report:
      - Total credits consumed in the period.
      - Breakdown by warehouse (credits, query count, avg execution time, peak hour).
      - Top 5 most expensive queries with IDs and SQL previews.
      - Optimization recommendations with category, description, estimated savings, and SQL.

    sample_questions:
      - question: "Analyze credit consumption across all warehouses for the last 7 days."
      - question: "What are the most expensive queries from user QLIK_SVC in the last 30 days?"
      - question: "Break down costs for warehouse QLIK_WH over the last 14 days and recommend optimizations."
      - question: "Which warehouses have the highest cost per query? Suggest right-sizing."

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
--   'CORTEX_CODE.PUBLIC.WORKLOAD_COST_AGENT',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Analyze credit consumption across all warehouses for the last 7 days."
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
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/WORKLOAD_COST_AGENT:run" \
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
--             "text": "Analyze credit consumption across all warehouses for the last 7 days."
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — non-streaming JSON response
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/WORKLOAD_COST_AGENT:run" \
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
--             "text": "What are the most expensive queries from user QLIK_SVC in the last 30 days?"
--           }
--         ]
--       }
--     ]
--   }'
