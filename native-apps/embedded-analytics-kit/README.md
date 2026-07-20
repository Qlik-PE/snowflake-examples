# Embedded Analytics Starter Kit

A Cortex Agent that provides a unified AI analytics experience over both Snowflake data and Qlik Cloud dashboards — demonstrating the joint value of the Qlik + Snowflake partnership.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  User (Snowflake Intelligence / CoWork / SQL)                       │
│                                                                     │
│  "What is MRR by segment? Show me related Qlik dashboards."        │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Cortex Agent: CORTEX_APP.PUBLIC.SAAS_ANALYTICS_KIT                 │
│  (orchestrates across both tool sources)                            │
├─────────────────────────────────┬───────────────────────────────────┤
│                                 │                                   │
│  Tool 1: SaaSMetrics            │  Tool 2: Qlik MCP Server          │
│  (Cortex Analyst — fallback)    │  (External MCP — primary)         │
│                                 │                                   │
│  ┌───────────────────────┐      │  ┌────────────────────────────┐  │
│  │ Semantic View          │      │  │ Qlik Cloud App             │  │
│  │ CORTEX_APP.PUBLIC.     │      │  │ dd64adae-c4db-46a7-...     │  │
│  │ SAAS_METRICS_SV        │      │  │                            │  │
│  │                        │      │  │  • App discovery           │  │
│  │ Tables:                │      │  │  • Sheet/chart creation    │  │
│  │  • accounts (500)      │      │  │  • Master items            │  │
│  │  • subscriptions (500) │      │  │  • Bookmarks               │  │
│  │  • monthly_revenue (7k)│      │  │  • Data exploration        │  │
│  │  • usage_events (5.5k) │      │  │  • 70+ tools               │  │
│  └───────────────────────┘      │  └────────────────────────────┘  │
└─────────────────────────────────┴───────────────────────────────────┘
```

## Deployed Objects

| Object | Location | Purpose |
|--------|----------|---------|
| Agent | `CORTEX_APP.PUBLIC.SAAS_ANALYTICS_KIT` | Dual-source Cortex Agent |
| Semantic View | `CORTEX_APP.PUBLIC.SAAS_METRICS_SV` | Cortex Analyst text-to-SQL |
| MCP Server | `CORTEX_APP.PUBLIC.QLIK_MCP_SERVER` | Qlik Cloud connection |
| Tables | `CORTEX_APP.PUBLIC.{ACCOUNTS,SUBSCRIPTIONS,MONTHLY_REVENUE,USAGE_EVENTS}` | SaaS metrics data |
| Qlik App | `dd64adae-c4db-46a7-857f-bc19dfe249a8` | 4 sheets with dashboards |

## Data Model

2,000 accounts, ~100k total rows across 42 months (Mar 2023 - Jul 2026):

| Table | Rows | Description |
|-------|------|-------------|
| accounts | 2,000 | Companies with segment, region, industry, status |
| subscriptions | 2,600 | Plan tier (Starter/Professional/Enterprise), pricing, add-ons |
| monthly_revenue | 52,127 | MRR, expansion, contraction, churn per account/month |
| usage_events | 43,238 | Logins, API calls, reports, GB scanned per account/month |

10 industries with 200 accounts each (Technology, Financial, Healthcare, Retail, Manufacturing, Energy, Education, Media, Logistics, Travel). Even distribution across 3 segments and 4 regions.

### Metrics

| Metric | Expression | Description |
|--------|------------|-------------|
| Total MRR | `Sum(MRR)` | Monthly Recurring Revenue |
| Total ARR | `Sum(MRR) * 12` | Annualized Recurring Revenue |
| Expansion | `Sum(EXPANSION_MRR)` | Upsell and cross-sell revenue |
| Churn | `Sum(CHURNED_MRR)` | Revenue lost from cancellations |
| NRR | `(MRR + Expansion - Contraction - Churn) / MRR * 100` | Net Revenue Retention % |
| ARPA | `Avg(MRR)` | Average Revenue Per Account |
| Active Accounts | `Count(DISTINCT ... status='Active')` | Paying customers |

## Routing Rules

The agent follows a strict routing hierarchy:

1. **Qlik MCP is primary** — all business questions go to the Qlik app first
2. **Cortex Analyst is fallback** — only used when Qlik MCP confirms a gap
3. **Visualization requests are Qlik-only** — charts, sheets, filters
4. **SQL analytics are Snowflake-only** — window functions, temporal patterns, hypotheticals

## Qlik App Sheets

| Sheet | Content |
|-------|---------|
| Executive Summary | 4 KPIs (MRR/ARR, Accounts, NRR, Expansion/Churn) + trend combo + segment/region/industry charts |
| Revenue | MRR trend line + segment components combo + heatmap (segment x region) + top accounts table |
| Customer Health | Status pie + churn by industry + engagement combo + usage vs revenue scatter + filters |
| Subscriptions | Revenue by plan pie + ARPA & expansion combo + segment bar + pivot matrix + detail table |

## Prerequisites

- Snowflake account with Cortex Agents enabled
- Qlik MCP server created (see `mcp/create-mcp-agent.sql`)
- User has completed Qlik OAuth flow
- ACCOUNTADMIN role

## Usage

**Snowflake Intelligence (CoWork):**
The agent appears as "SaaS Analytics Kit (Qlik + Snowflake)" in the agent picker.

**SQL:**
```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'CORTEX_APP.PUBLIC.SAAS_ANALYTICS_KIT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is ARR by region?"}]}]}'
);
```

**Authenticate Qlik:**
```sql
SELECT SYSTEM$START_USER_OAUTH_FLOW('QLIK_MCP_INTEGRATION');
```

## What's Included

| File | Purpose |
|------|---------|
| `setup_script.sql` | Creates tables, seed data, semantic view, agent (Native App format) |
| `manifest.yml` | Native App metadata |
| `semantic/saas_metrics.yaml` | Semantic model documentation |
| `agent/agent_spec.yaml` | Agent specification reference |
| `scripts/consumer_setup.sql` | Consumer onboarding (grants, MCP wiring) |
| `scripts/authenticate_qlik.sql` | OAuth flow for Qlik MCP |
| `scripts/test_agent.sql` | Verification queries |
| `scripts/sample-questions.md` | 15 complex analytical questions |
| `scripts/questions-by-source.md` | Questions unique to each platform |

## Why Both Platforms?

| Capability | Snowflake Only | Qlik Only | Together |
|-----------|---------------|-----------|----------|
| Ad-hoc SQL (window functions, CTEs) | ✅ | — | Agent routes complex analytics to SQL |
| Visualization & dashboards | — | ✅ | Agent creates charts on demand |
| Governed metrics (semantic layer) | ✅ Semantic View | ✅ Master Items | Both aligned |
| Associative exploration | — | ✅ | Agent leverages Qlik's green/white/gray |
| Scale (billions of rows) | ✅ | — | Snowflake computes, Qlik displays |
| Consecutive-period patterns | ✅ LAG/LEAD | — | SQL window functions |
| Hypothetical modeling | ✅ CASE/subqueries | — | What-if scenarios in SQL |
| Bookmarks & selection states | — | ✅ | Save investigation context |
