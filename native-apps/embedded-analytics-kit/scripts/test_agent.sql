-- =============================================================================
-- Test Agent: Verify the Embedded Analytics Kit
-- =============================================================================
--
-- Run these queries after installing the app and completing consumer_setup.sql.
-- Each query exercises a different capability of the dual-tool agent.
--
-- =============================================================================

-- =============================================================================
-- Configuration
-- =============================================================================

SET APP_NAME = 'EMBEDDED_ANALYTICS_KIT';
SET AGENT_FQN = $APP_NAME || '.CORE.ANALYTICS_AGENT';

-- =============================================================================
-- Test 1: Pure Snowflake - Semantic View / Cortex Analyst
-- =============================================================================
-- These questions hit the SaaSMetrics tool (Cortex Analyst → Semantic View)

-- Basic metric query
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is total MRR by segment for Q1 2024?"}]}]}'
) AS test_1a_mrr_by_segment;

-- Multi-dimension breakdown
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "Show me net revenue retention by region"}]}]}'
) AS test_1b_nrr_by_region;

-- Usage correlation
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "Which accounts have the highest API usage but lowest MRR?"}]}]}'
) AS test_1c_usage_vs_revenue;

-- Churn analysis
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "How much revenue was lost to churn? Break it down by industry."}]}]}'
) AS test_1d_churn_by_industry;

-- =============================================================================
-- Test 2: Pure Qlik - MCP Server Tools
-- =============================================================================
-- These questions hit the Qlik MCP tools (requires OAuth authentication)

-- App discovery
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "List my Qlik apps"}]}]}'
) AS test_2a_list_apps;

-- Dashboard exploration
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What sheets exist in my most recent Qlik app?"}]}]}'
) AS test_2b_list_sheets;

-- =============================================================================
-- Test 3: Hybrid - Both Tools Together
-- =============================================================================
-- These questions require the agent to orchestrate across both tools

-- Data + visualization
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is MRR by segment? Then find any related Qlik dashboards about revenue."}]}]}'
) AS test_3a_data_then_qlik;

-- Investigation workflow
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $AGENT_FQN,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "Which segments are growing fastest? Check if there are any Qlik apps analyzing customer growth."}]}]}'
) AS test_3b_growth_investigation;

-- =============================================================================
-- Test 4: Verify Data Model Directly
-- =============================================================================
-- Quick sanity checks on the underlying tables

SELECT 'accounts' AS tbl, COUNT(*) AS row_count FROM IDENTIFIER($APP_NAME || '.CORE.ACCOUNTS')
UNION ALL
SELECT 'subscriptions', COUNT(*) FROM IDENTIFIER($APP_NAME || '.CORE.SUBSCRIPTIONS')
UNION ALL
SELECT 'monthly_revenue', COUNT(*) FROM IDENTIFIER($APP_NAME || '.CORE.MONTHLY_REVENUE')
UNION ALL
SELECT 'usage_events', COUNT(*) FROM IDENTIFIER($APP_NAME || '.CORE.USAGE_EVENTS');

-- Verify semantic view exists
SHOW SEMANTIC VIEWS IN SCHEMA IDENTIFIER($APP_NAME || '.CORE');

-- Verify agent exists
SHOW AGENTS IN SCHEMA IDENTIFIER($APP_NAME || '.CORE');
