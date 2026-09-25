"""
TPCH SF100 Cost-Optimize-Cost Workflow
========================================
End-to-end demonstration that chains the Workload Cost Attribution and SQL
Optimizer agents against SNOWFLAKE_SAMPLE_DATA.TPCH_SF100 (600 million rows).

Warning: this runs heavy queries on TPCH_SF100 and consumes warehouse credits.
The cost agent reads the real-time INFORMATION_SCHEMA.QUERY_HISTORY table
function, because ACCOUNT_USAGE.QUERY_HISTORY lags by up to ~45 minutes.

Workflow:
  1. Execute a deliberately complex, anti-pattern-heavy query.
  2. Call the Workload Cost agent to attribute the cost of that execution.
  3. Call the SQL Optimizer agent to rewrite the query.
  4. Execute the optimized query.
  5. Call the Workload Cost agent again and compare.

Usage:
    python tpch_cost_optimize_example.py
    python tpch_cost_optimize_example.py --warehouse COMPUTE_WH
"""

import argparse
import asyncio
import json
import re
import textwrap

from pydantic import BaseModel
from cortex_code_agent_sdk import (
    query,
    CortexCodeSDKClient,
    CortexCodeAgentOptions,
    AssistantMessage,
    ResultMessage,
)

# ---------------------------------------------------------------------------
# Deliberately bad query — packed with anti-patterns for the optimizer to fix
# ---------------------------------------------------------------------------

BAD_QUERY = textwrap.dedent("""\
    SELECT *
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.CUSTOMER c,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS o,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM l,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.SUPPLIER s,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.NATION n
    WHERE o.O_CUSTKEY = c.C_CUSTKEY
      AND l.L_ORDERKEY = o.O_ORDERKEY
      AND s.S_SUPPKEY = l.L_SUPPKEY
      AND n.N_NATIONKEY = s.S_NATIONKEY
      AND CAST(o.O_ORDERDATE AS VARCHAR) >= '1997-01-01'
      AND CAST(o.O_ORDERDATE AS VARCHAR) < '1998-01-01'
      AND o.O_ORDERSTATUS IN (
            SELECT DISTINCT O_ORDERSTATUS
            FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS sub
            WHERE sub.O_ORDERSTATUS = o.O_ORDERSTATUS
              AND sub.O_TOTALPRICE > 0
            ORDER BY sub.O_ORDERSTATUS
          )
      AND l.L_QUANTITY > (
            SELECT AVG(l2.L_QUANTITY)
            FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM l2
            WHERE l2.L_PARTKEY = l.L_PARTKEY
          )
      AND EXISTS (
            SELECT 1
            FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.PARTSUPP ps
            WHERE ps.PS_SUPPKEY = l.L_SUPPKEY
              AND ps.PS_PARTKEY = l.L_PARTKEY
              AND ps.PS_AVAILQTY > 0
          )
    GROUP BY
      c.C_CUSTKEY, c.C_NAME, c.C_ADDRESS, c.C_NATIONKEY, c.C_PHONE,
      c.C_ACCTBAL, c.C_MKTSEGMENT, c.C_COMMENT,
      o.O_ORDERKEY, o.O_CUSTKEY, o.O_ORDERSTATUS, o.O_TOTALPRICE,
      o.O_ORDERDATE, o.O_ORDERPRIORITY, o.O_CLERK, o.O_SHIPPRIORITY,
      o.O_COMMENT,
      l.L_ORDERKEY, l.L_PARTKEY, l.L_SUPPKEY, l.L_LINENUMBER,
      l.L_QUANTITY, l.L_EXTENDEDPRICE, l.L_DISCOUNT, l.L_TAX,
      l.L_RETURNFLAG, l.L_LINESTATUS, l.L_SHIPDATE, l.L_COMMITDATE,
      l.L_RECEIPTDATE, l.L_SHIPINSTRUCT, l.L_SHIPMODE, l.L_COMMENT,
      s.S_SUPPKEY, s.S_NAME, s.S_ADDRESS, s.S_NATIONKEY, s.S_PHONE,
      s.S_ACCTBAL, s.S_COMMENT,
      n.N_NATIONKEY, n.N_NAME, n.N_REGIONKEY, n.N_COMMENT
    HAVING SUM(l.L_EXTENDEDPRICE * (1 - l.L_DISCOUNT)) > 500000
    UNION
    SELECT *
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.CUSTOMER c2,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS o2,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM l2,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.SUPPLIER s2,
         SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.NATION n2
    WHERE o2.O_CUSTKEY = c2.C_CUSTKEY
      AND l2.L_ORDERKEY = o2.O_ORDERKEY
      AND s2.S_SUPPKEY = l2.L_SUPPKEY
      AND n2.N_NATIONKEY = s2.S_NATIONKEY
      AND o2.O_ORDERDATE >= DATE '1996-01-01'
      AND o2.O_ORDERDATE <  DATE '1997-01-01'
      AND o2.O_ORDERSTATUS = 'F'
    GROUP BY
      c2.C_CUSTKEY, c2.C_NAME, c2.C_ADDRESS, c2.C_NATIONKEY, c2.C_PHONE,
      c2.C_ACCTBAL, c2.C_MKTSEGMENT, c2.C_COMMENT,
      o2.O_ORDERKEY, o2.O_CUSTKEY, o2.O_ORDERSTATUS, o2.O_TOTALPRICE,
      o2.O_ORDERDATE, o2.O_ORDERPRIORITY, o2.O_CLERK, o2.O_SHIPPRIORITY,
      o2.O_COMMENT,
      l2.L_ORDERKEY, l2.L_PARTKEY, l2.L_SUPPKEY, l2.L_LINENUMBER,
      l2.L_QUANTITY, l2.L_EXTENDEDPRICE, l2.L_DISCOUNT, l2.L_TAX,
      l2.L_RETURNFLAG, l2.L_LINESTATUS, l2.L_SHIPDATE, l2.L_COMMITDATE,
      l2.L_RECEIPTDATE, l2.L_SHIPINSTRUCT, l2.L_SHIPMODE, l2.L_COMMENT,
      s2.S_SUPPKEY, s2.S_NAME, s2.S_ADDRESS, s2.S_NATIONKEY, s2.S_PHONE,
      s2.S_ACCTBAL, s2.S_COMMENT,
      n2.N_NATIONKEY, n2.N_NAME, n2.N_REGIONKEY, n2.N_COMMENT
    HAVING SUM(l2.L_EXTENDEDPRICE * (1 - l2.L_DISCOUNT)) > 500000
    ORDER BY 1, 9
    LIMIT 200
""")

