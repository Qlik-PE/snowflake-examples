"""
Workload Cost Attribution Agent
================================
Queries SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY and attributes credit
consumption to Qlik-originated workloads. Returns a structured cost
breakdown with optimization recommendations.

Usage:
    python workload_cost_agent.py
    python workload_cost_agent.py --days 7 --user QLIK_SVC --warehouse QLIK_WH
"""

import argparse

from pydantic import BaseModel

from _common import make_options, print_report, run_main, run_structured

# ---------------------------------------------------------------------------
# Structured output schema
# ---------------------------------------------------------------------------

class WarehouseCost(BaseModel):
    warehouse_name: str
    total_credits: float
    query_count: int
    avg_execution_time_s: float
    peak_hour_utc: int

class TopQuery(BaseModel):
    query_id: str
    query_text_preview: str
    credits_used: float
    execution_time_s: float
    warehouse_name: str

class Recommendation(BaseModel):
    category: str  # "resize", "scheduling", "caching", "cleanup"
    description: str
    estimated_savings_pct: float
    sql: str

class CostReport(BaseModel):
    summary: str
    total_credits: float
    period_days: int
    by_warehouse: list[WarehouseCost]
    top_expensive_queries: list[TopQuery]
    recommendations: list[Recommendation]

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a Snowflake FinOps specialist embedded inside a Qlik integration.
Your job is to analyze Snowflake credit consumption for Qlik-originated
workloads and produce actionable cost optimization recommendations.

Use SNOWFLAKE.ACCOUNT_USAGE views: QUERY_HISTORY, WAREHOUSE_METERING_HISTORY,
and WAREHOUSE_LOAD_HISTORY. Always base recommendations on actual data.
"""

def build_prompt(days: int, user: str, warehouse: str) -> str:
    user_filter = f"user '{user}'" if user != "*" else "all users"
    wh_filter = f"warehouse '{warehouse}'" if warehouse != "*" else "all warehouses"
    return f"""\
Analyze Snowflake credit consumption for Qlik workloads over the last {days} days.

Filters:
- User: {user_filter}
- Warehouse: {wh_filter}

Steps:
1. Query WAREHOUSE_METERING_HISTORY for total credits by warehouse in the period.
2. Query QUERY_HISTORY to get query counts, avg execution time, and peak usage
   hours, filtered by the user/warehouse above.
3. Identify the top 5 most expensive queries by credits_used_cloud_services +
   estimated compute cost (execution_time * warehouse credit rate).
4. Recommend optimizations: warehouse resizing, multi-cluster scaling, query
   caching, scheduling off-peak, dropping unused objects consuming storage.
5. Estimate savings percentage for each recommendation.
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(days: int, user: str, warehouse: str) -> None:
    print("Launching CoCo cost attribution agent...")
    print(f"  period={days}d  user={user}  warehouse={warehouse}\n")

    report = await run_structured(
        build_prompt(days, user, warehouse),
        CostReport,
        make_options(SYSTEM_PROMPT, max_turns=15),
    )
    print_report("COST ATTRIBUTION REPORT", report)


def main():
    parser = argparse.ArgumentParser(description="Snowflake workload cost attribution agent")
    parser.add_argument("--days", type=int, default=7,
                        help="Lookback period in days (default: 7)")
    parser.add_argument("--user", default="*",
                        help="Snowflake user to filter on (default: all)")
    parser.add_argument("--warehouse", default="*",
                        help="Warehouse to filter on (default: all)")
    args = parser.parse_args()

    run_main(lambda: run(args.days, args.user, args.warehouse))


if __name__ == "__main__":
    main()
