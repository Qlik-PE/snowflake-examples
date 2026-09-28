"""
Pipeline Pre-Flight Validator
==============================
Before a Qlik Declarative Pipeline runs, this agent checks the Snowflake
side: target tables exist, the service account has required grants,
warehouses are running, and dynamic tables are healthy. Returns a
structured go/no-go report with remediation SQL.

Uses a PreToolUse hook to log every SQL statement for audit.

Usage:
    python preflight_validator_agent.py \
        --database STAGING \
        --schema RAW \
        --role QLIK_ROLE \
        --warehouse QLIK_WH
"""

import argparse
import json

from pydantic import BaseModel

from _common import (
    make_options, print_report, run_main, run_structured, sql_audit_hooks, EXIT_FINDINGS,
)

# ---------------------------------------------------------------------------
# Structured output schema
# ---------------------------------------------------------------------------

class ObjectCheck(BaseModel):
    object_name: str
    object_type: str  # "table", "view", "dynamic_table", "stage", "schema"
    exists: bool
    issue: str

class GrantCheck(BaseModel):
    privilege: str
    object_name: str
    granted: bool
    issue: str

class WarehouseCheck(BaseModel):
    warehouse_name: str
    state: str  # "STARTED", "SUSPENDED", "RESIZING"
    size: str
    issue: str

class DynamicTableCheck(BaseModel):
    table_name: str
    refresh_status: str  # "HEALTHY", "UPSTREAM_FAILED", "STALE"
    last_refresh: str
    issue: str

class RemediationAction(BaseModel):
    description: str
    sql: str

class PreFlightReport(BaseModel):
    summary: str
    go_no_go: str  # "GO", "NO_GO"
    checked_at_utc: str
    object_checks: list[ObjectCheck]
    grant_checks: list[GrantCheck]
    warehouse_checks: list[WarehouseCheck]
    dynamic_table_checks: list[DynamicTableCheck]
    remediations: list[RemediationAction]

# Audit log: every SQL statement is recorded before the agent runs it (see
# _common.sql_audit_hooks). Each call is printed to stderr as it happens and the
# full log is printed at the end.
SQL_AUDIT_LOG: list[dict] = []

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a Snowflake operations specialist embedded inside a Qlik integration.
Your job is to perform pre-flight validation before a Qlik Declarative Pipeline
runs. Check that all Snowflake prerequisites are met and report any blockers.

Be thorough: check object existence, grants, warehouse state, and dynamic table
health. For every issue found, provide remediation SQL.
"""

def build_prompt(database: str, schema: str, role: str, warehouse: str) -> str:
    return f"""\
Perform a pre-flight check for a Qlik pipeline targeting {database}.{schema}.

Context:
- Service role: {role}
- Warehouse: {warehouse}

Steps:
1. Verify the database and schema exist.
2. List tables, views, and dynamic tables in {database}.{schema}. Note any
   that are missing or in an error state.
3. Check that role {role} has USAGE on the database and schema, SELECT on
   tables, and USAGE on warehouse {warehouse}. Use SHOW GRANTS TO ROLE.
4. Check warehouse {warehouse} state (STARTED/SUSPENDED). If suspended,
   include RESUME SQL in remediations.
5. For any dynamic tables in the schema, check their refresh status via
   SHOW DYNAMIC TABLES and DYNAMIC_TABLE_REFRESH_HISTORY. Flag any with
   UPSTREAM_FAILED or stale refreshes.
6. Produce a GO / NO_GO verdict. NO_GO if any critical issue is found
   (missing objects, missing grants, warehouse suspended).
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(database: str, schema: str, role: str, warehouse: str) -> int | None:
    print("Launching CoCo pre-flight validator...")
    print(f"  target={database}.{schema}  role={role}  warehouse={warehouse}\n")

    try:
        report = await run_structured(
            build_prompt(database, schema, role, warehouse),
            PreFlightReport,
            make_options(SYSTEM_PROMPT, max_turns=20, hooks=sql_audit_hooks(SQL_AUDIT_LOG)),
        )
    finally:
        if SQL_AUDIT_LOG:
            print(f"\n========== SQL AUDIT LOG ({len(SQL_AUDIT_LOG)} queries) ==========")
            print(json.dumps(SQL_AUDIT_LOG, indent=2))

    print_report("PRE-FLIGHT REPORT", report)
    if report.go_no_go.upper() != "GO":
        return EXIT_FINDINGS


def main():
    parser = argparse.ArgumentParser(description="Snowflake pipeline pre-flight validator")
    parser.add_argument("--database", required=True,
                        help="Target Snowflake database")
    parser.add_argument("--schema", required=True,
                        help="Target Snowflake schema")
    parser.add_argument("--role", required=True,
                        help="Service role the pipeline runs as")
    parser.add_argument("--warehouse", required=True,
                        help="Warehouse the pipeline uses")
    args = parser.parse_args()

    run_main(lambda: run(args.database, args.schema, args.role, args.warehouse))


if __name__ == "__main__":
    main()
