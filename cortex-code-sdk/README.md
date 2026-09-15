# Cortex Code SDK

Agentic AI examples for Snowflake + Qlik integrations. Every use case is implemented twice — once as a Python SDK agent and once as a SQL `CREATE AGENT` object — so you can choose the approach that fits your architecture.

## Directory Layout

```
cortex-code-sdk/
├── sdk/                # Python agents using the Cortex Code Agent SDK
│   ├── snowflake_rca_agent.py
│   ├── workload_cost_agent.py
│   ├── semantic_drift_agent.py
│   ├── preflight_validator_agent.py
│   ├── sql_optimizer_agent.py
│   ├── data_freshness_agent.py
│   ├── access_audit_agent.py
│   └── README.md       # SDK setup, architecture, feature coverage matrix
├── sql/                # SQL CREATE AGENT equivalents (code_toolset_all)
│   ├── rca-agent.sql
│   ├── workload-cost-agent.sql
│   ├── semantic-drift-agent.sql
│   ├── preflight-validator-agent.sql
│   ├── sql-optimizer-agent.sql
│   ├── data-freshness-agent.sql
│   ├── access-audit-agent.sql
│   └── doc-intelligence-agent.sql
```

## Use Cases

| Use case | SDK (Python) | SQL (CREATE AGENT) |
|---|---|---|
| **Failure root-cause analysis** — investigate Snowflake-side failures when a Qlik reload or CDC pipeline errors out | [snowflake_rca_agent.py](sdk/snowflake_rca_agent.py) | [rca-agent.sql](sql/rca-agent.sql) |
| **Workload cost attribution** — attribute credit consumption to Qlik-originated workloads, recommend optimizations | [workload_cost_agent.py](sdk/workload_cost_agent.py) | [workload-cost-agent.sql](sql/workload-cost-agent.sql) |
| **Semantic view drift** — compare Qlik Data Product definitions against Snowflake semantic views, produce reconciliation DDL | [semantic_drift_agent.py](sdk/semantic_drift_agent.py) | [semantic-drift-agent.sql](sql/semantic-drift-agent.sql) |
| **Pipeline pre-flight validation** — check object existence, grants, warehouse state, and dynamic table health before a pipeline runs | [preflight_validator_agent.py](sdk/preflight_validator_agent.py) | [preflight-validator-agent.sql](sql/preflight-validator-agent.sql) |
| **SQL optimization** — analyze and rewrite SQL queries following Snowflake best practices | [sql_optimizer_agent.py](sdk/sql_optimizer_agent.py) | [sql-optimizer-agent.sql](sql/sql-optimizer-agent.sql) |
| **Data freshness SLA monitoring** — detect stale tables, diagnose root causes via TASK_HISTORY | [data_freshness_agent.py](sdk/data_freshness_agent.py) | [data-freshness-agent.sql](sql/data-freshness-agent.sql) |
| **Access audit / least-privilege** — identify over-privileged roles, unused grants, and access anomalies | [access_audit_agent.py](sdk/access_audit_agent.py) | [access-audit-agent.sql](sql/access-audit-agent.sql) |
| **Document intelligence** — parse, extract, classify, and answer questions about documents using Cortex AI functions | — | [doc-intelligence-agent.sql](sql/doc-intelligence-agent.sql) |

## SDK (Python) vs Cortex Agent (SQL + REST API)

| | SDK (Python) | Cortex Agent (SQL + REST API) |
|---|---|---|
| **Runtime** | Python process on your machine or server | Snowflake-managed; no external process |
| **Invocation** | `query()` / `CortexCodeSDKClient` in Python | `DATA_AGENT_RUN()` SQL function or `POST /api/v2/cortex/agent:run` |
| **Deployment** | `pip install cortex-code-agent-sdk` + Cortex Code CLI | `CREATE AGENT` DDL; nothing to install |
| **Multi-turn** | Native via `CortexCodeSDKClient` context | Pass `thread_id` / `parent_message_id` across REST calls |
| **Hooks** | `PreToolUse`, `PostToolUse`, `Stop` callbacks in Python | Not available server-side; use event tables or query history for audit |
| **Structured output** | `output_format` with JSON Schema; validated client-side with Pydantic | Not available in the agent spec; parse the response JSON |
| **Tool approval** | `allowed_tools` auto-approves; `canUseTool` callback for custom logic | `permission_policy: always_allow` or interactive approval via REST |
| **Scheduling** | Cron, Qlik Automate, or any scheduler that can run Python | `CREATE TASK` with `DATA_AGENT_RUN()`, or Cortex Code `/automation` |
| **Best for** | Complex orchestration, client-side validation, hook-driven audit logging | Headless/server-side execution, SQL-native teams, scheduled tasks, REST integrations |

### Key Differences

**Hooks and audit logging.** The SDK agents (`preflight_validator_agent.py`, `access_audit_agent.py`) use a `PreToolUse` hook to log every SQL statement. The SQL agents do not have this server-side. For audit logging, query `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` filtered by the agent's session, or configure an event table.

**Structured output.** SDK agents enforce a JSON Schema via `output_format` and validate with Pydantic. The SQL agents receive the full response as JSON from `DATA_AGENT_RUN()` — the caller parses it. The agent's `instructions.response` guides formatting but does not enforce a schema.

**Multi-turn conversations.** SDK agents using `CortexCodeSDKClient` maintain context across turns natively. SQL agents achieve the same by passing `thread_id` and `parent_message_id` in consecutive calls.

**When to use which.** Use the SDK when you need client-side control: hooks, Pydantic validation, custom orchestration, or integration into a Python app. Use the SQL agent for zero-infrastructure deployment callable from Snowflake Tasks, stored procedures, Qlik Automate REST actions, or any HTTP client.

## Calling Agents via the REST API

Every SQL agent file includes commented `curl` examples. Replace `$SNOWFLAKE_ACCOUNT_BASE_URL` with your account URL (`https://<orgname>-<account_name>.snowflakecomputing.com`) and `$PAT` with a [programmatic access token](https://docs.snowflake.com/en/user-guide/admin-user-management#programmatic-access-tokens).

**Single-turn (streaming SSE):**

```bash
curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/RCA_AGENT:run" \
  --header 'Content-Type: application/json' \
  --header 'Accept: text/event-stream' \
  --header "Authorization: Bearer $PAT" \
  --data '{
    "messages": [
      {
        "role": "user",
        "content": [{ "type": "text", "text": "Investigate failures on warehouse QLIK_WH in the last 30 minutes." }]
      }
    ]
  }'
```

**Non-streaming JSON:** Set `"stream": false` and `Accept: application/json`.

**Multi-turn with threads:** Pass `"thread_id": 0, "parent_message_id": 0` on the first call. Use the `thread_id` and `assistant_message_id` from the response to continue.

**Background runs:** Set `"background": true` for tasks exceeding the 15-minute REST timeout.

For the full API reference, see [Cortex Agents Run API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run).

## References

- [Cortex Code Agent SDK documentation](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk) (also saved locally in [cortex-code-agent-sdk-docs.md](cortex-code-agent-sdk-docs.md))
- [Coding Agent (code_toolset_all)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-coding-agent)
- [DATA_AGENT_RUN SQL function](https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex)
- [Cortex Agents Run REST API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run)
- [SDK setup and feature coverage](sdk/README.md)
