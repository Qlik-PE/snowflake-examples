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
  └── returns one row: STATUS, counts, BREACHES, AGENT_JSON,
                       ALERT_MESSAGE (NULL when ok), RELOAD_NEEDED ('yes' on breach)
  │
  ▼
Qlik Automate
  ├── ALERT_MESSAGE not empty → Slack - Send Message (a breach, or a failed check)
  └── RELOAD_NEEDED not empty → Qlik Cloud Services - Do Reload
```

**Why a procedure in the middle?** The agent's JSON answer arrives as text inside the agent response envelope. Unpacking that reliably is simple in SQL and awkward in Automate. The procedure does the parsing, the audit write and the alert text, so the workflow only tests whether two columns are empty.

## What's Included

| File | Description |
|---|---|
| [setup.sql](setup.sql) | Creates the `FRESHNESS_AUDIT_LOG` table, the Cortex Agent (instructed to answer with a single JSON object) and the `RUN_FRESHNESS_CHECK` procedure. Also includes test calls and a `curl` example for calling the agent directly over REST. |
| [qlik-automate-workflow.json](qlik-automate-workflow.json) | Importable Qlik Automate workspace: Start → configuration variables → Snowflake **Do Query** (`CALL RUN_FRESHNESS_CHECK`) → *Alert needed?* → Slack **Send Message**, and *Reload needed?* → Qlik **Do Reload**. |

## Prerequisites

- **Snowflake:** Cortex Agents enabled, and a service user whose role has:
  - the `SNOWFLAKE.CORTEX_USER` database role,
  - `USAGE` on the agent and on `RUN_FRESHNESS_CHECK` (plus their database and schema),
  - `INSERT` and `SELECT` on `FRESHNESS_AUDIT_LOG`,
  - read access to the monitored schemas' `INFORMATION_SCHEMA` and to `SNOWFLAKE.ACCOUNT_USAGE`,
  - a default warehouse.

  The procedure runs with the caller's rights, so the agent's queries run as this role.
- **Qlik Cloud:** a tenant with Qlik Automate. It is included in Qlik Cloud Analytics Premium and Enterprise.
- **Slack:** a Slack connection in Qlik Automate, with access to the alert channel.

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

### Step 3: Import and configure the workflow

1. In Qlik Cloud, open **Automate** → **Create automation**. Right-click the empty canvas → **Upload workspace**, and choose `qlik-automate-workflow.json`.
2. Set the values in the **Variable** blocks at the top:

   | Variable | Description |
   |---|---|
   | `vAgentSchema` | `DATABASE.SCHEMA` holding the agent, procedure and audit table (default `CORTEX_CODE.PUBLIC`) |
   | `vAgentName` | Agent name (default `QLIK_AUTOMATE_FRESHNESS_AGENT`) |
   | `vTargetSchema` | Schema to monitor, e.g. `ANALYTICS.PUBLIC` |
   | `vSlaHours` | SLA threshold in hours (default `4`) |
   | `vSlackChannel` | Slack channel for alerts, e.g. `#data-alerts` |
   | `vQlikAppId` | ID of the Qlik app to reload on breach (it's in the app's URL) |

3. Select connections in two blocks' settings:
   - **Snowflake - Do Query** (`runFreshnessCheck`): the Snowflake connection from Step 2. Give it a generous timeout, because an agent run can take a minute or more.
   - **Slack - Send Message** (`sendAlert`): your Slack connection. Check that *Channel* shows `{$.vSlackChannel}` and *Text* shows `{$.runFreshnessCheck.item.ALERT_MESSAGE}`.
4. In the **Start** block, set **Run mode** to **Scheduled**, e.g. every 4 hours.
5. **Enable** the automation.

**How it flows:** the Do Query block returns one row, and the two conditions run once for that row.
- **Alert needed?** tests whether `ALERT_MESSAGE` is empty. If it isn't (an SLA breach, or a failed check), the **NO** branch sends it to Slack.
- **Reload needed?** tests whether `RELOAD_NEEDED` is empty. On a breach it isn't, and the **NO** branch runs **Do Reload** on `{$.vQlikAppId}`.

The **YES** branches are intentionally empty.

### Step 4: Test end to end

1. In the automation editor, click **Run**.
2. Check the run history for errors.
3. Confirm that an audit row was written:
   ```sql
   SELECT * FROM CORTEX_CODE.PUBLIC.FRESHNESS_AUDIT_LOG ORDER BY run_timestamp DESC LIMIT 5;
   ```

## Customization

### Notification channel

Replace **Slack - Send Message** with one of (send `{$.runFreshnessCheck.item.ALERT_MESSAGE}` as the text):
- **Microsoft Teams:** a Call URL block that posts to a Teams incoming webhook.
- **Email:** the Qlik Automate **Mail** block.
- **PagerDuty:** the PagerDuty connector, to open an incident.

### Trigger

The workflow runs on a 4-hour cron schedule by default. Other options:
- **Qlik event:** run after a specific app reload finishes (`app.reload.finished`).
- **Webhook:** expose a URL that Snowflake alerts or other systems can call.
- **Manual:** run on demand from the Automate UI.

### Monitor several schemas

Duplicate the workflow with different `vTargetSchema` / `vSlaHours` values, or add a **Loop** block over a list of schemas that runs the Do Query block once per schema.

### Call the agent directly over REST

If another system needs the agent without the procedure, call `POST /api/v2/databases/{db}/schemas/{schema}/agents/QLIK_AUTOMATE_FRESHNESS_AGENT:run`. Authenticate with a Snowflake **Programmatic Access Token** (`Authorization: Bearer <PAT>`), and send `"stream": false` to get one JSON document back. The agent's JSON is the text of the final message in that response. Step 6 of `setup.sql` has a `curl` example.

> **Security:** issue the PAT to a dedicated service user with only the privileges above, and store it in a secret or credential field, not in plain workflow variables.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `CALL` fails with "insufficient privileges" | Service role is missing a grant | Grant `SNOWFLAKE.CORTEX_USER`, `USAGE` on the agent and procedure, and `INSERT` on the audit table |
| Slack says "Freshness check failed" (`STATUS` = `error`) | The agent timed out, or its answer contained no valid JSON with a `status` field | Look at `agent_response` in the latest audit row; test the agent with `DATA_AGENT_RUN` |
| Every table is reported as fresh | The service role can't see the tables | Check that the role has access to the target schema's `INFORMATION_SCHEMA` |
| Snowflake block times out | Agent runs are slow on first use | Increase the block's query timeout |
| Upload workspace fails | The file was edited into invalid JSON, or isn't a workspace export | Re-download it from the repository; the file must have top-level `blocks` and `variables` arrays |
| Slack alert not delivered | Slack connection not selected, or it can't post to the channel | Select the connection in **Slack - Send Message**, and invite the Slack app to `vSlackChannel` |
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
