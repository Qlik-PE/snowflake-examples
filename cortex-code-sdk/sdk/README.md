# Cortex Code Agent SDK — Qlik Integration Prototypes

Python prototypes that show how a Qlik integration can hand Snowflake-platform
work to the [Cortex Code Agent SDK](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk).
The SDK runs a sandboxed agent session that can execute SQL, run Python,
read and write files, and reason over several steps against your Snowflake
account. Each script returns a Pydantic-validated JSON report.

For the SQL (`CREATE AGENT`) versions of the same agents, and a comparison of
the two approaches, see the [parent README](../README.md).

## Setup

```bash
cd cortex-code-sdk/sdk
python3 -m venv .venv
source .venv/bin/activate
pip install cortex-code-agent-sdk pydantic
```

The SDK requires the [Cortex Code CLI](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli)
on your `PATH`. If it is installed elsewhere, set `CORTEX_CODE_CLI_PATH=/path/to/cortex`.

A Snowflake connection must be configured in `~/.snowflake/connections.toml`:

```toml
[my-connection]
account = "myorg-myaccount"
user = "myuser"
authenticator = "externalbrowser"
```

The SDK uses the default connection unless you override it in code. The role
behind that connection needs read access to `SNOWFLAKE.ACCOUNT_USAGE` for most
of these agents.

> **Latency:** `SNOWFLAKE.ACCOUNT_USAGE` views lag real time, by up to about
> 45 minutes for `QUERY_HISTORY` and `TASK_HISTORY`. The RCA, freshness and
> TPCH cost prompts therefore tell the agent to use the real-time
> `INFORMATION_SCHEMA` table functions for recent activity.

## Prototypes

### `rca_agent.py` — Reload / CDC Failure Root-Cause Investigator

When a Qlik reload or Replicate task fails, this script launches a CoCo agent
session that investigates the Snowflake side and returns a structured JSON report
with root cause and remediation SQL.

Goal: *"Cross-system triage arrives solved instead of started."*

#### How it works

```
Qlik (webhook / event)
        │
        ▼
┌──────────────────────┐
│  rca_agent            │  ← Python script embedding the SDK
│                      │
│  1. Receives failure │
│     context          │
│  2. Launches CoCo    │
│     agent session    │
│  3. Agent queries    │
│     QUERY_HISTORY,   │
│     WAREHOUSE_EVENTS │
│  4. Returns struct.  │
│     JSON report      │
└──────────────────────┘
        │
        ▼
  Qlik REST API
  (post result back)
```

#### SDK features used

| Feature | How it is used |
|---|---|
| `query()` | Single-shot agentic workflow |
| `allowed_tools=["SQL"]` | Auto-approves the SQL tool so the agent queries Snowflake without prompting |
| `system_prompt` | Injects Snowflake domain knowledge and investigation guidelines |
| `output_format` | Pydantic-derived JSON Schema forces the agent to return machine-readable output |
| `max_turns=15` | Caps the agent's reasoning loop |

#### Usage

```bash
# Default: investigate all warehouses, last 30 minutes
python rca_agent.py

# Targeted investigation
python rca_agent.py \
    --warehouse QLIK_WH \
    --minutes 60 \
    --error "timeout"
```

| Argument | Default | Description |
|---|---|---|
| `--warehouse` | `*` (all) | Snowflake warehouse to filter on |
| `--minutes` | `30` | Lookback window in minutes |
| `--error` | `"unknown failure"` | Error hint from the Qlik alert |

#### Output contract

The agent returns an `RCAReport` JSON object:

```json
{
  "summary": "3 queries failed with OBJECT_NOT_FOUND on STAGING.RAW.EVENTS",
  "root_cause": "Table STAGING.RAW.EVENTS was dropped at 14:02 UTC",
  "severity": "high",
  "failed_queries": [
    {
      "query_id": "01b2c3d4-...",
      "query_text": "INSERT INTO staging.raw.events ...",
      "error_message": "Object 'STAGING.RAW.EVENTS' does not exist",
      "user_name": "QLIK_SVC",
      "warehouse_name": "QLIK_WH",
      "execution_time_s": 0.12
    }
  ],
  "remediations": [
    {
      "description": "Restore the dropped table from Time Travel",
      "sql": "UNDROP TABLE STAGING.RAW.EVENTS;"
    }
  ]
}
```

This is the contract that a Qlik integration would consume via HTTP and
surface in the Management Console.

### `workload_cost_agent.py` — Workload Cost Attribution Agent

