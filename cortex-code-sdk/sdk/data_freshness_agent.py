"""
Data Freshness SLA Monitor
============================
Scheduled agent that checks whether Qlik-managed tables in Snowflake meet
their freshness SLAs. Queries INFORMATION_SCHEMA and table metadata to
compute staleness, then returns a structured report with SLA violations
and suggested remediation (resume tasks, trigger reloads).

Demonstrates the multi-turn SDK pattern: turn 1 discovers tables and their
last-modified timestamps; turn 2 cross-references with TASK_HISTORY to
diagnose why stale tables fell behind.

Usage:
    python data_freshness_agent.py --database ANALYTICS --schema PUBLIC --sla-hours 4
    python data_freshness_agent.py --database STAGING --schema RAW --sla-hours 1 --tag QLIK_MANAGED
"""

import argparse

from pydantic import BaseModel

from _common import make_options, print_report, run_main, run_multi_turn, EXIT_FINDINGS

# ---------------------------------------------------------------------------
# Structured output schema
# ---------------------------------------------------------------------------

class TableFreshness(BaseModel):
    table_name: str
    last_altered: str
    hours_stale: float
    sla_hours: float
    sla_met: bool
    row_count: int

class StaleRootCause(BaseModel):
    table_name: str
    cause: str  # "task_suspended", "task_failed", "no_task", "upstream_delay"
    last_task_run: str
    task_name: str
    error_message: str

class RemediationAction(BaseModel):
    description: str
    sql: str

class FreshnessReport(BaseModel):
    summary: str
    database: str
    schema_name: str
    sla_hours: float
    total_tables: int
    tables_meeting_sla: int
    tables_violating_sla: int
    table_details: list[TableFreshness]
    root_causes: list[StaleRootCause]
    remediations: list[RemediationAction]

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a Snowflake data operations specialist embedded inside a Qlik
integration. Your job is to monitor data freshness across Snowflake tables
that Qlik pipelines populate, detect SLA violations, and diagnose why
tables are stale.

You have access to INFORMATION_SCHEMA, SNOWFLAKE.ACCOUNT_USAGE, and can
query task history. Always ground analysis in actual metadata timestamps.
"""

def build_discover_prompt(database: str, schema: str, sla_hours: float, tag: str) -> str:
    tag_filter = ""
    if tag:
        tag_filter = f"""
Also try to filter tables by tag '{tag}' using TAG_REFERENCES if available.
If the tag doesn't exist, check all tables in the schema.
"""
    return f"""\
Check data freshness for tables in {database}.{schema}.

Steps:
1. List all tables in {database}.{schema} using INFORMATION_SCHEMA.TABLES.
   Get TABLE_NAME, ROW_COUNT, LAST_ALTERED (or LAST_DDL).
2. For each table, compute hours since last alteration.
3. Compare against the SLA threshold of {sla_hours} hours.
4. Flag any table where staleness exceeds the SLA.
{tag_filter}
Report what you find. Do NOT produce structured output yet — I will ask
for root-cause analysis in the next turn.
"""

def build_diagnose_prompt(database: str, schema: str) -> str:
    return f"""\
For each table that violates the SLA, diagnose why it is stale:

1. Find the most recent runs of tasks targeting {database}.{schema}. Use the
   real-time TABLE({database}.INFORMATION_SCHEMA.TASK_HISTORY(...)) table
   function for recent runs; SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY lags by up
   to ~45 minutes and is only for older history.
2. Check if any tasks are suspended (SHOW TASKS IN SCHEMA {database}.{schema}).
3. If a task failed, include the error message.
4. If no task exists for a stale table, note "no_task" as the cause.

Produce the final structured JSON output with all table freshness details,
root causes for SLA violations, and remediation SQL (e.g., RESUME TASK,
ALTER TASK SET SCHEDULE).
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(database: str, schema: str, sla_hours: float, tag: str) -> int | None:
    print("Launching CoCo data freshness SLA monitor (multi-turn)...")
    print(f"  target={database}.{schema}  SLA={sla_hours}h  tag={tag or '(all)'}\n")

    report = await run_multi_turn(
        turns=[("Discovering tables and measuring freshness",
                build_discover_prompt(database, schema, sla_hours, tag))],
        final=("Diagnosing SLA violations", build_diagnose_prompt(database, schema)),
        model=FreshnessReport,
        options=make_options(SYSTEM_PROMPT),
    )
    print_report("FRESHNESS REPORT", report)
    if report.tables_violating_sla > 0:
        print(f"\n*** {report.tables_violating_sla} table(s) violating SLA ***")
        return EXIT_FINDINGS


def main():
    parser = argparse.ArgumentParser(description="Snowflake data freshness SLA monitor")
    parser.add_argument("--database", required=True,
                        help="Target Snowflake database")
    parser.add_argument("--schema", required=True,
                        help="Target Snowflake schema")
    parser.add_argument("--sla-hours", type=float, default=4.0,
                        help="Maximum acceptable staleness in hours (default: 4)")
    parser.add_argument("--tag", default="",
                        help="Optional Snowflake tag to filter tables (e.g. QLIK_MANAGED)")
    args = parser.parse_args()

    run_main(lambda: run(args.database, args.schema, args.sla_hours, args.tag))


if __name__ == "__main__":
    main()
