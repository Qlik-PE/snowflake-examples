-- =============================================================================
-- Access Audit / Least-Privilege Agent (Cortex Agent + REST API)
-- =============================================================================
--
-- SQL equivalent of cortex-code-sdk/sdk/access_audit_agent.py.
--
-- Audits Snowflake access patterns for Qlik service accounts. Identifies
-- over-privileged roles, unused grants, and access anomalies. Returns a
-- structured security report with least-privilege REVOKE/GRANT SQL.
--
-- SDK version:  Multi-turn CortexCodeSDKClient (turn 1: inventory grants,
--               turn 2: cross-reference with usage) with PreToolUse audit
--               hook and structured output (JSON Schema)
-- This version: CREATE AGENT with code_toolset_all, callable via REST API
--               or DATA_AGENT_RUN SQL function. The PreToolUse audit hook
--               is not available server-side; use the agent's event table
--               or query history for audit logging instead.
--
-- Prerequisites:
--   - Snowflake account with Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Access to SNOWFLAKE.ACCOUNT_USAGE views (ACCESS_HISTORY, LOGIN_HISTORY)
--
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

CREATE OR REPLACE AGENT ACCESS_AUDIT_AGENT
  COMMENT = 'Audits access patterns for Qlik service accounts and recommends least-privilege adjustments'
  PROFILE = '{"display_name": "Access Audit", "color": "gray"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a Snowflake security specialist embedded inside a Qlik integration.
      Your job is to audit access patterns for service accounts and roles used by
      Qlik pipelines. You identify over-privileged roles, unused grants, and
      access anomalies, then recommend least-privilege adjustments.

      Be conservative: only recommend revoking grants that are provably unused
      within the audit period. Flag anything that requires testing before removal.

      Audit workflow:
      1. Run SHOW GRANTS TO ROLE to list all privileges for the target role.
      2. Run SHOW GRANTS OF ROLE to see which users/roles inherit it.
      3. Check for any ACCOUNTADMIN or SECURITYADMIN grants in the chain — flag
         these as critical anomalies.
      4. Count total grants by object type (TABLE, SCHEMA, DATABASE, WAREHOUSE).
      5. Find which objects were actually accessed by the role during the audit
         period. ACCESS_HISTORY has no role column: join
         SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY to SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
         on QUERY_ID, filter on QUERY_HISTORY.ROLE_NAME, and FLATTEN
         BASE_OBJECTS_ACCESSED (and OBJECTS_MODIFIED for write grants) to get
         objectName values. Privileges the role passes to parent roles are used
         under those roles' names, so include parent roles or mark the result
         as uncertain instead of "unused".
      6. Compare accessed objects against the grant inventory. Any grant whose
         object was NOT accessed is "unused".
      7. Look for cross-schema or cross-database access patterns that suggest
         the role is broader than needed.
      8. Check LOGIN_HISTORY for the user to spot unusual access times or clients.
      9. Produce least-privilege REVOKE/GRANT recommendations with risk ratings
         (safe / test_first / breaking).

    response: |
      Present a structured access audit report:
      - Summary: role, user, audit period, total/used/unused grant counts, anomaly count.
      - Grant details: each privilege with object, whether it was used, and last used date.
      - Anomalies: type, description, severity, affected object.
      - Recommendations: each with action (revoke/grant/replace_role), description, SQL, and risk.

    sample_questions:
      - question: "Audit all grants for role QLIK_ROLE and identify unused privileges over the last 30 days."
      - question: "Check if service account QLIK_SVC has excessive permissions. Recommend least-privilege adjustments."
      - question: "Are there any ACCOUNTADMIN grants in the role hierarchy for ETL_ROLE? Flag security anomalies."
      - question: "Compare grants vs actual usage for LOADER_ROLE over the last 90 days and produce REVOKE SQL for unused grants."

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
--   'CORTEX_CODE.PUBLIC.ACCESS_AUDIT_AGENT',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Audit all grants for role QLIK_ROLE and identify unused privileges over the last 30 days."
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
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/ACCESS_AUDIT_AGENT:run" \
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
--             "text": "Audit all grants for role QLIK_ROLE and identify unused privileges over the last 30 days."
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — multi-turn with thread (mirrors the SDK 2-turn pattern)
-- Turn 1: Inventory grants
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/ACCESS_AUDIT_AGENT:run" \
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
--             "text": "Inventory all grants for role QLIK_ROLE. Check for ACCOUNTADMIN grants in the chain."
--           }
--         ]
--       }
--     ]
--   }'
--
-- Turn 2: Cross-reference with usage (use thread_id and parent_message_id from Turn 1)
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/ACCESS_AUDIT_AGENT:run" \
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
--             "text": "Now cross-reference grants against actual usage in the last 30 days. Produce REVOKE SQL for unused grants with risk ratings."
--           }
--         ]
--       }
--     ]
--   }'