Queries `SNOWFLAKE.ACCOUNT_USAGE` to attribute Snowflake credit consumption to
Qlik-originated workloads. Returns a structured cost breakdown by warehouse,
identifies the most expensive queries, and provides optimization recommendations
with estimated savings.

Goal: *"Qlik makes your Snowflake cheaper, with evidence."*

#### SDK features used

| Feature | How it is used |
|---|---|
| `query()` | Single-shot agentic workflow |
| `allowed_tools=["SQL"]` | Auto-approved SQL for ACCOUNT_USAGE queries |
| `system_prompt` | FinOps domain expertise injection |
| `output_format` | Pydantic `CostReport` schema with per-warehouse breakdown |
| `max_turns=15` | Caps the reasoning loop |

#### Usage

```bash
# Default: all users/warehouses, last 7 days
python workload_cost_agent.py

# Targeted
python workload_cost_agent.py --days 7 --user QLIK_SVC --warehouse QLIK_WH
```

| Argument | Default | Description |
|---|---|---|
| `--days` | `7` | Lookback period in days |
| `--user` | `*` (all) | Snowflake user to filter on |
| `--warehouse` | `*` (all) | Warehouse to filter on |

#### Output contract

```json
{
  "summary": "QLIK_WH consumed 142.5 credits over 7 days, 68% during off-peak hours",
  "total_credits": 142.5,
  "period_days": 7,
  "by_warehouse": [
    {
      "warehouse_name": "QLIK_WH",
      "total_credits": 142.5,
      "query_count": 8420,
      "avg_execution_time_s": 3.2,
      "peak_hour_utc": 14
    }
  ],
  "top_expensive_queries": [ ... ],
  "recommendations": [
    {
      "category": "scheduling",
      "description": "Shift 3 large reload jobs from 14:00 to 02:00 UTC to avoid contention",
      "estimated_savings_pct": 15.0,
      "sql": "ALTER TASK reload_daily SET SCHEDULE = 'USING CRON 0 2 * * * UTC';"
    }
  ]
}
```

---

### `semantic_drift_agent.py` — Semantic View Drift Checker

Multi-turn agent that compares a Qlik Data Product definition against a Snowflake
semantic view. Detects drift (added/removed columns, type mismatches, broken
verified queries) and returns a structured diff with reconciliation DDL.

Goal: *"Qlik data products natively consumable by Cortex Agents."*

#### SDK features used

| Feature | How it is used |
|---|---|
| `CortexCodeSDKClient` | Multi-turn session: turn 1 discovers + compares, turn 2 validates verified queries |
| `allowed_tools=["SQL"]` | Auto-approved SQL for DESCRIBE and query execution |
| `system_prompt` | Semantic layer domain expertise |
| `output_format` | Pydantic `DriftReport` schema (applied on the final turn only) |

#### Usage

```bash
python semantic_drift_agent.py --semantic-view "ANALYTICS.PUBLIC.SALES_SV"

# With expected Qlik Data Product fields
python semantic_drift_agent.py \
    --semantic-view "ANALYTICS.PUBLIC.SALES_SV" \
    --expected-fields "revenue:NUMBER,customer_id:VARCHAR,order_date:DATE"
```

| Argument | Default | Description |
|---|---|---|
| `--semantic-view` | (required) | Fully qualified semantic view name |
| `--expected-fields` | (empty) | Comma-separated `field:type` pairs from the Qlik Data Product |

#### Output contract

```json
{
  "summary": "2 column drifts detected, 1 verified query failing",
  "semantic_view": "ANALYTICS.PUBLIC.SALES_SV",
  "underlying_table": "ANALYTICS.PUBLIC.SALES",
  "drift_detected": true,
  "column_drifts": [
    {
      "column_name": "DISCOUNT_PCT",
      "drift_type": "added",
      "expected": "not present",
      "actual": "NUMBER(5,2) in underlying table"
    }
  ],
  "verified_query_results": [
    {
      "query_name": "monthly_revenue",
      "status": "passed",
      "error_message": "",
      "row_count": 24
    }
  ],
  "reconciliation_actions": [
    {
      "description": "Add DISCOUNT_PCT to the semantic view",
      "ddl": "ALTER SEMANTIC VIEW ANALYTICS.PUBLIC.SALES_SV ADD COLUMN ..."
    }
  ]
}
```

---

### `preflight_validator_agent.py` — Pipeline Pre-Flight Validator

Before a Qlik Declarative Pipeline runs, this agent checks the Snowflake side:
target objects exist, the service role has required grants, warehouses are running,
and dynamic tables are healthy. Returns a structured GO / NO_GO report with
remediation SQL.

Goal: *"Review becomes approval rather than debugging."*

#### SDK features used

