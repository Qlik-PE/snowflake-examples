# TPCH SF1000 — Cost → Optimize → Cost Walkthrough

End-to-end example that chains the **Workload Cost Attribution** and **SQL Optimizer** agents against `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000` (6 billion LINEITEM rows). The workflow demonstrates how the Cortex Code Agent SDK can measure the cost of a bad query, optimize it, and then measure the savings.

## Dataset

| Table | Row Count |
|---|---:|
| LINEITEM | 5,999,989,709 |
| ORDERS | 1,500,000,000 |
| PARTSUPP | 800,000,000 |
| PART | 200,000,000 |
| CUSTOMER | 150,000,000 |
| SUPPLIER | 10,000,000 |
| NATION | 25 |
| REGION | 5 |

## Workflow Overview

```
┌──────────────────────┐     ┌──────────────────────┐     ┌──────────────────────┐
│  Step 1               │     │  Step 3               │     │  Step 4               │
│  Execute BAD query    │────▶│  SQL Optimizer agent  │────▶│  Execute GOOD query   │
│  → capture query_id   │     │  → rewrite + report   │     │  → capture query_id   │
└──────────┬───────────┘     └──────────────────────┘     └──────────┬───────────┘
           │                                                         │
           ▼                                                         ▼
┌──────────────────────┐                               ┌──────────────────────┐
│  Step 2               │                               │  Step 5               │
│  Workload Cost agent  │                               │  Workload Cost agent  │
│  → BEFORE report      │                               │  → AFTER report       │
└──────────────────────┘                               └──────────────────────┘
                                                                    │
                                                                    ▼
                                                       ┌──────────────────────┐
                                                       │  Step 6               │
                                                       │  Compare BEFORE/AFTER │
                                                       └──────────────────────┘
```

## The Deliberately Bad Query

The query joins five tables from TPCH_SF1000 and is designed with as many anti-patterns as possible so the optimizer has real issues to fix:

```sql
SELECT *
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.CUSTOMER c,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.ORDERS o,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM l,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.SUPPLIER s,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.NATION n
WHERE o.O_CUSTKEY = c.C_CUSTKEY
  AND l.L_ORDERKEY = o.O_ORDERKEY
  AND s.S_SUPPKEY = l.L_SUPPKEY
  AND n.N_NATIONKEY = s.S_NATIONKEY
  AND CAST(o.O_ORDERDATE AS VARCHAR) >= '1997-01-01'
  AND CAST(o.O_ORDERDATE AS VARCHAR) < '1998-01-01'
  AND o.O_ORDERSTATUS IN (
        SELECT DISTINCT O_ORDERSTATUS
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.ORDERS sub
        WHERE sub.O_ORDERSTATUS = o.O_ORDERSTATUS
          AND sub.O_TOTALPRICE > 0
        ORDER BY sub.O_ORDERSTATUS
      )
  AND l.L_QUANTITY > (
        SELECT AVG(l2.L_QUANTITY)
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM l2
        WHERE l2.L_PARTKEY = l.L_PARTKEY
      )
  AND EXISTS (
        SELECT 1
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.PARTSUPP ps
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
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.CUSTOMER c2,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.ORDERS o2,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM l2,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.SUPPLIER s2,
     SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.NATION n2
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
```

### Anti-patterns embedded in the query

