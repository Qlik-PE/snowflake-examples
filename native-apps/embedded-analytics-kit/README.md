# Embedded Analytics Starter Kit

A Snowflake Native App that installs a SaaS-metrics data model, a Semantic View, and a Cortex Agent. After installation, you connect the agent to your own Qlik Cloud MCP server. The result is one assistant that answers metric questions from Snowflake (through Cortex Analyst) and works with Qlik dashboards (through MCP).

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  User (Snowflake Intelligence / SQL / REST API)                      │
│  "What is MRR by segment? Then build me a Qlik chart of it."         │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Cortex Agent  <APP_NAME>.CORE.ANALYTICS_AGENT                       │
├──────────────────────────────────┬───────────────────────────────────┤
│  Tool: SaaSMetrics               │  Qlik MCP server                  │
│  (Cortex Analyst, installed      │  (consumer-owned External MCP     │
│   with the app)                  │   Server, wired after install)    │
│                                  │                                   │
│  Semantic View                   │  Qlik Cloud tenant                │
│  CORE.SAAS_METRICS_SV            │   • app / sheet discovery         │
│   • accounts                     │   • chart and sheet creation      │
│   • subscriptions                │   • master items, bookmarks       │
│   • monthly_revenue              │   • data exploration              │
│   • usage_events                 │                                   │
└──────────────────────────────────┴───────────────────────────────────┘
```

**How the agent routes questions** (from its orchestration instructions):

- **Metric and analysis questions** (MRR, ARR, churn, retention, breakdowns by segment/region/plan/time) → `SaaSMetrics` (Cortex Analyst).
- **Dashboard and visualization requests** (find apps and sheets, create charts, master items, bookmarks) → Qlik MCP tools.
- **Hybrid requests** → query the data first, then build the visualization in Qlik.

## What the App Installs

All objects are created in the app's `CORE` schema by `setup_script.sql`:

| Object | Name | Purpose |
|---|---|---|
| Application role | `APP_USER` | Granted to consumer roles; has access to everything below |
| Tables | `ACCOUNTS`, `SUBSCRIPTIONS`, `MONTHLY_REVENUE`, `USAGE_EVENTS` | Sample SaaS data |
| Semantic View | `SAAS_METRICS_SV` | Cortex Analyst text-to-SQL over the tables |
| Cortex Agent | `ANALYTICS_AGENT` | Shown as **"SaaS Analytics Kit (Qlik + Snowflake)"** |
| Procedure | `REGISTER_REFERENCE` | Callback for the consumer warehouse reference in `manifest.yml` |

### Sample data

The setup script loads a small seed dataset: 20 accounts across 3 segments (Enterprise, Mid-Market, SMB), 4 regions (NA, EMEA, APAC, LATAM) and 10 industries. It also includes one subscription per account, and monthly revenue and usage snapshots for January and April 2024. Replace the `INSERT` statements to load a larger or more realistic dataset.

### Semantic View metrics

| Metric | Definition | Synonyms |
|---|---|---|
| `total_mrr` | `SUM(mrr)` | monthly recurring revenue |
| `total_arr` | `SUM(mrr) * 12` | annual recurring revenue, ARR |
| `total_expansion` | `SUM(expansion_mrr)` | expansion / upsell revenue |
| `total_churn` | `SUM(churned_mrr)` | churned / lost revenue |
| `avg_mrr_per_account` | `AVG(mrr)` | ARPA |
| `active_accounts` | distinct accounts with `status = 'Active'` | paying customers |
| `churned_accounts` | distinct accounts with `status = 'Churned'` | lost customers |
| `avg_logins` | `AVG(logins)` | login frequency |
| `total_api_calls` | `SUM(api_calls)` | API volume |

[`semantic/saas_metrics.yaml`](semantic/saas_metrics.yaml) is a human-readable description of the model. It also defines `net_revenue_retention` and `churn_rate`, which are **not** in the installed Semantic View yet.

## Prerequisites

- A Snowflake account with Cortex Agents and Native Apps enabled.
- `ACCOUNTADMIN`, or a role that can create application packages and grant caller privileges.
- A Qlik MCP External MCP Server and API integration. Create them with [`mcp/create-mcp-agent.sql`](../../mcp/create-mcp-agent.sql).
- Each user must have completed the Qlik OAuth flow (see [Authenticate](#3-authenticate-with-qlik)).

## Install and Configure

### 1. Build and install the app

`manifest.yml` and `setup_script.sql` must sit at the root of the stage:

```sql
CREATE APPLICATION PACKAGE embedded_analytics_pkg;
CREATE SCHEMA embedded_analytics_pkg.v1;
CREATE STAGE  embedded_analytics_pkg.v1.app_stage;