# ---------------------------------------------------------------------------
# Structured output schemas
# ---------------------------------------------------------------------------

class WarehouseCost(BaseModel):
    warehouse_name: str
    total_credits: float
    query_count: int
    avg_execution_time_s: float

class TopQuery(BaseModel):
    query_id: str
    query_text_preview: str
    credits_used: float
    execution_time_s: float

class Recommendation(BaseModel):
    category: str
    description: str
    estimated_savings_pct: float

class CostReport(BaseModel):
    summary: str
    total_credits: float
    by_warehouse: list[WarehouseCost]
    top_expensive_queries: list[TopQuery]
    recommendations: list[Recommendation]


class Optimization(BaseModel):
    category: str
    description: str
    before: str
    after: str
    impact: str

class Warning(BaseModel):
    severity: str
    message: str

class OptimizationReport(BaseModel):
    summary: str
    original_query: str
    optimized_query: str
    optimization_count: int
    optimizations: list[Optimization]
    warnings: list[Warning]
    estimated_improvement: str

class ExecutionResult(BaseModel):
    query_id: str
    row_count: int

# Snowflake query IDs are UUID-shaped (8-4-4-4-12 hex digits).
QUERY_ID_RE = re.compile(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', re.IGNORECASE
)

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

COST_SYSTEM_PROMPT = """\
You are a Snowflake FinOps analyst. Analyze credit consumption for specific
query executions and produce structured cost breakdowns. Use the real-time
INFORMATION_SCHEMA.QUERY_HISTORY table function for recent queries (ACCOUNT_USAGE
lags by up to ~45 minutes). Base every number on actual data — never estimate
without a query.
"""

OPTIMIZER_SYSTEM_PROMPT = """\
You are a Snowflake SQL performance specialist. Analyze SQL queries, identify
anti-patterns, and produce optimized rewrites following Snowflake best practices.

Rules:
- Replace SELECT * with explicit column lists.
- Push filters early for partition pruning.
- Prefer QUALIFY over subqueries for window function filtering.
- Replace correlated subqueries with JOINs or window functions.
- Avoid implicit type casts in predicates (they disable pruning).
- Prefer UNION ALL over UNION when duplicate elimination is unnecessary.
- Use DATE_TRUNC instead of EXTRACT-based grouping.
- Use :: cast syntax for readability.
- Avoid ORDER BY in subqueries unless paired with LIMIT.
- Use explicit ANSI JOIN syntax instead of comma-separated FROM clauses.
"""

# ---------------------------------------------------------------------------
# Agent runners
# ---------------------------------------------------------------------------