| # | Anti-Pattern | Location | Why It Hurts on Snowflake |
|---|---|---|---|
| 1 | **`SELECT *`** | Both branches of UNION | Returns all 44 columns from 5 tables. Forces Snowflake to read every micro-partition column, defeating columnar storage benefits. |
| 2 | **Implicit comma-join syntax** | `FROM ... c, o, l, s, n` | Old-style join. Harder for both the optimizer and humans to reason about join order. |
| 3 | **`CAST(O_ORDERDATE AS VARCHAR)`** | `WHERE CAST(o.O_ORDERDATE AS VARCHAR) >= '1997-01-01'` | Wrapping a DATE column in a VARCHAR cast disables partition pruning entirely. Snowflake cannot use the clustering metadata on `O_ORDERDATE` because it is comparing strings, not dates. |
| 4 | **Correlated subquery (tautological)** | `O_ORDERSTATUS IN (SELECT DISTINCT ... WHERE sub.O_ORDERSTATUS = o.O_ORDERSTATUS ...)` | Scans the entire 1.5B-row ORDERS table per outer row, just to confirm a status value exists — the WHERE clause is a tautology that always matches. |
| 5 | **`ORDER BY` inside a subquery** | `ORDER BY sub.O_ORDERSTATUS` inside the IN subquery | Snowflake must sort intermediate results that will be consumed as a set. The order is discarded by `IN`. |
| 6 | **Correlated subquery for AVG** | `L_QUANTITY > (SELECT AVG(...) WHERE l2.L_PARTKEY = l.L_PARTKEY)` | Runs an aggregate over the 6B-row LINEITEM table for every row in the outer query. Could be replaced with a window function or a pre-aggregated CTE. |
| 7 | **`UNION` instead of `UNION ALL`** | Between the two branches | UNION forces a global de-duplication sort across all 44 columns. The two branches query non-overlapping date ranges (1996 vs 1997) so duplicates are impossible. UNION ALL avoids the sort entirely. |
| 8 | **GROUP BY all 44 columns** | Both branches | Grouping by every column (including the primary key) means each group contains exactly one row. The GROUP BY + HAVING is logically a filter — it would be simpler and faster as a window function or CTE with a pre-aggregated sum. |
| 9 | **Inconsistent date filtering** | Branch 1: `CAST(... AS VARCHAR) >= '1997-01-01'`; Branch 2: `O_ORDERDATE >= DATE '1996-01-01'` | Branch 2 is already correct with a DATE literal. Branch 1 uses the VARCHAR anti-pattern. Inconsistency makes the UNION less amenable to predicate pushdown. |
| 10 | **EXISTS without correlation benefit** | `EXISTS (SELECT 1 FROM PARTSUPP ps WHERE ps.PS_SUPPKEY = l.L_SUPPKEY AND ps.PS_PARTKEY = l.L_PARTKEY ...)` | Not the worst anti-pattern, but when combined with the other subqueries, it adds a third correlated probe against the 800M-row PARTSUPP table on each outer row. Could be a semi-join. |

## SDK Patterns Used

### Workload Cost Agent — single-shot `query()`

The cost agent uses the stateless `query()` pattern with structured output. It receives one or more query IDs, analyzes `QUERY_HISTORY` for execution metrics, and returns a `CostReport` Pydantic model.

```python
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
    if isinstance(message, ResultMessage) and message.structured_output:
        report = CostReport.model_validate(message.structured_output)
```

### SQL Optimizer Agent — multi-turn `CortexCodeSDKClient`

The optimizer uses a two-turn pattern. Turn 1 analyzes anti-patterns without rewriting. Turn 2 produces the optimized query with structured output.

```python
async with CortexCodeSDKClient(
    CortexCodeAgentOptions(cwd=".", allowed_tools=["SQL"], system_prompt=OPTIMIZER_SYSTEM_PROMPT)
) as client:
    # Turn 1: analyze
    await client.query(analyze_prompt)
    async for msg in client.receive_response():
        ...

    # Turn 2: rewrite with structured output
    client._options = CortexCodeAgentOptions(
        ...,
        output_format={"type": "json_schema", "schema": schema},
    )
    await client.query(rewrite_prompt)
    async for msg in client.receive_response():
        ...
```

## What the Optimizer Should Find

When the SQL Optimizer agent processes this query, it should identify and fix the following:

| Optimization | Category | Expected Impact |
|---|---|---|
| Replace `SELECT *` with explicit columns needed by the HAVING clause | `pruning` | **High** — columnar scan reads only required columns |
| Convert comma-joins to explicit `INNER JOIN ... ON` | `join` | **Low** — readability; minor optimizer benefit |
| Remove `CAST(O_ORDERDATE AS VARCHAR)`, use `DATE` literal | `type_cast` | **High** — enables partition pruning on clustered column |
| Eliminate the tautological correlated IN subquery | `subquery` | **High** — removes a 1.5B-row correlated scan |
| Remove `ORDER BY` inside the IN subquery | `sort` | **Medium** — eliminates unnecessary intermediate sort |
| Replace correlated AVG subquery with a CTE or window function | `subquery` | **High** — single-pass aggregate instead of per-row probe |
| Change `UNION` to `UNION ALL` | `anti_pattern` | **High** — eliminates global dedup sort across 44 columns |
| Simplify GROUP BY all columns to a CTE + filter | `aggregation` | **Medium** — cleaner plan, less memory pressure |

