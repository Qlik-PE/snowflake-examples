# Qlik Automate → Snowflake Cortex Agent Orchestration

A Qlik Automate workflow that asks a Snowflake Cortex Agent to check data-freshness SLAs. When an SLA is breached, the workflow sends an alert (Slack, Teams or email) and reloads a Qlik app as remediation. Every run leaves an audit record in Snowflake.

## Architecture

```
Qlik Automate (every 4 h, or on a webhook / Qlik event)
  │
  │  Snowflake connector:
  │  CALL RUN_FRESHNESS_CHECK('<agent>', 'ANALYTICS.PUBLIC', 4)
  ▼
Snowflake procedure RUN_FRESHNESS_CHECK
  ├── DATA_AGENT_RUN → Cortex Agent QLIK_AUTOMATE_FRESHNESS_AGENT
  │      ├── INFORMATION_SCHEMA.TABLES               → how stale each table is
  │      └── TASK_HISTORY, SHOW TASKS                → why a table is stale
  ├── extracts the agent's JSON answer from the response
  ├── INSERT INTO FRESHNESS_AUDIT_LOG
  └── returns one row: STATUS, TOTAL_TABLES, TABLES_OK, TABLES_BREACHED, BREACHES, AGENT_JSON
  │
  ▼
Qlik Automate: branch on STATUS
  ├── "ok"     → done
  ├── "breach" → Slack alert → reload Qlik app
  └── "error"  → Slack alert that the check itself failed
```

**Why a procedure in the middle?** The agent's JSON answer arrives as text inside the agent response envelope. Unpacking that reliably is simple in SQL and awkward in Automate. The procedure does the parsing and the audit write, so the workflow only reads flat columns.

## What's Included

| File | Description |
|---|---|
| [setup.sql](setup.sql) | Creates the `FRESHNESS_AUDIT_LOG` table, the Cortex Agent (instructed to answer with a single JSON object) and the `RUN_FRESHNESS_CHECK` procedure. Also includes test calls and a `curl` example for calling the agent directly over REST. |
| [qlik-automate-workflow.json](qlik-automate-workflow.json) | Reference workflow definition: config variables → `CALL RUN_FRESHNESS_CHECK` → branch → Slack alert + Qlik reload, or a "check failed" alert. |

## Prerequisites

- **Snowflake:** Cortex Agents enabled, and a service user whose role has:
  - the `SNOWFLAKE.CORTEX_USER` database role,
  - `USAGE` on the agent and on `RUN_FRESHNESS_CHECK` (plus their database and schema),
  - `INSERT` and `SELECT` on `FRESHNESS_AUDIT_LOG`,
  - read access to the monitored schemas' `INFORMATION_SCHEMA` and to `SNOWFLAKE.ACCOUNT_USAGE`,
  - a default warehouse.

  The procedure runs with the caller's rights, so the agent's queries run as this role.
- **Qlik Cloud:** a tenant with Qlik Automate. It is included in Qlik Cloud Analytics Premium and Enterprise.

## Setup

### Step 1: Create the Snowflake objects

1. Edit the configuration block in `setup.sql` (`TARGET_DATABASE`, `TARGET_SCHEMA`, `AGENT_NAME`).
   > The test calls in `setup.sql` and the defaults in the workflow use `CORTEX_CODE.PUBLIC`. If you choose a different location, update those as well.
2. Run the script:
   ```bash
   snow sql -f automate/qlik-automate-agent-orchestration/setup.sql
   ```
3. Grant the service role what it needs. The `GRANT` statements are at the end of Step 3 in `setup.sql`.
4. Test from a worksheet, running as the service role:
   ```sql
   CALL CORTEX_CODE.PUBLIC.RUN_FRESHNESS_CHECK(
     'CORTEX_CODE.PUBLIC.QLIK_AUTOMATE_FRESHNESS_AGENT', 'ANALYTICS.PUBLIC', 4);
   ```
   You should get one row with `STATUS` = `ok` or `breach`, and a new row in `FRESHNESS_AUDIT_LOG`.

### Step 2: Create the Snowflake connection in Qlik Automate

1. In Qlik Cloud, open **Automate** → **Connections** → **Add connection** → **Snowflake**.
2. Configure it:

   | Setting | Value |
   |---|---|
   | Account | `<your-account>.snowflakecomputing.com` |
   | Username | `<service-user>` |
   | Auth method | Key-pair (recommended) or username/password |
   | Database / Schema | Where the procedure lives (default `CORTEX_CODE` / `PUBLIC`) |
   | Warehouse | `<your-warehouse>` |

