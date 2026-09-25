# Cortex Code SDK Examples

Agentic AI examples for Snowflake + Qlik operations. Each use case is implemented **twice**:

- as a **Python agent** built on the [Cortex Code Agent SDK](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk) (runs on your machine or server), and
- as a **SQL `CREATE AGENT`** using the server-side Coding Agent (`code_toolset_all`). You call it with `DATA_AGENT_RUN()` or the Cortex Agents REST API.

Choose whichever fits your architecture. The two versions follow the same workflow.

## Why Agents for Qlik + Snowflake Operations

Qlik workloads (reloads, CDC pipelines, data products, cost reviews) span Qlik Cloud and Snowflake. When something goes wrong, the answer usually sits in Snowflake metadata: `QUERY_HISTORY`, `TASK_HISTORY`, `ACCESS_HISTORY` and `INFORMATION_SCHEMA`. These agents query that metadata, reason over the results, and return a structured report with remediation SQL. Qlik Automate or any backend can trigger them.

| Problem | What the agent does |
|---|---|
| A Qlik reload or Replicate task failed | Finds the failing Snowflake queries, identifies the root cause, and returns remediation SQL |
| Snowflake spend from Qlik workloads is too high | Attributes credits by warehouse and query, then recommends resizing or rescheduling |
| A Qlik Data Product and its Semantic View have drifted apart | Diffs columns and types, runs verified queries, and generates reconciliation DDL |
| A pipeline is about to run | Checks objects, grants, warehouse state and dynamic-table health, and returns GO / NO_GO |
| A Qlik service role is over-privileged | Compares grants with actual `ACCESS_HISTORY` and returns REVOKE/GRANT SQL with a risk rating for each |

## Directory Layout

```
cortex-code-sdk/
├── sdk/                                   # Python agents (Cortex Code Agent SDK)
│   ├── README.md                          #   setup, per-agent usage and output contracts
│   ├── rca_agent.py
│   ├── workload_cost_agent.py
│   ├── semantic_drift_agent.py
│   ├── preflight_validator_agent.py
│   ├── sql_optimizer_agent.py
│   ├── data_freshness_agent.py
│   ├── access_audit_agent.py
│   └── tpch_cost_optimize_example.py      #   end-to-end: cost → optimize → cost
├── sql/                                   # CREATE AGENT equivalents (code_toolset_all)
│   ├── rca-agent.sql
│   ├── workload-cost-agent.sql
│   ├── semantic-drift-agent.sql
│   ├── preflight-validator-agent.sql
│   ├── sql-optimizer-agent.sql
│   ├── data-freshness-agent.sql
│   ├── access-audit-agent.sql
│   └── doc-intelligence-agent.sql         #   SQL only
├── tpch-cost-optimization-walkthrough.md
└── cortex-code-agent-sdk-docs.md          # local copy of the SDK docs
```

## Use Cases

| Use case | Python (SDK) | SQL (CREATE AGENT) |
|---|---|---|
| **Failure root-cause analysis**: investigate Snowflake-side failures behind a failed Qlik reload or CDC task | [rca_agent.py](sdk/rca_agent.py) | [rca-agent.sql](sql/rca-agent.sql) |
| **Workload cost attribution**: attribute credits to Qlik workloads and recommend optimizations | [workload_cost_agent.py](sdk/workload_cost_agent.py) | [workload-cost-agent.sql](sql/workload-cost-agent.sql) |
| **Semantic view drift**: compare a Qlik Data Product with its Semantic View and produce reconciliation DDL | [semantic_drift_agent.py](sdk/semantic_drift_agent.py) | [semantic-drift-agent.sql](sql/semantic-drift-agent.sql) |
| **Pipeline pre-flight validation**: check objects, grants, warehouse state and dynamic tables before a run | [preflight_validator_agent.py](sdk/preflight_validator_agent.py) | [preflight-validator-agent.sql](sql/preflight-validator-agent.sql) |
| **SQL optimization**: reformat and rewrite a query following Snowflake best practices | [sql_optimizer_agent.py](sdk/sql_optimizer_agent.py) | [sql-optimizer-agent.sql](sql/sql-optimizer-agent.sql) |
| **Data freshness SLA monitoring**: find stale tables and diagnose why with `TASK_HISTORY` | [data_freshness_agent.py](sdk/data_freshness_agent.py) | [data-freshness-agent.sql](sql/data-freshness-agent.sql) |
| **Access audit / least privilege**: find over-privileged roles, unused grants and anomalies | [access_audit_agent.py](sdk/access_audit_agent.py) | [access-audit-agent.sql](sql/access-audit-agent.sql) |
| **Document intelligence**: parse, extract, classify and summarize staged documents with Cortex AI functions | — | [doc-intelligence-agent.sql](sql/doc-intelligence-agent.sql) |

