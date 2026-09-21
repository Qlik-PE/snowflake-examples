# Qlik Automate → Snowflake Cortex Agent Orchestration

A Qlik Automate workflow that calls a Snowflake Cortex Agent via the REST API to monitor data freshness SLAs, routes alerts on breach (Slack/Teams/email), triggers Qlik app reloads as remediation, and writes audit records back to Snowflake.

## Architecture

```
Qlik Automate (scheduled every 4h)
  |
  |  1. POST /api/v2/.../agents/QLIK_AUTOMATE_FRESHNESS_AGENT:run
  |     (Generic REST block, Bearer token auth)
  v
Snowflake Cortex Agent
  |-- Queries INFORMATION_SCHEMA.TABLES (staleness)
  |-- Queries ACCOUNT_USAGE.TASK_HISTORY (root cause)
  |-- Returns structured JSON
  |
  v
Qlik Automate (parse + branch)
  |
  |-- status: "ok"     → write audit record → done
  |
  |-- status: "breach" → send Slack alert
  |                     → reload Qlik app (remediation)
  |                     → write audit record → done
  v
Snowflake: FRESHNESS_AUDIT_LOG table
  (historical trend data for dashboarding)
```

## What's Included

| File | Description |
|------|-------------|
| [setup.sql](setup.sql) | Creates the Cortex Agent (structured JSON output, optimized for machine consumption), the audit table, and includes curl examples matching the exact call Qlik Automate makes. |
| [qlik-automate-workflow.json](qlik-automate-workflow.json) | Importable Qlik Automate workflow definition with all blocks pre-wired: REST call, response parsing, conditional routing, Slack alert, Qlik app reload, and Snowflake audit write-back. |

## Prerequisites

- **Snowflake**: Account with Cortex Agents enabled. `SNOWFLAKE.CORTEX_USER` database role granted to the service user.
- **Qlik Cloud**: Tenant with Qlik Automate enabled (included in Qlik Cloud Analytics Premium and Enterprise).
- **Authentication**: A Snowflake Personal Access Token (PAT) or key-pair credentials for Qlik Automate to authenticate.

## Setup

### Step 1: Create the Snowflake Agent

1. Edit `setup.sql` and set your `TARGET_DATABASE` and `TARGET_SCHEMA`.
2. Run the script in a Snowflake worksheet:

```sql
!source setup.sql
```

3. Test the agent locally:

```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'CORTEX_CODE.PUBLIC.QLIK_AUTOMATE_FRESHNESS_AGENT',
  $${ "messages": [{ "role": "user", "content": [{ "type": "text",
      "text": "Check freshness for ANALYTICS.PUBLIC with a 4-hour SLA." }] }] }$$,
  TRUE
) AS response;
```

Verify the response is valid JSON with `status`, `summary`, `tables`, and `breaches` fields.

### Step 2: Create a Snowflake PAT

Qlik Automate authenticates to the Snowflake REST API using a Bearer token. Create a PAT for a service user:

1. In Snowsight, go to your user profile → **Personal Access Tokens**.
2. Create a new token with a descriptive name (e.g., `qlik-automate-freshness`).
3. Copy the token — you'll need it in Step 4.

> **Security note:** Use a dedicated service user with minimal privileges (read access to `INFORMATION_SCHEMA`, `ACCOUNT_USAGE`, and insert access to the audit table). Never use an admin PAT.

### Step 3: Create the Snowflake Connector in Qlik Automate

1. In Qlik Cloud, go to **Automate** → **Connections** → **Add connection**.
2. Select **Snowflake**.
3. Configure:

| Setting | Value |
|---------|-------|
| Account | `<your-account>.snowflakecomputing.com` |
| Username | `<service-user>` |
| Auth method | Key-pair (recommended) or username/password |
| Database | `CORTEX_CODE` |
| Schema | `PUBLIC` |
| Warehouse | `<your-warehouse>` |

