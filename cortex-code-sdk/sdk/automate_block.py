"""
Qlik Automate block simulator: "Run Cortex Code agent"
=======================================================
Simulates a custom Qlik Automate block that calls the Cortex Code Agent SDK.
It behaves like a block on the canvas: it takes the block inputs, runs one
agent session and always returns the same three outputs, so a single
Condition block can branch on ``status``.

Inputs
    connection     Snowflake connection name (the block's dropdown). Options are
                   read from ~/.snowflake/connections.toml and show account,
                   role and warehouse.
    system_prompt  Who the agent is and the ground rules. Set once.
    instructions   The task for this run, with {{name}} placeholders.
    parameters     Array of {"name": ..., "value": ...} pairs, mapped from
                   earlier blocks.

Outputs
    status         "success" | "error"
    response       The agent's answer as text ("" on error)
    error          The message when status is "error" ("" on success)

The block never raises: every failure (bad input, missing placeholder,
unknown connection, CLI/SDK error, agent error) becomes status="error".

Usage:
    # List the connection dropdown
    python automate_block.py --list-connections

    # Run from a JSON payload (file or "-" for stdin), in the shape Automate sends
    python automate_block.py --input payload.json
    echo '{...}' | python automate_block.py --input -

    # Run the built-in freshness example on a connection
    python automate_block.py --example --connection my_conn

Example payload:
    {
      "connection": "my_conn",
      "system_prompt": "You are a Snowflake operations specialist. Only read data; never change objects.",
      "instructions": "Check whether tables in {{database}}.{{schema}} were updated within {{sla_hours}} hours. Explain any that were not.",
      "parameters": [
        {"name": "database",  "value": "ANALYTICS"},
        {"name": "schema",    "value": "PUBLIC"},
        {"name": "sla_hours", "value": "4"}
      ]
    }

The outputs are printed to stdout as JSON. The agent's progress goes to stderr.
Exit code is 0 for success and 1 for error.
"""

import argparse
import asyncio
import json
import os
import re
import sys
import tomllib
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, Field, ValidationError
from cortex_code_agent_sdk import (
    query,
    AssistantMessage,
    ResultMessage,
    CortexCodeAgentOptions,
    CortexCodeSDKError,
    CLINotFoundError,
)

PLACEHOLDER = re.compile(r"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}")
DEFAULT_TIMEOUT_S = 600

# ---------------------------------------------------------------------------
# Block contract
# ---------------------------------------------------------------------------

class Parameter(BaseModel):
    name: str = Field(min_length=1)
    value: Any = ""


class BlockInput(BaseModel):
    connection: str = Field(min_length=1)
    system_prompt: str = Field(min_length=1)
    instructions: str = Field(min_length=1)
    parameters: list[Parameter] = []


class BlockOutput(BaseModel):
    status: Literal["success", "error"]
    response: str = ""
    error: str = ""

    @classmethod
    def ok(cls, response: str) -> "BlockOutput":
        return cls(status="success", response=response)

    @classmethod
    def fail(cls, error: str) -> "BlockOutput":
        return cls(status="error", error=error)


# ---------------------------------------------------------------------------
# Connection dropdown
# ---------------------------------------------------------------------------

def _connections_file() -> Path:
    home = os.environ.get("SNOWFLAKE_HOME")
    return Path(home or Path.home() / ".snowflake") / "connections.toml"


def list_connections() -> list[dict[str, str]]:
    """The dropdown options: one entry per connection in connections.toml."""
    path = _connections_file()
    if not path.exists():
        return []
    with path.open("rb") as f:
        data = tomllib.load(f)
    return [
        {
            "name": name,
            "account": str(cfg.get("account", "")),
            "role": str(cfg.get("role", "")),
            "warehouse": str(cfg.get("warehouse", "")),
        }
        for name, cfg in data.items()
        if isinstance(cfg, dict)
    ]


# ---------------------------------------------------------------------------
# Placeholders
# ---------------------------------------------------------------------------

def render_instructions(template: str, parameters: list[Parameter]) -> str:
    """Replace {{name}} with parameter values; any unmapped name is an error."""
    values: dict[str, str] = {}
    for p in parameters:
        if p.name in values:
            raise ValueError(f"duplicate parameter '{p.name}'")
        values[p.name] = "" if p.value is None else str(p.value)

    missing = sorted({m for m in PLACEHOLDER.findall(template) if m not in values})
    if missing:
        raise ValueError("no parameter for placeholder(s): "
                         + ", ".join("{{" + m + "}}" for m in missing))
    return PLACEHOLDER.sub(lambda m: values[m.group(1)], template)