**End-to-end walkthrough:** [TPCH SF100 Cost → Optimize → Cost](tpch-cost-optimization-walkthrough.md) chains the Workload Cost and SQL Optimizer agents against a 600M-row dataset. It runs a deliberately inefficient query, measures its cost, optimizes it, and measures again. Script: [tpch_cost_optimize_example.py](sdk/tpch_cost_optimize_example.py).

## Python SDK vs. SQL Agent

| | Python (SDK) | SQL agent (`CREATE AGENT` + REST) |
|---|---|---|
| **Runs** | In a Python process you host | Inside Snowflake; nothing to host |
| **Install** | `pip install cortex-code-agent-sdk pydantic` + Cortex Code CLI | Nothing. Run the DDL once |
| **Invoke** | `query()` or `CortexCodeSDKClient` | `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` or `POST …/agents/<name>:run` |
| **Multi-turn** | Native, through the client session | Pass `thread_id` / `parent_message_id` between calls |
| **Structured output** | Enforced with `output_format` (JSON Schema) and validated with Pydantic | Guided by `instructions.response` only; the caller parses the text |
| **Audit hooks** | `PreToolUse` / `PostToolUse` callbacks | Not available; use `QUERY_HISTORY` or an event table |
| **Tool approval** | `allowed_tools` or a custom callback | `permission_policy` (these examples use `always_allow`) |
| **Scheduling** | cron, Qlik Automate + a backend, any scheduler | `CREATE TASK` calling `DATA_AGENT_RUN()`, or Qlik Automate calling REST directly |
| **Best for** | Client-side validation, audit logging, custom orchestration | Zero-infrastructure, SQL-native, REST-driven integrations |

> **Security:** the SQL agents use `code_toolset_all` with `permission_policy: always_allow`. They can run any SQL the caller's role allows, without asking first. Run them under a role that has only the privileges the use case needs, especially the access-audit and pre-flight agents, which generate `REVOKE`/`GRANT`/`ALTER` statements.

## Calling the SQL Agents over REST

Every SQL file includes commented `curl` examples. Set `$SNOWFLAKE_ACCOUNT_BASE_URL` to `https://<orgname>-<account_name>.snowflakecomputing.com`, and `$PAT` to a [programmatic access token](https://docs.snowflake.com/en/user-guide/admin-user-management#programmatic-access-tokens).

```bash
curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/RCA_AGENT:run" \
  --header 'Content-Type: application/json' \
  --header 'Accept: text/event-stream' \
  --header "Authorization: Bearer $PAT" \
  --data '{
    "messages": [
      { "role": "user",
        "content": [{ "type": "text", "text": "Investigate failures on warehouse QLIK_WH in the last 30 minutes." }] }
    ]
  }'
```

- **Single JSON response instead of a stream:** set `"stream": false` and `Accept: application/json`.
- **Multi-turn:** send `"thread_id": 0, "parent_message_id": 0` on the first call, then pass the returned `thread_id` and assistant message ID on the next call.
- **Long runs:** set `"background": true` for tasks that may exceed the 15-minute REST timeout.

The examples create agents in `CORTEX_CODE.PUBLIC` by default. Change `TARGET_DATABASE` / `TARGET_SCHEMA` at the top of each SQL file, and update the call examples to match.

## References

- [Cortex Code Agent SDK](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk): [Quickstart](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/quickstart), [Python reference](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/python-reference), [TypeScript reference](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/typescript-reference), and a [local copy](cortex-code-agent-sdk-docs.md) of the docs
- [Coding Agent (`code_toolset_all`)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-coding-agent), the server-side equivalent
- [`DATA_AGENT_RUN`](https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex)
- [Cortex Agents Run REST API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run)
- [Cortex Code product page](https://www.snowflake.com/en/product/features/cortex-code/)
- [SDK setup, per-agent usage and output contracts](sdk/README.md)
