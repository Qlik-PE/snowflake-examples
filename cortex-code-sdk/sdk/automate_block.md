# Qlik Automate Block Simulator: "Run Cortex Code agent"

[`automate_block.py`](automate_block.py) simulates a custom Qlik Automate block that calls the [Cortex Code Agent SDK](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk). It acts like a block on the canvas: it takes the block inputs, runs one agent session, and always returns the same three outputs. One Condition block can then branch on `status`.

## Inputs

| Input | Description | Example |
|---|---|---|
| **Connection** | Snowflake connection picked from a dropdown. The options come from `~/.snowflake/connections.toml` (or `$SNOWFLAKE_HOME/connections.toml`) and show account, role and warehouse. | `SERVICE_CANJOS` |
| **System Prompt** | Who the agent is and the ground rules. Set once, rarely changed. | `You are a Snowflake operations specialist. Only read data; never change objects.` |
| **Instructions** | The task for this run, with `{{name}}` placeholders. | `Check whether tables in {{database}}.{{schema}} were updated within {{sla_hours}} hours. Explain any that were not.` |
| **Parameters** | Array of `{name, value}` pairs whose values are mapped from earlier blocks. Values are converted to text. | `database = ANALYTICS`, `schema = PUBLIC`, `sla_hours = 4` |

## Outputs

| Output | Description |
|---|---|
| **Status** | `success` or `error` |
| **Response** | The agent's answer as text (empty on error) |
| **Error** | The message when Status is `error` (empty on success) |

The block never raises an exception. Every failure is returned as `status: "error"` with a message:

| Failure | Example error |
|---|---|
| Missing or empty input field | `invalid block input: connection: Field required` |
| Connection not in the dropdown | `unknown connection 'nope' (available: SERVICE_CANJOS)` |
| Placeholder without a parameter | `no parameter for placeholder(s): {{schema}}` |
| Same parameter name twice | `duplicate parameter 'schema'` |
| Agent ran too long | `agent timed out after 600s` |
| Cortex Code CLI missing | `Cortex Code CLI not found. Install it or set CORTEX_CODE_CLI_PATH.` |
| SDK or agent failure | `Cortex Code SDK failure: …` / `agent error: …` |
| Agent returned no text | `agent returned an empty response` |

## How it works

1. The input payload is validated against a Pydantic model (`BlockInput`).
2. The connection is checked against the dropdown list. If `connections.toml` is missing, this check is skipped.
3. Each `{{name}}` in the Instructions is replaced with its parameter value. Whitespace inside the braces is allowed (`{{ name }}`). A placeholder with no matching parameter is an error, not left in the text.
4. The SDK runs one `query()` session with:
   - `connection` = the chosen connection
   - `system_prompt` = the System Prompt
   - `allowed_tools = ["SQL"]`, the same as the other agents in this folder
5. The final `ResultMessage.result` becomes **Response**. If it is empty, the streamed assistant text is used instead.

> The rule "only read data" is enforced by the system prompt, not by the block. For a hard guarantee, run the block on a connection whose role has read-only grants.

## Setup

```bash
cd cortex-code-sdk/sdk
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt     # cortex-code-agent-sdk>=1.0.7, pydantic>=2.0
```

You also need the Cortex Code CLI on your `PATH` (or set `CORTEX_CODE_CLI_PATH`) and a configured Snowflake connection.

## Usage

```bash
# Show the connection dropdown
python automate_block.py --list-connections

# Run from a JSON payload file, or from stdin with "-"
python automate_block.py --input payload.json
cat payload.json | python automate_block.py --input -

# Run the built-in freshness example on a connection
python automate_block.py --example --connection SERVICE_CANJOS

# Override the connection in a payload, or change the timeout (seconds)
python automate_block.py --input payload.json --connection OTHER_CONN --timeout 300
```

| Option | Description |
|---|---|
| `--input FILE\|-` | JSON payload file, or `-` for stdin |
| `--example` | Run the built-in data-freshness example |
| `--list-connections` | Print the dropdown options as JSON |
| `--connection NAME` | Set or override the connection |
| `--timeout SECONDS` | Agent timeout (default `600`) |

The outputs go to **stdout** as JSON. The agent's progress text streams to **stderr**. Exit code: `0` = success, `1` = error.

### Example payload

```json
{
  "connection": "SERVICE_CANJOS",
  "system_prompt": "You are a Snowflake operations specialist. Only read data; never change objects.",
  "instructions": "Check whether tables in {{database}}.{{schema}} were updated within {{sla_hours}} hours. Explain any that were not.",
  "parameters": [
    {"name": "database",  "value": "ANALYTICS"},
    {"name": "schema",    "value": "PUBLIC"},
    {"name": "sla_hours", "value": "4"}
  ]
}
```

### Example outputs

Success:

```json
{
  "status": "success",
  "response": "Role: QLIK_DATA_INTEGRATION_ROLE, warehouse: COMPUTE (connection SERVICE_CANJOS).\n\nDONE",
  "error": ""
}
```

Error:

```json
{
  "status": "error",
  "response": "",
  "error": "no parameter for placeholder(s): {{schema}}"
}
```

Connection dropdown:

```json
[
  {
    "name": "SERVICE_CANJOS",
    "account": "AYFRZOA-QLIK",
    "role": "QLIK_DATA_INTEGRATION_ROLE",
    "warehouse": "COMPUTE"
  }
]
```

## Calling it from Python

```python
import asyncio
from automate_block import run_block, list_connections

options = list_connections()              # dropdown values
out = asyncio.run(run_block({
    "connection": options[0]["name"],
    "system_prompt": "You are a Snowflake operations specialist. Only read data; never change objects.",
    "instructions": "Summarize row counts in {{database}}.{{schema}}.",
    "parameters": [{"name": "database", "value": "ANALYTICS"},
                   {"name": "schema", "value": "PUBLIC"}],
}, timeout_s=300))

if out.status == "success":   # what the Condition block would check
    print(out.response)
else:
    print("Failed:", out.error)
```

`run_block()` returns a `BlockOutput` model with `status`, `response` and `error`. Use `out.model_dump()` to get a dict.

## Mapping to a real Qlik Automate flow

```
[Earlier blocks] ──► [Run Cortex Code agent] ──► [Condition: Status = success]
                       connection                     ├─ yes ─► use Response (Slack, email, note…)
                       system prompt                  └─ no  ─► use Error (alert, retry…)
                       instructions
                       parameters ◄── mapped values
```

In Qlik Automate you would host this logic behind an endpoint (for example a small web service that wraps `run_block()`) and call it with a **Call URL** block or a custom connector. The JSON payload and outputs above are the contract that endpoint would expose.
