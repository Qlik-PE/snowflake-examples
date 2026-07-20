# SaaS Analytics Kit — Sample Questions

## Questions for Both Sources (Hybrid)

1. Which segment has the highest net revenue retention, and what's driving it — expansion or low churn?
2. Show me the MRR concentration risk — what percentage of total revenue comes from the top 3 accounts, and which regions are they in?
3. Compare expansion revenue as a percentage of base MRR across plan tiers. Which tier has the most upsell headroom?
4. Are there accounts with declining engagement (low logins, low API calls) but high MRR that might be churn risks?
5. Which industry-segment combination has the worst churn rate, and how much revenue is at risk in similar active accounts?
6. Rank regions by revenue-weighted churn — not just account count, but by how much MRR was lost per region.
7. Which region-industry pair generates the most expansion revenue relative to its base MRR? Where should sales focus?
8. Compare the APAC and EMEA portfolios: which has higher ARPA, better retention, and stronger engagement metrics?

## Qlik MCP Only (visualization, app interaction)

9. Create a bar chart showing MRR by region on the Executive Summary sheet.
10. What bookmarks exist in the app and which selections do they capture?
11. Add a filter panel for Segment and Region to the Customer Health sheet.
12. Create a new sheet with a KPI for total ARR and a line chart trending MRR over time.
13. List the master dimensions and measures currently defined in the app.

## Snowflake Cortex Analyst Only (complex SQL analytics)

14. What is the average time in days between signup and the first month with expansion revenue, grouped by segment?
15. Show me all accounts where MRR decreased for 3 consecutive months.
16. What would total ARR be if every Starter and Professional account upgraded to the next tier's average price?
17. Give me a cohort analysis: group accounts by signup quarter and show how their MRR evolved over subsequent months.
18. Create a health score for each account combining MRR, expansion history, login frequency, and API usage — rank the bottom 10.