For key-pair authentication, see: [Creating a Snowflake Key Pair connector for Qlik Automate](https://community.qlik.com/t5/Official-Support-Articles/Creating-a-Snowflake-Key-Pair-based-connector-for-Application/ta-p/2512104).

### Step 4: Import the Qlik Automate Workflow

1. In Qlik Cloud, go to **Automate** → **Create automation** → **Import**.
2. Upload `qlik-automate-workflow.json`.
3. Edit the **Set Configuration Variables** block and replace all `<placeholder>` values:

| Variable | Description |
|----------|-------------|
| `snowflake_account_url` | Your Snowflake account URL (e.g., `xy12345.us-east-1.snowflakecomputing.com`) |
| `snowflake_pat` | The PAT from Step 2 |
| `agent_database` | Database containing the agent (default: `CORTEX_CODE`) |
| `agent_schema` | Schema containing the agent (default: `PUBLIC`) |
| `agent_name` | Agent name (default: `QLIK_AUTOMATE_FRESHNESS_AGENT`) |
| `target_schema` | Schema to monitor (e.g., `ANALYTICS.PUBLIC`) |
| `sla_hours` | SLA threshold in hours (default: `4`) |
| `slack_webhook_url` | Slack incoming webhook URL for alerts |
| `qlik_app_id_to_reload` | Qlik app ID to reload on breach (find in Qlik Hub URL) |

4. Wire the Snowflake connector (from Step 3) to the two Snowflake blocks.
5. Wire the Slack block to your Slack workspace (or replace with Teams/email).
6. **Enable** the automation.

### Step 5: Test End-to-End

1. In the automation editor, click **Run** (manual trigger).
2. Check the run history for success.
3. Verify the audit record in Snowflake:

```sql
SELECT * FROM FRESHNESS_AUDIT_LOG ORDER BY run_timestamp DESC LIMIT 5;
```

## Customization

### Change the notification channel

Replace the **Send Slack Alert** block with:
- **Microsoft Teams**: Use a Teams incoming webhook URL in a Call URL block.
- **Email**: Use the Qlik Automate **Mail** connector block.
- **PagerDuty**: Use the PagerDuty connector to create an incident.

### Change the trigger

The workflow defaults to a 4-hour cron schedule. Alternatives:
- **Qlik event trigger**: Fire after a specific Qlik app reload completes (set trigger type to `qlikEvent`, event: `app.reload.finished`).
- **Webhook trigger**: Expose a URL that Snowflake alerts or external systems can call.
- **Manual**: Run on-demand from the Automate UI.

### Monitor multiple schemas

Duplicate the workflow and change `target_schema` and `sla_hours` per copy, or add a **Loop** block that iterates over a list of schemas.

### Add Cortex Agent thread persistence

For multi-turn diagnostics, pass `thread_id` in the REST API call to maintain conversation context across sequential Qlik Automate runs:

```json
{
  "thread_id": "<persistent-thread-id>",
  "messages": [...]
}
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| REST call returns 401 | PAT expired or invalid | Generate a new PAT in Snowsight and update the workflow variable |
| REST call returns 403 | Service user lacks privileges | Grant `SNOWFLAKE.CORTEX_USER` database role and `USAGE` on the agent |
| Agent returns empty or malformed JSON | Agent timed out or schema has no tables | Check agent logs; verify the target schema exists and contains tables |
| Slack alert not delivered | Webhook URL invalid or Slack app deactivated | Test the webhook URL with a manual curl; check Slack app settings |
| Snowflake write-back fails | Missing INSERT privilege on audit table | Grant `INSERT` on `FRESHNESS_AUDIT_LOG` to the service user role |
| Qlik Automate "connection failed" on Snowflake block | Key-pair auth misconfigured | Verify the .p8 key, username, and account; re-test the connection |

## Agent Response Schema

The agent always returns this JSON structure (designed for machine parsing):

```json
{
  "status": "ok | breach",
  "schema_checked": "DATABASE.SCHEMA",
  "sla_hours": 4,
  "checked_at": "2026-09-21T15:00:00Z",
  "summary": {
    "total_tables": 12,
    "tables_ok": 10,
    "tables_breached": 2
  },
  "tables": [
    {
      "table_name": "ORDERS",
      "last_altered": "2026-09-21T14:30:00Z",
      "hours_stale": 0.5,
      "sla_status": "ok",
      "row_count": 1500000
    }
  ],
  "breaches": [
    {
      "table_name": "CUSTOMERS",
      "hours_stale": 6.2,
      "cause": "task_suspended",
      "task_name": "LOAD_CUSTOMERS",
      "error_message": null,
      "remediation_sql": "ALTER TASK LOAD_CUSTOMERS RESUME;"
    }
  ]
}
```

## Try Qlik Cloud

Don't have a Qlik Cloud tenant yet? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics) to get started with Qlik Automate.

## License

See [LICENSE](../../LICENSE) for details.
