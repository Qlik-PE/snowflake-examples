"""
Snowflake Failure Root-Cause Investigator
==========================================
Prototype demonstrating the Cortex Code Agent SDK for the
"Reload / CDC failure root-cause" use case.

Simulates a Qlik webhook trigger: when a reload or
Replicate task fails, a CoCo agent session investigates the
Snowflake side (QUERY_HISTORY, WAREHOUSE_EVENTS_HISTORY, etc.) and
returns a structured JSON report with root cause + remediation.

Because SNOWFLAKE.ACCOUNT_USAGE lags by up to ~45 minutes, the prompt tells
the agent to use the real-time INFORMATION_SCHEMA.QUERY_HISTORY table function
for recent failures.

Usage:
    source .venv/bin/activate
    python rca_agent.py

    # Or pass custom context:
    python rca_agent.py \
        --warehouse QLIK_WH \
        --minutes 60 \
        --error "timeout"
"""

import argparse
import asyncio
import json
import sys

from pydantic import BaseModel
from cortex_code_agent_sdk import (
    query,
    AssistantMessage,
    ResultMessage,
    CortexCodeAgentOptions,
)

# ---------------------------------------------------------------------------
# Structured output schema (Pydantic → JSON Schema)
# ---------------------------------------------------------------------------

class FailedQuery(BaseModel):
    query_id: str
    query_text: str
    error_message: str
    user_name: str
    warehouse_name: str
    execution_time_s: float

class Remediation(BaseModel):
    description: str
    sql: str

class RCAReport(BaseModel):
    summary: str
    root_cause: str
    severity: str  # "low", "medium", "high", "critical"
    failed_queries: list[FailedQuery]
    remediations: list[Remediation]

# ---------------------------------------------------------------------------
# Agent prompt template
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a Snowflake platform specialist embedded inside a Qlik integration.
Your job is to investigate failures on the Snowflake side when a Qlik reload
or CDC pipeline reports an error. You have access to the SQL tool and can
query SNOWFLAKE.ACCOUNT_USAGE and INFORMATION_SCHEMA views.

Always ground your analysis in actual query history data. If you find no
matching failures, say so clearly in the summary.
"""

def build_prompt(warehouse: str, minutes: int, error_hint: str) -> str:
    return f"""\
A Qlik data pipeline failure was detected. Investigate the Snowflake side.

Context from the Qlik alert:
- Warehouse: {warehouse}
- Time window: last {minutes} minutes
- Error hint: "{error_hint}"

Investigation steps:
1. Find failed queries (EXECUTION_STATUS / ERROR_CODE set) in the last
   {minutes} minutes, filtered to warehouse '{warehouse}' if it is not '*'.
   SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY lags by up to ~45 minutes, so for
   recent activity use the real-time table function
   TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
       END_TIME_RANGE_START => DATEADD('minute', -{minutes}, CURRENT_TIMESTAMP()),
       RESULT_LIMIT => 10000))
   (or QUERY_HISTORY_BY_WAREHOUSE for a single warehouse). Use ACCOUNT_USAGE
   only for the part of the window older than ~45 minutes, and de-duplicate
   on QUERY_ID if you query both.
2. Look for patterns: repeated errors, resource contention, credential
   issues, object-not-found, timeouts, etc.
3. If relevant, check WAREHOUSE_LOAD_HISTORY or WAREHOUSE_EVENTS_HISTORY
   for the same period.
4. Produce a root-cause analysis with concrete remediation SQL.
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(warehouse: str, minutes: int, error_hint: str) -> None:
    prompt = build_prompt(warehouse, minutes, error_hint)
    output_schema = RCAReport.model_json_schema()

    print(f"Launching CoCo agent session...")
    print(f"  warehouse={warehouse}  window={minutes}m  hint=\"{error_hint}\"\n")

    async for message in query(
        prompt=prompt,
        options=CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=SYSTEM_PROMPT,
            output_format={"type": "json_schema", "schema": output_schema},
            max_turns=15,
        ),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text, end="")

        elif isinstance(message, ResultMessage):
            print(f"\n\n--- Agent finished (turns={message.num_turns}, "
                  f"duration={message.duration_ms}ms) ---")
            if message.is_error:
                print(f"Agent error: {message.subtype}")
                return

            if message.structured_output:
                report = RCAReport.model_validate(message.structured_output)
                print("\n========== STRUCTURED RCA REPORT ==========")
                print(json.dumps(report.model_dump(), indent=2))
            else:
                print("\nNo structured output returned.")


def main():
    parser = argparse.ArgumentParser(description="Snowflake failure RCA agent")
    parser.add_argument("--warehouse", default="*",
                        help="Warehouse to investigate (default: all)")
    parser.add_argument("--minutes", type=int, default=30,
                        help="Lookback window in minutes (default: 30)")
    parser.add_argument("--error", default="unknown failure",
                        help="Error hint from the Qlik alert")
    args = parser.parse_args()

    asyncio.run(run(args.warehouse, args.minutes, args.error))


if __name__ == "__main__":
    main()