## Running the Example

### Prerequisites

```bash
pip install cortex-code-agent-sdk pydantic
```

Cortex Code CLI must be authenticated against a Snowflake account with access to `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000`.

### Execute

```bash
# Default warehouse
python sdk/tpch_cost_optimize_example.py

# Specify a warehouse
python sdk/tpch_cost_optimize_example.py --warehouse ANALYTICS_WH
```

### Expected Output

The script produces console output for each step:

```
============================================================
  TPCH SF1000 — Cost → Optimize → Cost Workflow
============================================================

  Warehouse: COMPUTE_WH
  Dataset:   SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000
  LINEITEM:  ~6 billion rows

############################################################
# STEP 1: Execute the original (unoptimized) query
############################################################
  ...agent executes the bad query and captures query_id...

############################################################
# STEP 2: Workload Cost Attribution — BEFORE optimization
############################################################
  ...agent queries QUERY_HISTORY for execution metrics...
  Total credits (before): 0.XXXXXX

############################################################
# STEP 3: SQL Optimizer — Analyze and rewrite
############################################################
  --- Turn 1: Analyzing anti-patterns ---
  ...identifies 8-10 anti-patterns...

  --- Turn 2: Rewriting and optimizing ---
  ...produces optimized SQL...
  Optimizations applied: 8

############################################################
# STEP 4: Execute the optimized query
############################################################
  ...agent executes the rewritten query...

############################################################
# STEP 5: Workload Cost Attribution — AFTER optimization
############################################################
  ...agent queries QUERY_HISTORY for new execution metrics...
  Total credits (after): 0.XXXXXX

############################################################
# STEP 6: Comparison Summary
############################################################

  ┌─────────────────────────────────────────────────┐
  │  BEFORE  credits: 0.XXXXXX                      │
  │  AFTER   credits: 0.XXXXXX                      │
  │  SAVINGS:         0.XXXXXX (XX.X%)              │
  │  Optimizations:   8                             │
  └─────────────────────────────────────────────────┘
```

## Structured Output Schemas

### CostReport

```json
{
  "summary": "...",
  "total_credits": 0.003421,
  "by_warehouse": [
    {
      "warehouse_name": "COMPUTE_WH",
      "total_credits": 0.003421,
      "query_count": 1,
      "avg_execution_time_s": 45.2
    }
  ],
  "top_expensive_queries": [
    {
      "query_id": "01c7...",
      "query_text_preview": "SELECT * FROM ...",
      "credits_used": 0.003421,
      "execution_time_s": 45.2
    }
  ],
  "recommendations": [
    {
      "category": "type_cast",
      "description": "Remove VARCHAR cast on O_ORDERDATE to enable pruning",
      "estimated_savings_pct": 30.0
    }
  ]
}
```

### OptimizationReport

```json
{
  "summary": "10 anti-patterns identified, 8 optimizations applied",
  "original_query": "SELECT * FROM ...",
  "optimized_query": "WITH avg_qty AS (...) SELECT ...",
  "optimization_count": 8,
  "optimizations": [
    {
      "category": "type_cast",
      "description": "Replaced CAST(O_ORDERDATE AS VARCHAR) with native DATE comparison",
      "before": "CAST(o.O_ORDERDATE AS VARCHAR) >= '1997-01-01'",
      "after": "o.O_ORDERDATE >= DATE '1997-01-01'",
      "impact": "high"
    }
  ],
  "warnings": [],
  "estimated_improvement": "60-80% reduction in execution time and credits"
}
```

## How This Maps to the SDK Feature Matrix

| Feature | Used In This Example |
|---|---|
| `query()` (single-shot) | Cost agent (Steps 2, 5), query execution (Steps 1, 4) |
| `CortexCodeSDKClient` (multi-turn) | Optimizer agent (Step 3) |
| `allowed_tools=["SQL"]` | All agent calls |
| `system_prompt` | All agent calls |
| `output_format` (structured output) | Cost agent + optimizer turn 2 |
| `max_turns` | Cost agent (15), query executor (5) |
| Pydantic validation | `CostReport`, `OptimizationReport` |
| EXPLAIN plan analysis | Optimizer turn 1 |
| Multi-turn option switching | Optimizer (turn 1 no schema → turn 2 with schema) |
