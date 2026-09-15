"""
SQL Optimizer Agent
====================
Accepts a raw SQL query, analyzes it against Snowflake best practices, and
returns a properly formatted and optimized version. The agent inspects the
query plan (EXPLAIN), checks for common anti-patterns, and produces a
structured report with the rewritten SQL, optimizations applied, and
estimated impact.

Uses a multi-turn pattern: turn 1 analyzes the original query and its
execution profile; turn 2 rewrites and validates the optimized version.

Usage:
    python sql_optimizer_agent.py --query "SELECT * FROM orders WHERE ..."
    python sql_optimizer_agent.py --file ./slow_query.sql
    python sql_optimizer_agent.py --file ./slow_query.sql --warehouse ANALYTICS_WH
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path

from pydantic import BaseModel
from cortex_code_agent_sdk import (
    CortexCodeSDKClient,
    CortexCodeAgentOptions,
    AssistantMessage,
    ResultMessage,
)

# ---------------------------------------------------------------------------
# Structured output schema
# ---------------------------------------------------------------------------

class Optimization(BaseModel):
    category: str  # "formatting", "predicate", "join", "aggregation", "pruning", "anti_pattern", "type_cast", "sort", "subquery"
    description: str
    before: str
    after: str
    impact: str  # "high", "medium", "low", "cosmetic"

class Warning(BaseModel):
    severity: str  # "critical", "warning", "info"
    message: str
    line_reference: str

class OptimizationReport(BaseModel):
    summary: str
    original_query: str
    optimized_query: str
    formatting_only: bool
    optimization_count: int
    optimizations: list[Optimization]
    warnings: list[Warning]
    estimated_improvement: str

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a Snowflake SQL performance specialist. Your job is to analyze SQL
queries, reformat them for readability, and optimize them following Snowflake
best practices.

Snowflake-specific optimization rules:
- Replace SELECT * with explicit column lists.
- Push filters as early as possible for partition pruning.
- Prefer QUALIFY over subqueries for window function filtering.
- Use COPY GRANTS when rewriting views.
- Replace correlated subqueries with JOINs or window functions where possible.
- Use appropriate clustering key alignment in predicates.
- Avoid ORDER BY in subqueries unless paired with LIMIT.
- Avoid implicit type casts in join/filter predicates (e.g., comparing VARCHAR
  to NUMBER) — they disable pruning and prevent micro-partition elimination.
- Prefer UNION ALL over UNION when duplicates are impossible or acceptable.
- Use DATE_TRUNC or TIME_SLICE instead of EXTRACT-based grouping.
- Avoid FLATTEN on large arrays without LATERAL constraints.
- Use :: cast syntax for readability (e.g., col::DATE instead of CAST(col AS DATE)).
- Prefer IS NOT DISTINCT FROM over NVL-based NULL comparisons in joins.

Formatting rules:
- Uppercase SQL keywords (SELECT, FROM, WHERE, JOIN, etc.).
- One clause per line, aligned.
- Indent subqueries and CTEs consistently (2 spaces).
- Use trailing commas in SELECT lists.
- Alias all tables and subqueries with meaningful short names.
- Place each JOIN on its own line with the ON clause indented beneath.

Always explain WHY each optimization matters for Snowflake specifically.
"""

def build_analyze_prompt(query_sql: str, warehouse: str) -> str:
    wh_block = ""
    if warehouse:
        wh_block = f"""
Also run EXPLAIN on the query using warehouse {warehouse} to get the query
plan. Note partition pruning effectiveness and any full table scans.
"""
    return f"""\
Analyze the following SQL query for formatting issues, anti-patterns, and
optimization opportunities against Snowflake best practices.

```sql
{query_sql}
```
{wh_block}
Steps:
1. Identify formatting issues (inconsistent casing, alignment, aliases).
2. Check for anti-patterns: SELECT *, implicit casts, correlated subqueries,
   unnecessary ORDER BY, UNION instead of UNION ALL, etc.
3. Check predicate pushdown opportunities and clustering key alignment.
4. Note any joins that could cause fan-out or Cartesian products.
5. If EXPLAIN is available, analyze partition pruning and scan efficiency.

Report your findings. Do NOT produce the final optimized query yet — I will
ask for that in the next turn.
"""

REWRITE_PROMPT = """\
Now produce the optimized and properly formatted version of the query.

Requirements:
1. Apply all formatting rules (uppercase keywords, aligned clauses, trailing
   commas, meaningful aliases).
2. Apply all optimizations you identified in the previous turn.
3. Ensure the optimized query is semantically equivalent to the original —
   same result set, same column order, same column names.
4. For each optimization, explain the category, what changed, and the
   expected impact on Snowflake specifically.

Produce the final structured JSON output.
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(query_sql: str, warehouse: str) -> None:
    output_schema = OptimizationReport.model_json_schema()

    print("Launching CoCo SQL optimizer agent (multi-turn)...")
    print(f"  query length={len(query_sql)} chars  warehouse={warehouse or '(none)'}\n")

    async with CortexCodeSDKClient(
        CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=SYSTEM_PROMPT,
        )
    ) as client:
        # --- Turn 1: Analyze the query ---
        print("=== Turn 1: Analyzing query for issues and opportunities ===\n")
        await client.query(build_analyze_prompt(query_sql, warehouse))
        async for msg in client.receive_response():
            if isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if hasattr(block, "text"):
                        print(block.text, end="")
            elif isinstance(msg, ResultMessage):
                print(f"\n  (turn 1 done, {msg.num_turns} agent turns)\n")

        # --- Turn 2: Rewrite and produce structured output ---
        print("=== Turn 2: Rewriting and optimizing ===\n")

        client._options = CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=SYSTEM_PROMPT,
            output_format={"type": "json_schema", "schema": output_schema},
        )

        await client.query(REWRITE_PROMPT)
        async for msg in client.receive_response():
            if isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if hasattr(block, "text"):
                        print(block.text, end="")
            elif isinstance(msg, ResultMessage):
                print(f"\n\n--- Agent finished (turns={msg.num_turns}, "
                      f"duration={msg.duration_ms}ms) ---")
                if msg.is_error:
                    print(f"Agent error: {msg.subtype}")
                    return

                if msg.structured_output:
                    report = OptimizationReport.model_validate(msg.structured_output)
                    print("\n========== OPTIMIZATION REPORT ==========")
                    print(json.dumps(report.model_dump(), indent=2))

                    print(f"\n--- Optimized Query ---\n")
                    print(report.optimized_query)
                else:
                    print("\nNo structured output returned.")


def main():
    parser = argparse.ArgumentParser(description="Snowflake SQL optimizer agent")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--query", help="SQL query string to optimize")
    group.add_argument("--file", help="Path to a .sql file containing the query")
    parser.add_argument("--warehouse", default="",
                        help="Warehouse to use for EXPLAIN analysis (optional)")
    args = parser.parse_args()

    if args.file:
        path = Path(args.file)
        if not path.exists():
            print(f"Error: file not found: {args.file}", file=sys.stderr)
            sys.exit(1)
        query_sql = path.read_text(encoding="utf-8", errors="replace")
    else:
        query_sql = args.query

    if not query_sql.strip():
        print("Error: empty query", file=sys.stderr)
        sys.exit(1)

    asyncio.run(run(query_sql, args.warehouse))


if __name__ == "__main__":
    main()