async def run_cost_agent(query_ids: list[str], label: str, warehouse: str) -> CostReport | None:
    ids_str = ", ".join(f"'{qid}'" for qid in query_ids)
    prompt = f"""\
Analyze the cost of these specific query executions on warehouse '{warehouse}'.

Query IDs: {ids_str}

Steps:
1. These queries ran moments ago, and SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
   lags by up to ~45 minutes. Look them up with the real-time table function
   TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 10000)) filtered on
   QUERY_ID (run it with any current database set). Get
   EXECUTION_TIME, COMPILATION_TIME, BYTES_SCANNED, ROWS_PRODUCED,
   CREDITS_USED_CLOUD_SERVICES, PARTITIONS_SCANNED, PARTITIONS_TOTAL,
   BYTES_SPILLED_TO_LOCAL_STORAGE, BYTES_SPILLED_TO_REMOTE_STORAGE.
2. Calculate estimated compute credits = (EXECUTION_TIME / 1000 / 3600) *
   warehouse_credits_per_hour. Use the warehouse size to look up the rate.
3. Report total credits, per-query breakdown, and optimization opportunities.

Label this analysis: {label}
"""
    schema = CostReport.model_json_schema()
    report = None

    print(f"\n{'='*60}")
    print(f"  WORKLOAD COST AGENT — {label}")
    print(f"{'='*60}\n")

    async for message in query(
        prompt=prompt,
        options=CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=COST_SYSTEM_PROMPT,
            output_format={"type": "json_schema", "schema": schema},
            max_turns=15,
        ),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text, end="")
        elif isinstance(message, ResultMessage):
            print(f"\n  (agent done — turns={message.num_turns}, "
                  f"duration={message.duration_ms}ms)")
            if message.structured_output:
                report = CostReport.model_validate(message.structured_output)

    return report


async def run_optimizer_agent(sql: str, warehouse: str) -> OptimizationReport | None:
    schema = OptimizationReport.model_json_schema()
    report = None

    print(f"\n{'='*60}")
    print(f"  SQL OPTIMIZER AGENT")
    print(f"{'='*60}\n")

    analyze_prompt = f"""\
Analyze this query for anti-patterns and optimization opportunities. If
possible, run EXPLAIN on warehouse {warehouse} to check partition pruning.

```sql
{sql}
```

Report every issue you find. Do NOT produce the rewrite yet.
"""

    rewrite_prompt = """\
Now produce the optimized and properly formatted query. Ensure semantic
equivalence (same result set). For each optimization explain the category,
what changed, and Snowflake-specific impact. Return the structured JSON.
"""

    async with CortexCodeSDKClient(
        CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=OPTIMIZER_SYSTEM_PROMPT,
        )
    ) as client:
        # Turn 1 — analyze
        print("--- Turn 1: Analyzing anti-patterns ---\n")
        await client.query(analyze_prompt)
        async for msg in client.receive_response():
            if isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if hasattr(block, "text"):
                        print(block.text, end="")
            elif isinstance(msg, ResultMessage):
                print(f"\n  (turn 1 done — {msg.num_turns} agent turns)\n")

        # Turn 2 — rewrite with structured output
        print("--- Turn 2: Rewriting and optimizing ---\n")
        # Turn 2 needs structured output, but options are fixed when the client is
        # created and the SDK has no public setter, so this swaps the private
        # _options attribute. If the running session ignores it, the result has no
        # structured_output and the script prints "No structured output returned."
        client._options = CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=OPTIMIZER_SYSTEM_PROMPT,
            output_format={"type": "json_schema", "schema": schema},
        )

        await client.query(rewrite_prompt)
        async for msg in client.receive_response():
            if isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if hasattr(block, "text"):
                        print(block.text, end="")
            elif isinstance(msg, ResultMessage):
                print(f"\n  (agent done — turns={msg.num_turns}, "
                      f"duration={msg.duration_ms}ms)")
                if msg.structured_output:
                    report = OptimizationReport.model_validate(
                        msg.structured_output
                    )

    return report


async def execute_query(sql: str, warehouse: str, label: str) -> str | None:
    """Run a SQL query via the SDK and return its query_id.

    The agent returns the ID as structured output (ExecutionResult). If that is
    missing, fall back to the last UUID-shaped string in the agent's text.
    """
    prompt = f"""\
Execute the following SQL query on warehouse {warehouse}. Use LIMIT 200 if the
query does not already have one. After execution, return the QUERY_ID from
LAST_QUERY_ID() and the row count.

```sql
{sql}
```

Report the QUERY_ID and basic execution stats, then return the QUERY_ID and
row count as the structured output.
"""
    query_id = None
    fallback_id = None

    print(f"\n{'='*60}")
    print(f"  EXECUTING QUERY — {label}")
    print(f"{'='*60}\n")

    async for message in query(
        prompt=prompt,
        options=CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt="Execute the SQL query and report the QUERY_ID and row count.",
            output_format={"type": "json_schema", "schema": ExecutionResult.model_json_schema()},
            max_turns=5,
        ),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text, end="")
                    matches = QUERY_ID_RE.findall(block.text)
                    if matches:
                        fallback_id = matches[-1]
        elif isinstance(message, ResultMessage):
            print(f"\n  (done — turns={message.num_turns})")
            if message.structured_output:
                result = ExecutionResult.model_validate(message.structured_output)
                if QUERY_ID_RE.fullmatch(result.query_id.strip()):
                    query_id = result.query_id.strip()

    return query_id or fallback_id


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

