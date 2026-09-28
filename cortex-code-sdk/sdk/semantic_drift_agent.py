"""
Semantic View Drift Checker
============================
Multi-turn agent that compares a Qlik Data Product definition against a
Snowflake semantic view. Detects drift (added/removed columns, type
mismatches, broken verified queries) and returns a structured diff with
reconciliation DDL.

Usage:
    python semantic_drift_agent.py --semantic-view "ANALYTICS.PUBLIC.SALES_SV"
    python semantic_drift_agent.py \
        --semantic-view "ANALYTICS.PUBLIC.SALES_SV" \
        --expected-fields "revenue:NUMBER,customer_id:VARCHAR,order_date:DATE"
"""

import argparse

from pydantic import BaseModel

from _common import make_options, print_report, run_main, run_multi_turn

# ---------------------------------------------------------------------------
# Structured output schema
# ---------------------------------------------------------------------------

class ColumnDrift(BaseModel):
    column_name: str
    drift_type: str  # "added", "removed", "type_changed", "nullability_changed"
    expected: str
    actual: str

class VerifiedQueryResult(BaseModel):
    query_name: str
    status: str  # "passed", "failed", "error"
    error_message: str
    row_count: int

class ReconciliationAction(BaseModel):
    description: str
    ddl: str

class DriftReport(BaseModel):
    summary: str
    semantic_view: str
    underlying_table: str
    drift_detected: bool
    column_drifts: list[ColumnDrift]
    verified_query_results: list[VerifiedQueryResult]
    reconciliation_actions: list[ReconciliationAction]

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a Snowflake semantic layer specialist embedded inside a Qlik integration.
Your job is to inspect Snowflake semantic views, compare them against expected
data product definitions, and detect drift. You can query INFORMATION_SCHEMA,
DESCRIBE semantic views, and run verified queries to validate correctness.

When drift is detected, produce ALTER/CREATE OR REPLACE DDL to reconcile.
"""

def build_discover_prompt(semantic_view: str, expected_fields: str) -> str:
    fields_block = ""
    if expected_fields:
        fields_block = f"""
Expected fields from the Qlik Data Product:
{expected_fields}

Compare these against what the semantic view actually defines.
"""
    return f"""\
Investigate the semantic view {semantic_view}.

Steps:
1. Run DESCRIBE SEMANTIC VIEW {semantic_view} to get its current definition.
2. Identify the underlying table(s) it references.
3. Run DESCRIBE TABLE on the underlying table(s) to get current column types.
4. Note any columns that exist in the table but not the semantic view, or vice versa.
{fields_block}
Report what you found. Do NOT produce the final structured output yet — I will
ask for that in the next turn after validation.
"""

VALIDATE_PROMPT = """\
Now validate the semantic view by running its verified queries (if any exist).
For each verified query, execute it and record whether it succeeded, failed,
or errored, along with the row count.

Then produce the final structured JSON output with:
- All column drifts found in the previous turn
- All verified query results from this turn
- Reconciliation DDL for any issues
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(semantic_view: str, expected_fields: str) -> None:
    print("Launching CoCo semantic drift checker (multi-turn)...")
    print(f"  semantic_view={semantic_view}\n")

    report = await run_multi_turn(
        turns=[("Discovering semantic view and detecting drift",
                build_discover_prompt(semantic_view, expected_fields))],
        final=("Validating verified queries", VALIDATE_PROMPT),
        model=DriftReport,
        options=make_options(SYSTEM_PROMPT),
    )
    print_report("DRIFT REPORT", report)


def main():
    parser = argparse.ArgumentParser(description="Snowflake semantic view drift checker")
    parser.add_argument("--semantic-view", required=True,
                        help="Fully qualified semantic view name (DB.SCHEMA.VIEW)")
    parser.add_argument("--expected-fields", default="",
                        help="Comma-separated field:type pairs from Qlik Data Product "
                             "(e.g. 'revenue:NUMBER,customer_id:VARCHAR')")
    args = parser.parse_args()

    run_main(lambda: run(args.semantic_view, args.expected_fields))


if __name__ == "__main__":
    main()