| Feature | How it is used |
|---|---|
| `query()` | Single-shot agentic workflow |
| `allowed_tools=["SQL"]` | Auto-approved SQL for SHOW GRANTS, DESCRIBE, etc. |
| `system_prompt` | Snowflake operations expertise |
| `output_format` | Pydantic `PreFlightReport` with GO/NO_GO verdict |
| `hooks` (`PreToolUse`) | Logs every SQL statement to an audit trail for compliance |
| `max_turns=20` | Higher cap since the agent checks multiple object categories |

#### Usage

```bash
python preflight_validator_agent.py \
    --database STAGING \
    --schema RAW \
    --role QLIK_ROLE \
    --warehouse QLIK_WH
```

| Argument | Default | Description |
|---|---|---|
| `--database` | (required) | Target Snowflake database |
| `--schema` | (required) | Target Snowflake schema |
| `--role` | (required) | Service role the pipeline runs as |
| `--warehouse` | (required) | Warehouse the pipeline uses |

#### Output contract

```json
{
  "summary": "2 issues found: warehouse suspended, missing SELECT on EVENTS",
  "go_no_go": "NO_GO",
  "checked_at_utc": "2026-09-14T18:30:00Z",
  "object_checks": [ ... ],
  "grant_checks": [
    {
      "privilege": "SELECT",
      "object_name": "STAGING.RAW.EVENTS",
      "granted": false,
      "issue": "Role QLIK_ROLE lacks SELECT on STAGING.RAW.EVENTS"
    }
  ],
  "warehouse_checks": [
    {
      "warehouse_name": "QLIK_WH",
      "state": "SUSPENDED",
      "size": "MEDIUM",
      "issue": "Warehouse is suspended"
    }
  ],
  "dynamic_table_checks": [ ... ],
  "remediations": [
    {
      "description": "Grant SELECT on the missing table",
      "sql": "GRANT SELECT ON TABLE STAGING.RAW.EVENTS TO ROLE QLIK_ROLE;"
    },
    {
      "description": "Resume the warehouse",
      "sql": "ALTER WAREHOUSE QLIK_WH RESUME;"
    }
  ]
}
```

The pre-flight agent also records every SQL statement it runs through a
`PreToolUse` hook. It prints an `[AUDIT]` line to stderr for each statement as it
runs, and the full audit log (JSON) at the end.

---

### `sql_optimizer_agent.py` — SQL Optimizer Agent

Accepts a raw SQL query, analyzes it against Snowflake best practices, and
returns a properly formatted and optimized version. The agent inspects the
query plan (via EXPLAIN when a warehouse is provided), checks for common
anti-patterns, and produces a structured report with the rewritten SQL,
each optimization explained, and estimated impact.

Goal: *"Every query Qlik generates runs at peak Snowflake efficiency."*

#### SDK features used

| Feature | How it is used |
|---|---|
| `CortexCodeSDKClient` | Multi-turn: turn 1 analyzes the query, turn 2 rewrites and validates |
| `allowed_tools=["SQL"]` | Auto-approved SQL for EXPLAIN and validation queries |
| `system_prompt` | Snowflake SQL optimization and formatting rules |
| `output_format` | Pydantic `OptimizationReport` with per-optimization detail |

#### Usage

```bash
# Inline query
python sql_optimizer_agent.py --query "SELECT * FROM orders WHERE order_date > '2024-01-01'"

# From a .sql file
python sql_optimizer_agent.py --file ./slow_query.sql

# With EXPLAIN analysis
python sql_optimizer_agent.py --file ./slow_query.sql --warehouse ANALYTICS_WH
```

| Argument | Default | Description |
|---|---|---|
| `--query` | (mutually exclusive with `--file`) | SQL query string to optimize |
| `--file` | (mutually exclusive with `--query`) | Path to a `.sql` file |
| `--warehouse` | (empty) | Warehouse for EXPLAIN analysis (optional) |

#### Output contract

