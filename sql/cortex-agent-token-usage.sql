-- =============================================================================
-- Cortex Agent Token Usage Inspector
-- =============================================================================
--
-- This query inspects token consumption by Cortex Agents, broken down by
-- agent and LLM model. Useful for understanding which agents and models
-- are driving the most token and credit usage.
--
-- View used:
--   SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY
--
-- Columns returned:
--   - AGENT_DATABASE_NAME, AGENT_SCHEMA_NAME, AGENT_NAME — agent identity
--   - MODEL_NAME       — the LLM model used (e.g., claude-3-5-sonnet, llama3.1-70b)
--   - SERVICE_TYPE     — service layer (e.g., cortex_agent, cortex_analyst)
--   - TOTAL_CREDITS    — AI credits consumed (token-based)
--   - TOTAL_TOKENS     — raw token count (input + output + cache)
--   - REQUEST_COUNT    — number of distinct requests
--
-- Prerequisites:
--   - A role with access to SNOWFLAKE.ACCOUNT_USAGE
--   - Cortex Agents must have been invoked within the time window
--
-- Usage:
--   Replace <START_TIME> and <END_TIME> with your desired date range.
--   Keep the window to at most one month to avoid query timeouts.
--
-- =============================================================================

-- Adjust the time window (max 1 month recommended)
SET START_TIME = '2026-07-21';
SET END_TIME   = '2026-08-21';

WITH flattened AS (
    SELECT
        AGENT_DATABASE_NAME,
        AGENT_SCHEMA_NAME,
        AGENT_NAME,
        COALESCE(NULLIF(cf4.key, ''), 'unknown') AS model_name,
        cf3.key AS service_type,
        COALESCE(cf4.value:input::FLOAT, 0) +
        COALESCE(cf4.value:output::FLOAT, 0) +
        COALESCE(cf4.value:cache_read_input::FLOAT, 0) +
        COALESCE(cf4.value:cache_write_input::FLOAT, 0) AS total_credits,
        COALESCE(tf4.value:input::FLOAT, 0) +
        COALESCE(tf4.value:output::FLOAT, 0) +
        COALESCE(tf4.value:cache_read_input::FLOAT, 0) +
        COALESCE(tf4.value:cache_write_input::FLOAT, 0) AS total_tokens,
        h.REQUEST_ID
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY h,
         LATERAL FLATTEN(input => h.CREDITS_GRANULAR) cf1,
         LATERAL FLATTEN(input => cf1.value) cf2,
         LATERAL FLATTEN(input => cf2.value) cf3,
         LATERAL FLATTEN(input => cf3.value) cf4,
         LATERAL FLATTEN(input => h.TOKENS_GRANULAR) tf1,
         LATERAL FLATTEN(input => tf1.value) tf2,
         LATERAL FLATTEN(input => tf2.value) tf3,
         LATERAL FLATTEN(input => tf3.value) tf4
    WHERE cf2.key != 'start_time'
      AND tf2.key != 'start_time'
      AND cf1.index = tf1.index
      AND cf2.key = tf2.key
      AND cf3.key = tf3.key
      AND cf4.key = tf4.key
      AND h.START_TIME >= $START_TIME
      AND h.START_TIME < $END_TIME
)
SELECT
    AGENT_DATABASE_NAME,
    AGENT_SCHEMA_NAME,
    AGENT_NAME,
    model_name,
    service_type,
    ROUND(SUM(total_credits), 4) AS total_credits,
    SUM(total_tokens) AS total_tokens,
    COUNT(DISTINCT REQUEST_ID) AS request_count
FROM flattened
GROUP BY AGENT_DATABASE_NAME, AGENT_SCHEMA_NAME, AGENT_NAME, model_name, service_type
ORDER BY total_credits DESC;
