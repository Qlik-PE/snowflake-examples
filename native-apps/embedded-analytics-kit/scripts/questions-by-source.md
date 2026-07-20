# Questions by Source Capability

## Only answerable by Qlik MCP (not Snowflake Cortex Analyst)

1. **"Create a bar chart showing MRR by region on the Executive Summary sheet."**
   - Requires visualization creation — Cortex Analyst can only return data, never render charts.

2. **"What bookmarks exist in the app and which selections do they capture?"**
   - Bookmarks are a Qlik app construct with no Snowflake equivalent — they store selection states within the associative engine.

3. **"Add a filter panel for Segment and Region to the Customer Health sheet."**
   - Interactive filter creation is a Qlik-only operation — Snowflake has no concept of dashboard filters.

## Only answerable by Snowflake Cortex Analyst (not Qlik MCP)

1. **"What is the average time in days between signup_date and the first month with expansion_mrr > 0, grouped by segment?"**
   - Requires a correlated temporal calculation across tables (ACCOUNTS.signup_date vs first MONTHLY_REVENUE row with expansion) — this needs SQL window functions that Qlik expressions cannot easily replicate.

2. **"Show me all accounts where MRR decreased for 3 consecutive months."**
   - Consecutive-period pattern detection requires LAG/LEAD window functions across ordered partitions — native SQL territory, not achievable with standard Qlik set analysis.

3. **"What would total ARR be if every Starter and Professional account upgraded to the next tier's average price?"**
   - Hypothetical scenario modeling with conditional CASE logic joining across pricing tiers — requires SQL subqueries that reference other accounts' averages, which Qlik's per-row expression model doesn't support natively.