-- From the repo root:
PUT file://native-apps/embedded-analytics-kit/manifest.yml     @embedded_analytics_pkg.v1.app_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://native-apps/embedded-analytics-kit/setup_script.sql @embedded_analytics_pkg.v1.app_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

ALTER APPLICATION PACKAGE embedded_analytics_pkg REGISTER VERSION V1
  USING '@embedded_analytics_pkg.v1.app_stage';
CREATE APPLICATION EMBEDDED_ANALYTICS_KIT
  FROM APPLICATION PACKAGE embedded_analytics_pkg USING VERSION V1;
```

### 2. Run the consumer setup

Edit the `SET` block in [`scripts/consumer_setup.sql`](scripts/consumer_setup.sql) (`APP_NAME`, `WAREHOUSE`, `QLIK_MCP_SERVER`, `USER_ROLE`) and run it. The script:

1. grants the app caller `USAGE` on your warehouse and your Qlik MCP server,
2. replaces the agent specification with one that adds your warehouse (for Cortex Analyst) and your Qlik MCP server (`mcp_servers`),
3. sets the agent's Snowflake Intelligence profile,
4. grants `APP_USER` to your role,
5. runs a test question.

### 3. Authenticate with Qlik

Each user runs [`scripts/authenticate_qlik.sql`](scripts/authenticate_qlik.sql), or directly:

```sql
SELECT SYSTEM$START_USER_OAUTH_FLOW('<your_qlik_mcp_integration>');
```

Open the returned URL, sign in to Qlik and approve. The browser redirect completes the flow.

### 4. Test

[`scripts/test_agent.sql`](scripts/test_agent.sql) runs questions that exercise the Snowflake-only, Qlik-only and hybrid paths, then checks row counts and that the Semantic View and agent exist.

```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'EMBEDDED_ANALYTICS_KIT.CORE.ANALYTICS_AGENT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is ARR by region?"}]}]}'
);
```

In **Snowflake Intelligence**, the agent appears as *SaaS Analytics Kit (Qlik + Snowflake)*.

More questions to try are in [`scripts/sample-questions.md`](scripts/sample-questions.md). It has 18 questions, grouped into hybrid, Qlik-only and Snowflake-only.

## Companion Qlik App (not included)

The Qlik-side questions assume a Qlik Sense app built on the same four tables. This repository doesn't ship that app. A layout that works well:

| Sheet | Content |
|---|---|
| Executive Summary | KPIs (MRR/ARR, accounts, NRR, expansion/churn), trend combo chart, segment / region / industry charts |
| Revenue | MRR trend, segment components, segment × region heatmap, top accounts table |
| Customer Health | Status pie, churn by industry, engagement combo, usage-vs-revenue scatter, filters |
| Subscriptions | Revenue by plan, ARPA and expansion combo, segment bar, pivot, detail table |

## Files

| File | Purpose |
|---|---|
| `manifest.yml` | Native App manifest: version, setup script, warehouse reference |
| `setup_script.sql` | Installs the tables and seed data, the Semantic View, the agent and the grants |
| `semantic/saas_metrics.yaml` | Reference description of the semantic model (not deployed) |
| `agent/agent_spec.yaml` | Reference copy of the agent spec as installed (not deployed) |
| `scripts/consumer_setup.sql` | Post-install setup: caller grants, wires the warehouse and Qlik MCP server into the agent, profile, role grant |
| `scripts/authenticate_qlik.sql` | Starts the per-user Qlik OAuth flow |
| `scripts/test_agent.sql` | Test questions and object checks |
| `scripts/sample-questions.md` | 18 analytical questions for demos |

## Why Both Platforms?

| Capability | Snowflake | Qlik | Together |
|---|---|---|---|
| Ad-hoc SQL (window functions, CTEs, what-if) | ✅ | — | Agent sends complex analysis to Cortex Analyst |
| Dashboards and visualization | — | ✅ | Agent creates charts and sheets on request |
| Governed metrics | ✅ Semantic View | ✅ Master items | The same definitions on both sides |
| Associative exploration and selections | — | ✅ | Agent uses Qlik selections and bookmarks |
| Scale (billions of rows) | ✅ | — | Snowflake computes, Qlik presents |

## Try Qlik Cloud

Want to build your own embedded analytics experience? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics) and pair it with your Snowflake account.