# ---------------------------------------------------------------------------
# Block execution
# ---------------------------------------------------------------------------

async def _run_agent(prompt: str, system_prompt: str, connection: str) -> str:
    options = CortexCodeAgentOptions(
        cwd=".",
        connection=connection,
        system_prompt=system_prompt,
        allowed_tools=["SQL"],
    )
    result: ResultMessage | None = None
    text: list[str] = []
    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    text.append(block.text)
                    print(block.text, end="", flush=True, file=sys.stderr)
        elif isinstance(message, ResultMessage):
            result = message

    if result is None:
        raise RuntimeError("agent stream ended without a result message")
    if result.is_error:
        raise RuntimeError("agent error: " + ("; ".join(result.errors or []) or result.subtype))
    answer = (result.result or "".join(text)).strip()
    if not answer:
        raise RuntimeError("agent returned an empty response")
    return answer


async def run_block(payload: dict[str, Any], timeout_s: float = DEFAULT_TIMEOUT_S) -> BlockOutput:
    """Execute the block. Never raises; failures come back as status='error'."""
    try:
        inp = BlockInput.model_validate(payload)
    except ValidationError as exc:
        return BlockOutput.fail("invalid block input: " + "; ".join(
            f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()))

    names = {c["name"] for c in list_connections()}
    if names and inp.connection not in names:
        return BlockOutput.fail(f"unknown connection '{inp.connection}' "
                                f"(available: {', '.join(sorted(names))})")

    try:
        prompt = render_instructions(inp.instructions, inp.parameters)
    except ValueError as exc:
        return BlockOutput.fail(str(exc))

    try:
        answer = await asyncio.wait_for(
            _run_agent(prompt, inp.system_prompt, inp.connection), timeout_s)
    except asyncio.TimeoutError:
        return BlockOutput.fail(f"agent timed out after {timeout_s:.0f}s")
    except CLINotFoundError:
        return BlockOutput.fail("Cortex Code CLI not found. Install it or set CORTEX_CODE_CLI_PATH.")
    except CortexCodeSDKError as exc:
        return BlockOutput.fail(f"Cortex Code SDK failure: {exc}")
    except Exception as exc:  # the block contract: report, never raise
        return BlockOutput.fail(str(exc) or exc.__class__.__name__)
    return BlockOutput.ok(answer)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

EXAMPLE = {
    "system_prompt": "You are a Snowflake operations specialist. Only read data; never change objects.",
    "instructions": ("Check whether tables in {{database}}.{{schema}} were updated within "
                     "{{sla_hours}} hours. Explain any that were not."),
    "parameters": [
        {"name": "database", "value": "ANALYTICS"},
        {"name": "schema", "value": "PUBLIC"},
        {"name": "sla_hours", "value": "4"},
    ],
}


def _load_payload(source: str) -> dict[str, Any]:
    raw = sys.stdin.read() if source == "-" else Path(source).read_text()
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("payload must be a JSON object")
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description="Simulated Qlik Automate block for Cortex Code")
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--input", help="JSON payload file, or '-' for stdin")
    src.add_argument("--example", action="store_true", help="Run the built-in freshness example")
    src.add_argument("--list-connections", action="store_true", help="Print the connection dropdown")
    parser.add_argument("--connection", help="Override/set the connection name")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_S,
                        help=f"Agent timeout in seconds (default: {DEFAULT_TIMEOUT_S})")
    args = parser.parse_args()

    if args.list_connections:
        print(json.dumps(list_connections(), indent=2))
        return

    if args.example:
        payload = dict(EXAMPLE)
    else:
        try:
            payload = _load_payload(args.input)
        except (OSError, ValueError) as exc:
            out = BlockOutput.fail(f"cannot read payload: {exc}")
            print(out.model_dump_json(indent=2))
            sys.exit(1)
    if args.connection:
        payload["connection"] = args.connection

    try:
        out = asyncio.run(run_block(payload, args.timeout))
    except KeyboardInterrupt:
        out = BlockOutput.fail("interrupted")
    print(file=sys.stderr)
    print(out.model_dump_json(indent=2))
    sys.exit(0 if out.status == "success" else 1)


if __name__ == "__main__":
    main()