async def run(warehouse: str) -> None:
    print("=" * 60)
    print("  TPCH SF100 — Cost → Optimize → Cost Workflow")
    print("=" * 60)
    print(f"\n  Warehouse: {warehouse}")
    print(f"  Dataset:   SNOWFLAKE_SAMPLE_DATA.TPCH_SF100")
    print(f"  LINEITEM:  ~600 million rows\n")

    # Step 1 — Execute the bad query
    print("\n" + "#" * 60)
    print("# STEP 1: Execute the original (unoptimized) query")
    print("#" * 60)
    bad_query_id = await execute_query(BAD_QUERY, warehouse, "Original (bad) query")

    if not bad_query_id:
        print("\nFailed to capture query_id for the original query. "
              "Check QUERY_HISTORY manually.")
        return

    print(f"\n  Captured query_id: {bad_query_id}")

    # Step 2 — Cost attribution for the bad query
    print("\n" + "#" * 60)
    print("# STEP 2: Workload Cost Attribution — BEFORE optimization")
    print("#" * 60)
    cost_before = await run_cost_agent(
        [bad_query_id], "BEFORE optimization", warehouse
    )
    if cost_before:
        print(f"\n  Total credits (before): {cost_before.total_credits}")

    # Step 3 — Optimize the query
    print("\n" + "#" * 60)
    print("# STEP 3: SQL Optimizer — Analyze and rewrite")
    print("#" * 60)
    opt_report = await run_optimizer_agent(BAD_QUERY, warehouse)

    if not opt_report:
        print("\nOptimizer did not return a report.")
        return

    print(f"\n  Optimizations applied: {opt_report.optimization_count}")
    print(f"  Estimated improvement: {opt_report.estimated_improvement}")
    print(f"\n--- Optimized query ---\n{opt_report.optimized_query[:500]}...")

    # Step 4 — Execute the optimized query
    print("\n" + "#" * 60)
    print("# STEP 4: Execute the optimized query")
    print("#" * 60)
    good_query_id = await execute_query(
        opt_report.optimized_query, warehouse, "Optimized query"
    )

    if not good_query_id:
        print("\nFailed to capture query_id for the optimized query.")
        return

    print(f"\n  Captured query_id: {good_query_id}")

    # Step 5 — Cost attribution for the optimized query
    print("\n" + "#" * 60)
    print("# STEP 5: Workload Cost Attribution — AFTER optimization")
    print("#" * 60)
    cost_after = await run_cost_agent(
        [good_query_id], "AFTER optimization", warehouse
    )
    if cost_after:
        print(f"\n  Total credits (after): {cost_after.total_credits}")

    # Step 6 — Summary comparison
    print("\n" + "#" * 60)
    print("# STEP 6: Comparison Summary")
    print("#" * 60)

    if cost_before and cost_after:
        delta = cost_before.total_credits - cost_after.total_credits
        pct = (delta / cost_before.total_credits * 100) if cost_before.total_credits > 0 else 0
        print(f"""
  ┌─────────────────────────────────────────────────┐
  │  BEFORE  credits: {cost_before.total_credits:<30}│
  │  AFTER   credits: {cost_after.total_credits:<30}│
  │  SAVINGS:         {delta:<10.6f} ({pct:.1f}%){"":>16}│
  │  Optimizations:   {opt_report.optimization_count:<30}│
  └─────────────────────────────────────────────────┘
""")
    else:
        print("\n  Could not compare — one or both cost reports missing.\n")

    # Dump full reports
    print("\n--- Full Cost Report (BEFORE) ---")
    if cost_before:
        print(json.dumps(cost_before.model_dump(), indent=2))

    print("\n--- Optimization Report ---")
    print(json.dumps(opt_report.model_dump(), indent=2))

    print("\n--- Full Cost Report (AFTER) ---")
    if cost_after:
        print(json.dumps(cost_after.model_dump(), indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="TPCH SF100 cost-optimize-cost workflow"
    )
    parser.add_argument(
        "--warehouse", default="COMPUTE_WH",
        help="Warehouse to execute queries on (default: COMPUTE_WH)",
    )
    args = parser.parse_args()
    asyncio.run(run(args.warehouse))


if __name__ == "__main__":
    main()