```json
{
  "summary": "5 optimizations applied: 2 high-impact, 2 medium, 1 cosmetic",
  "original_query": "SELECT * FROM orders o, customers c WHERE ...",
  "optimized_query": "SELECT\n  o.order_id,\n  o.order_date,\n  ...",
  "formatting_only": false,
  "optimization_count": 5,
  "optimizations": [
    {
      "category": "anti_pattern",
      "description": "Replace SELECT * with explicit column list to reduce I/O and improve pruning",
      "before": "SELECT *",
      "after": "SELECT o.order_id, o.order_date, o.total_amount, c.customer_name",
      "impact": "high"
    },
    {
      "category": "join",
      "description": "Convert implicit comma-join to explicit INNER JOIN for clarity and optimizer hints",
      "before": "FROM orders o, customers c WHERE o.customer_id = c.id",
      "after": "FROM orders AS o\n  INNER JOIN customers AS c\n    ON o.customer_id = c.id",
      "impact": "medium"
    },
    {
      "category": "type_cast",
      "description": "Add explicit DATE cast to string literal to enable partition pruning",
      "before": "WHERE order_date > '2024-01-01'",
      "after": "WHERE order_date > '2024-01-01'::DATE",
      "impact": "high"
    }
  ],
  "warnings": [
    {
      "severity": "info",
      "message": "Consider adding a clustering key on ORDER_DATE if this filter pattern is frequent",
      "line_reference": "WHERE clause"
    }
  ],
  "estimated_improvement": "Partition pruning now effective on ORDER_DATE; expect 60-80% fewer micro-partitions scanned"
}
```

---

### `data_freshness_agent.py` — Data Freshness SLA Monitor

Scheduled agent that checks whether Qlik-managed tables meet their freshness
SLAs. Queries INFORMATION_SCHEMA and TASK_HISTORY to compute staleness, diagnose
why tables fell behind, and returns a structured report with SLA violations and
remediation SQL (resume tasks, adjust schedules).

Goal: *"Qlik pipelines are always on time, with evidence."*

#### SDK features used

| Feature | How it is used |
|---|---|
| `CortexCodeSDKClient` | Multi-turn session: turn 1 measures freshness, turn 2 diagnoses root causes |
| `allowed_tools=["SQL"]` | Auto-approved SQL for metadata and task history queries |
| `system_prompt` | Data operations expertise |
| `output_format` | Pydantic `FreshnessReport` with per-table staleness and root causes |

#### Usage

```bash
python data_freshness_agent.py --database ANALYTICS --schema PUBLIC --sla-hours 4

# With tag filtering
python data_freshness_agent.py --database STAGING --schema RAW --sla-hours 1 --tag QLIK_MANAGED
```

| Argument | Default | Description |
|---|---|---|
| `--database` | (required) | Target Snowflake database |
| `--schema` | (required) | Target Snowflake schema |
| `--sla-hours` | `4.0` | Maximum acceptable staleness in hours |
| `--tag` | (empty) | Optional Snowflake tag to filter tables |

#### Output contract

```json
{
  "summary": "3 of 15 tables violating 4h SLA; 2 due to suspended tasks",
  "database": "ANALYTICS",
  "schema_name": "PUBLIC",
  "sla_hours": 4.0,
  "total_tables": 15,
  "tables_meeting_sla": 12,
  "tables_violating_sla": 3,
  "table_details": [
    {
      "table_name": "ANALYTICS.PUBLIC.ORDERS",
      "last_altered": "2026-09-14T08:15:00Z",
      "hours_stale": 6.5,
      "sla_hours": 4.0,
      "sla_met": false,
      "row_count": 1420000
    }
  ],
  "root_causes": [
    {
      "table_name": "ANALYTICS.PUBLIC.ORDERS",
      "cause": "task_suspended",
      "last_task_run": "2026-09-14T02:00:00Z",
      "task_name": "RELOAD_ORDERS_TASK",
      "error_message": ""
    }
  ],
  "remediations": [
    {
      "description": "Resume the suspended reload task",
      "sql": "ALTER TASK ANALYTICS.PUBLIC.RELOAD_ORDERS_TASK RESUME;"
    }
  ]
}
```

---

### `access_audit_agent.py` — Access Audit Agent

Audits Snowflake access patterns for Qlik service accounts. Identifies
over-privileged roles, unused grants, and access anomalies by cross-referencing
SHOW GRANTS against ACCESS_HISTORY. Returns a security report with least-privilege
recommendations and ready-to-run REVOKE/GRANT SQL.

Goal: *"Every Qlik service account is least-privilege, with evidence."*

#### SDK features used

| Feature | How it is used |
|---|---|
| `CortexCodeSDKClient` | Multi-turn: turn 1 inventories grants, turn 2 cross-references with usage |
| `allowed_tools=["SQL"]` | Auto-approved SQL for SHOW GRANTS and ACCOUNT_USAGE queries |
| `system_prompt` | Security domain expertise |
| `output_format` | Pydantic `AccessAuditReport` with per-grant used/unused status |
| `hooks` (`PreToolUse`) | Logs every SQL statement to an audit trail for compliance |

#### Usage

```bash
python access_audit_agent.py --role QLIK_ROLE

# Targeted audit
python access_audit_agent.py --role QLIK_ROLE --user QLIK_SVC --days 30
```