For key-pair setup, see [Creating a Snowflake Key Pair connector for Qlik Automate](https://community.qlik.com/t5/Official-Support-Articles/Creating-a-Snowflake-Key-Pair-based-connector-for-Application/ta-p/2512104).

### Step 3: Build the workflow

`qlik-automate-workflow.json` describes every block and its settings. Import it, or recreate the blocks in the Automate editor if your tenant's import format differs.

1. Open the **Set Configuration Variables** block and replace every `<placeholder>`:

   | Variable | Description |
   |---|---|
   | `agent_database` / `agent_schema` / `agent_name` | Location of the agent and procedure (defaults `CORTEX_CODE` / `PUBLIC` / `QLIK_AUTOMATE_FRESHNESS_AGENT`) |
   | `target_schema` | Schema to monitor, e.g. `ANALYTICS.PUBLIC` |
   | `sla_hours` | SLA threshold in hours (default `4`) |
   | `slack_webhook_url` | Slack incoming-webhook URL |
   | `qlik_app_id_to_reload` | ID of the Qlik app to reload on breach (it's in the app's URL) |

2. Attach the Snowflake connection from Step 2 to the **Run Freshness Check** block. Give it a generous query timeout, because an agent run can take a minute or more.
3. In both condition blocks, check that `STATUS` is read from the first row of the Snowflake block's output. The exact reference syntax depends on your tenant.
4. Configure the Slack blocks, or replace them (see [Customization](#customization)).
5. **Enable** the automation.

### Step 4: Test end to end

1. In the automation editor, click **Run**.
2. Check the run history for errors.
3. Confirm that an audit row was written:
   ```sql
   SELECT * FROM CORTEX_CODE.PUBLIC.FRESHNESS_AUDIT_LOG ORDER BY run_timestamp DESC LIMIT 5;
   ```

## Customization

### Notification channel

Replace the Slack blocks with one of:
- **Microsoft Teams:** a Call URL block that posts to a Teams incoming webhook.
- **Email:** the Qlik Automate **Mail** block.
- **PagerDuty:** the PagerDuty connector, to open an incident.

### Trigger

The workflow runs on a 4-hour cron schedule by default. Other options:
- **Qlik event:** run after a specific app reload finishes (`app.reload.finished`).
- **Webhook:** expose a URL that Snowflake alerts or other systems can call.
- **Manual:** run on demand from the Automate UI.

### Monitor several schemas

Duplicate the workflow with different `target_schema` / `sla_hours` values, or add a **Loop** block over a list of schemas that calls the procedure once per schema.

### Call the agent directly over REST

If another system needs the agent without the procedure, call `POST /api/v2/databases/{db}/schemas/{schema}/agents/QLIK_AUTOMATE_FRESHNESS_AGENT:run`. Authenticate with a Snowflake **Programmatic Access Token** (`Authorization: Bearer <PAT>`), and send `"stream": false` to get one JSON document back. The agent's JSON is the text of the final message in that response. Step 6 of `setup.sql` has a `curl` example.

> **Security:** issue the PAT to a dedicated service user with only the privileges above, and store it in a secret or credential field, not in plain workflow variables.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `CALL` fails with "insufficient privileges" | Service role is missing a grant | Grant `SNOWFLAKE.CORTEX_USER`, `USAGE` on the agent and procedure, and `INSERT` on the audit table |
| `STATUS` is `error` | The agent timed out, or its answer contained no valid JSON with a `status` field | Look at `agent_response` in the latest audit row; test the agent with `DATA_AGENT_RUN` |
| Every table is reported as fresh | The service role can't see the tables | Check that the role has access to the target schema's `INFORMATION_SCHEMA` |
| Snowflake block times out | Agent runs are slow on first use | Increase the block's query timeout |
| Slack alert not delivered | Webhook URL invalid, or the Slack app is disabled | Test the webhook with `curl`; check the Slack app settings |
| "Connection failed" on the Snowflake block | Key-pair auth misconfigured | Re-check the `.p8` key, username and account identifier, then re-test the connection |

## Agent Response Schema

The agent is instructed to answer with exactly one JSON object in this shape. `RUN_FRESHNESS_CHECK` returns it as `AGENT_JSON` and stores it in `FRESHNESS_AUDIT_LOG.agent_response`.

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

`cause` is one of `task_failed`, `task_suspended`, `no_task` or `unknown`.

## Try Qlik Cloud

Don't have a Qlik Cloud tenant yet? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics) to get started with Qlik Automate.

## License

See [LICENSE](../../LICENSE).
