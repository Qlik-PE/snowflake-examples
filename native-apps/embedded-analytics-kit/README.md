# Embedded Analytics Starter Kit

A Snowflake Native App that provides a unified AI analytics experience over both Snowflake data and Qlik Cloud dashboards through a single Cortex Agent.

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
│  Cortex Agent: analytics_agent                                      │
│  (orchestrates across both tool sources)                            │
├─────────────────────────────────┬───────────────────────────────────┤
│                                 │                                   │
│  Tool 1: SaaSMetrics            │  Tool 2: Qlik MCP Server          │
│  (Cortex Analyst)               │  (External MCP)                   │
│                                 │                                   │
│  ┌───────────────────────┐      │  ┌────────────────────────────┐  │
│  │ Semantic View         │      │  │ Qlik Cloud                 │  │
│  │ ┌─────────────────┐   │      │  │                            │  │
│  │ │ accounts        │   │      │  │  • App discovery           │  │
│  │ │ subscriptions   │   │      │  │  • Sheet/chart creation    │  │
│  │ │ monthly_revenue │   │      │  │  • Master items            │  │
│  │ │ usage_events    │   │      │  │  • Bookmarks               │  │
│  │ └─────────────────┘   │      │  │  • Data exploration        │  │
│  │                       │      │  │  • Glossary                 │  │
│  │ Metrics: MRR, ARR,    │      │  │  • Lineage                 │  │
│  │ NRR, churn, expansion │      │  │  • 70+ tools               │  │
│  └───────────────────────┘      │  └────────────────────────────┘  │
└─────────────────────────────────┴───────────────────────────────────┘
```

## What's Included

| File | Purpose |
|------|---------|
| `manifest.yml` | Native App metadata, version, privileges |
| `setup_script.sql` | Creates tables, seed data, semantic view, agent |
| `semantic/saas_metrics.yaml` | Semantic model documentation (reference) |
| `agent/agent_spec.yaml` | Agent specification documentation (reference) |
| `scripts/consumer_setup.sql` | Consumer admin runs post-install to connect Qlik |
| `scripts/test_agent.sql` | Verification queries for both tool paths |

## Data Model

The app ships with a sample SaaS metrics dataset:

- **accounts** (20 rows) — Companies with segment, region, industry, status
- **subscriptions** (20 rows) — Plans with tier (Starter/Professional/Enterprise) and pricing
- **monthly_revenue** (36 rows) — MRR, expansion, contraction, and churn per account/month
- **usage_events** (31 rows) — Logins, API calls, reports, data scanned per account/month

### Metrics Available

| Metric | Description |
|--------|-------------|
| MRR | Monthly Recurring Revenue |
| ARR | Annual Recurring Revenue (MRR × 12) |
| Net Revenue Retention | (MRR + Expansion - Contraction - Churn) / MRR |
| Expansion Revenue | Upsell and cross-sell revenue |
| Churn | Revenue lost from cancellations |
| ARPA | Average Revenue Per Account |
| Active Accounts | Count of paying customers |
| Churn Rate | Percentage of churned accounts |

## Prerequisites

- Snowflake account with Cortex Agents enabled
- A Qlik MCP server already created (see `mcp/create-mcp-agent.sql`)
- User has completed Qlik OAuth flow
- ACCOUNTADMIN role for installation

## Installation

### 1. Create the Application Package

```sql
CREATE APPLICATION PACKAGE embedded_analytics_kit_pkg;
CREATE SCHEMA embedded_analytics_kit_pkg.v1;

-- Upload all files to a stage
CREATE STAGE embedded_analytics_kit_pkg.v1.app_stage;
-- PUT files to stage (via Snowflake CLI or UI)

ALTER APPLICATION PACKAGE embedded_analytics_kit_pkg
  ADD VERSION v1 USING '@embedded_analytics_kit_pkg.v1.app_stage';
```

### 2. Install the App

```sql
CREATE APPLICATION embedded_analytics_kit
  FROM APPLICATION PACKAGE embedded_analytics_kit_pkg
  USING VERSION v1;
```

### 3. Connect Qlik MCP Server

Run `scripts/consumer_setup.sql` with your configuration:

```sql
SET QLIK_MCP_SERVER = 'YOUR_DB.YOUR_SCHEMA.YOUR_QLIK_MCP_SERVER';
-- ... then run the rest of consumer_setup.sql
```

### 4. Verify

Run `scripts/test_agent.sql` to confirm both tool paths work.

## Usage

After installation, the agent is available via:

**Snowflake Intelligence (CoWork):**
The agent appears automatically with the name "SaaS Analytics Kit (Qlik + Snowflake)".

**SQL:**
```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'EMBEDDED_ANALYTICS_KIT.CORE.ANALYTICS_AGENT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is ARR by region?"}]}]}'
);
```

## Example Questions

| Question | Tools Used |
|----------|-----------|
| "What is total MRR by segment?" | SaaSMetrics (Cortex Analyst) |
| "Which accounts have the highest churn risk?" | SaaSMetrics |
| "List my Qlik apps" | Qlik MCP |
| "Create a bar chart of revenue by region" | Qlik MCP |
| "What is NRR and do we have any dashboards tracking it?" | Both |
| "Show me expansion revenue trends, then find related Qlik sheets" | Both |

## Customization

**Replace the data model:** Swap the sample tables in `setup_script.sql` with your own schema. Update the Semantic View definition to match your columns and metrics.

**Add more tools:** Edit the agent spec to add additional MCP servers (GitHub, Jira, Salesforce) or Cortex Search services.

**Change the semantic model:** Modify `semantic/saas_metrics.yaml` as your reference, then update the `CREATE SEMANTIC VIEW` DDL in `setup_script.sql` to match.

## Why Both Platforms?

| Capability | Snowflake | Qlik | Together |
|-----------|-----------|------|----------|
| Ad-hoc SQL queries | ✅ | — | Agent decides |
| Governed metrics | Semantic View | Master Items | Aligned definitions |
| Interactive exploration | — | ✅ Associative engine | Agent bridges both |
| Visualization creation | — | ✅ Charts/sheets | Data from SF, viz in Qlik |
| Scale (billions of rows) | ✅ | — | Snowflake computes, Qlik displays |
| AI/ML enrichment | ✅ Cortex AI | — | Enriched data flows to Qlik |