| Argument | Default | Description |
|---|---|---|
| `--role` | (required) | Snowflake role to audit |
| `--user` | `*` (all) | Specific user to audit |
| `--days` | `30` | Lookback period in days |

#### Output contract

```json
{
  "summary": "QLIK_ROLE has 47 grants, 12 unused in the last 30 days; 1 critical anomaly",
  "role": "QLIK_ROLE",
  "user": "QLIK_SVC",
  "audit_period_days": 30,
  "total_grants": 47,
  "used_grants": 35,
  "unused_grants": 12,
  "anomaly_count": 1,
  "grant_details": [ ... ],
  "anomalies": [
    {
      "anomaly_type": "admin_grant",
      "description": "QLIK_ROLE inherits SYSADMIN through intermediate role DBA_ROLE",
      "severity": "critical",
      "object_name": "SYSADMIN"
    }
  ],
  "recommendations": [
    {
      "action": "revoke",
      "description": "Remove unused SELECT on STAGING.RAW.LEGACY_EVENTS (not accessed in 30d)",
      "sql": "REVOKE SELECT ON TABLE STAGING.RAW.LEGACY_EVENTS FROM ROLE QLIK_ROLE;",
      "risk": "safe"
    }
  ]
}
```

The access audit agent records its SQL the same way as the pre-flight agent.

---

## Integration architecture

### Approach 1: Cortex Code Agent SDK (this folder)

The SDK is designed for asynchronous, authoring-style workflows (30-90 second
sessions), not sub-second interactions. The recommended integration pattern is:

1. A **Qlik event** (webhook, scheduled trigger, or pipeline failure) fires
2. A lightweight **backend service** (Flask, FastAPI, Lambda) receives the event
   and calls the SDK
3. The SDK returns structured JSON
4. The service posts the result back via the **Qlik REST API**

Auth is either a scoped Snowflake service account or user OAuth. Snowflake
governance, audit trail, and RBAC remain intact — CoCo is a specialist tool
behind the Qlik agent, not a replacement for it.

### Approach 2: Cortex Agent + REST API (no Python)

Every prototype also exists as a SQL `CREATE AGENT` in [`../sql/`](../sql/). It runs
entirely inside Snowflake and can be called from Qlik Automate or any HTTP
client. See the [parent README](../README.md#python-sdk-vs-sql-agent) for a
side-by-side comparison.

## SDK feature coverage across prototypes

Each prototype demonstrates different SDK capabilities to serve as reference
implementations:

| SDK Feature | RCA Agent | Cost Agent | Drift Checker | Pre-Flight | SQL Optimizer | Freshness SLA | Access Audit |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `query()` (single-shot) | x | x | | x | | | |
| `CortexCodeSDKClient` (multi-turn) | | | x | | x | x | x |
| `allowed_tools` | x | x | x | x | x | x | x |
| `system_prompt` | x | x | x | x | x | x | x |
| `output_format` (structured output) | x | x | x | x | x | x | x |
| `hooks` (`PreToolUse`) | | | | x | | | x |
| `max_turns` | x | x | | x | | | |
| Pydantic schema validation | x | x | x | x | x | x | x |
| EXPLAIN plan analysis | | | | | x | | |
| Tag-based filtering | | | | | | x | |
| Cross-reference (grants vs usage) | | | | | | | x |

## Further use cases

These are candidates for future prototypes, ordered by integration effort:

| Use case | Value | Effort | Status |
|---|---|---|---|
| Reload / CDC failure root-cause | Cross-system triage arrives solved | Low | **Done** |
| Workload economics | "Qlik makes your Snowflake cheaper," with evidence | Medium | **Done** |
| Data products to Snowflake semantic views | Qlik data products consumable by Cortex Agents | Medium | **Done** |
| Pipeline pre-flight validation | Review becomes approval rather than debugging | Medium | **Done** |
| SQL optimization | Every query runs at peak Snowflake efficiency | Low-Medium | **Done** |
| Data freshness SLA monitoring | Qlik pipelines are always on time, with evidence | Medium | **Done** |
| Access audit / least-privilege | Every service account is least-privilege, with evidence | Medium | **Done** |
| Agent fleet delegation | Every Qlik agent is better on Snowflake | High | Candidate |

## End-to-end walkthroughs

| Example | Agents chained | Script |
|---|---|---|
| [TPCH SF100 Cost → Optimize → Cost](../tpch-cost-optimization-walkthrough.md) | Workload Cost + SQL Optimizer | [tpch_cost_optimize_example.py](tpch_cost_optimize_example.py) |
