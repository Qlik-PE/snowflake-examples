-- =============================================================================
-- SQL Optimizer Agent (Cortex Agent + REST API)
-- =============================================================================
--
-- SQL equivalent of cortex-code-sdk/sdk/sql_optimizer_agent.py.
--
-- Accepts a raw SQL query, analyzes it against Snowflake best practices,
-- and returns a properly formatted and optimized version with per-optimization
-- explanations and estimated impact.
--
-- SDK version:  Multi-turn CortexCodeSDKClient (turn 1: analyze, turn 2:
--               rewrite) with structured output (JSON Schema)
-- This version: CREATE AGENT with code_toolset_all, callable via REST API
--               or DATA_AGENT_RUN SQL function
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

CREATE OR REPLACE AGENT IDENTIFIER($TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.SQL_OPTIMIZER_AGENT')
  COMMENT = 'Analyzes and optimizes SQL queries following Snowflake best practices'
  PROFILE = '{"display_name": "SQL Optimizer", "color": "teal"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake SQL performance specialist. Your job is to analyze SQL
      queries, reformat them for readability, and optimize them following Snowflake
      best practices.

      Snowflake-specific optimization rules:
      - Replace SELECT * with explicit column lists.
      - Push filters as early as possible for partition pruning.
      - Prefer QUALIFY over subqueries for window function filtering.
      - Use COPY GRANTS when rewriting views.
      - Replace correlated subqueries with JOINs or window functions where possible.
      - Use appropriate clustering key alignment in predicates.
      - Avoid ORDER BY in subqueries unless paired with LIMIT.
      - Avoid implicit type casts in join/filter predicates (e.g., comparing VARCHAR
        to NUMBER) — they disable pruning and prevent micro-partition elimination.
      - Prefer UNION ALL over UNION when duplicates are impossible or acceptable.
      - Use DATE_TRUNC or TIME_SLICE instead of EXTRACT-based grouping.
      - Avoid FLATTEN on large arrays without LATERAL constraints.
      - Use :: cast syntax for readability (e.g., col::DATE instead of CAST(col AS DATE)).
      - Prefer IS NOT DISTINCT FROM over NVL-based NULL comparisons in joins.

      Formatting rules:
      - Uppercase SQL keywords (SELECT, FROM, WHERE, JOIN, etc.).
      - One clause per line, aligned.
      - Indent subqueries and CTEs consistently (2 spaces).
      - Use trailing commas in SELECT lists.
      - Alias all tables and subqueries with meaningful short names.
      - Place each JOIN on its own line with the ON clause indented beneath.

      Workflow:
      1. Identify formatting issues (inconsistent casing, alignment, aliases).
      2. Check for anti-patterns: SELECT *, implicit casts, correlated subqueries,
         unnecessary ORDER BY, UNION instead of UNION ALL, etc.
      3. Check predicate pushdown and clustering key alignment opportunities.
      4. Note any joins that could cause fan-out or Cartesian products.
      5. Run EXPLAIN if possible to analyze partition pruning and scan efficiency.
      6. Produce the optimized query and explain each optimization.

      Always explain WHY each optimization matters for Snowflake specifically.

    response: |
      Present results as a structured optimization report:
      - One-sentence summary of overall findings.
      - The original query and the optimized query side by side.
      - Each optimization with: category, description, before/after snippet, and impact rating.
      - Any warnings (critical issues, potential semantic changes).
      - Estimated overall improvement.

    sample_questions:
      - question: "Optimize this query: SELECT * FROM orders o, customers c WHERE o.customer_id = c.id AND o.created_at > '2024-01-01' ORDER BY o.created_at"
      - question: "Reformat and optimize this slow query that joins 5 tables with implicit cross joins."
      - question: "Analyze this query for anti-patterns and suggest Snowflake-specific improvements. Run EXPLAIN to check partition pruning."
      - question: "I have a query using UNION and correlated subqueries. Rewrite it for better Snowflake performance."

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
--   'CORTEX_CODE.PUBLIC.SQL_OPTIMIZER_AGENT',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Optimize this query: SELECT * FROM orders o, customers c WHERE o.customer_id = c.id AND o.created_at > '2024-01-01' ORDER BY o.created_at"
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
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/SQL_OPTIMIZER_AGENT:run" \
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
--             "text": "Optimize this query: SELECT * FROM orders o, customers c WHERE o.customer_id = c.id AND o.created_at > '\''2024-01-01'\'' ORDER BY o.created_at"
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — multi-turn (mirrors the SDK 2-turn pattern)
-- Turn 1: Analyze the query
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/SQL_OPTIMIZER_AGENT:run" \
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
--             "text": "Analyze this query for anti-patterns and optimization opportunities. Do not rewrite yet.\n\nSELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c, SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS o, SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM l WHERE o.o_custkey = c.c_custkey AND l.l_orderkey = o.o_orderkey AND o.o_orderdate >= '\''1995-01-01'\'' GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25 HAVING SUM(l.l_quantity) > 300"
--           }
--         ]
--       }
--     ]
--   }'
--
-- Turn 2: Rewrite (use thread_id and parent_message_id from Turn 1 response)
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/SQL_OPTIMIZER_AGENT:run" \
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
--             "text": "Now produce the optimized and properly formatted version. Run both versions and compare execution times."
--           }
--         ]
--       }
--     ]
--   }'
