"""
Access Audit Agent
===================
Audits Snowflake access patterns for Qlik service accounts. Identifies
over-privileged roles, unused grants, and access anomalies. Returns a
structured security report with least-privilege recommendations and
ready-to-run REVOKE/GRANT SQL.

Demonstrates the PreToolUse hook for SQL audit logging (same as
preflight_validator) combined with multi-turn conversation for deep
investigation.

Usage:
    python access_audit_agent.py --role QLIK_ROLE
    python access_audit_agent.py --role QLIK_ROLE --user QLIK_SVC --days 30
"""

import argparse
import asyncio
import json
import sys
from datetime import datetime, timezone

from pydantic import BaseModel
from cortex_code_agent_sdk import (
    CortexCodeSDKClient,
    CortexCodeAgentOptions,
    AssistantMessage,
    ResultMessage,
    HookMatcher,
)

# ---------------------------------------------------------------------------
# Structured output schema
# ---------------------------------------------------------------------------

class GrantDetail(BaseModel):
    privilege: str
    object_type: str
    object_name: str
    granted_on: str
    used_in_period: bool
    last_used: str

class AccessAnomaly(BaseModel):
    anomaly_type: str  # "unused_grant", "excessive_privilege", "cross_schema_access", "admin_grant"
    description: str
    severity: str  # "low", "medium", "high", "critical"
    object_name: str

class LeastPrivilegeAction(BaseModel):
    action: str  # "revoke", "grant", "replace_role"
    description: str
    sql: str
    risk: str  # "safe", "test_first", "breaking"

class AccessAuditReport(BaseModel):
    summary: str
    role: str
    user: str
    audit_period_days: int
    total_grants: int
    used_grants: int
    unused_grants: int
    anomaly_count: int
    grant_details: list[GrantDetail]
    anomalies: list[AccessAnomaly]
    recommendations: list[LeastPrivilegeAction]

# ---------------------------------------------------------------------------
# Audit hook
# ---------------------------------------------------------------------------

SQL_AUDIT_LOG: list[dict] = []

async def audit_sql_hook(input_data, tool_use_id, context):
    if input_data.get("tool_name") == "sql_execute":
        sql = input_data.get("tool_input", {}).get("sql", "")
        SQL_AUDIT_LOG.append({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "tool_use_id": tool_use_id,
            "sql": sql[:500],
        })
        print(f"  [AUDIT] {sql[:80]}...", file=sys.stderr)
    return {"continue_": True}

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a Snowflake security specialist embedded inside a Qlik integration.
Your job is to audit access patterns for service accounts and roles used by
Qlik pipelines. You identify over-privileged roles, unused grants, and
access anomalies, then recommend least-privilege adjustments.

Be conservative: only recommend revoking grants that are provably unused
within the audit period. Flag anything that requires testing before removal.
"""

def build_inventory_prompt(role: str, user: str) -> str:
    user_filter = f"Also check what role(s) user {user} uses via SHOW GRANTS TO USER." if user != "*" else ""
    return f"""\
Inventory all grants for role {role}.

Steps:
1. Run SHOW GRANTS TO ROLE {role} to list all privileges.
2. Run SHOW GRANTS OF ROLE {role} to see which users/roles inherit it.
3. Check for any ACCOUNTADMIN or SECURITYADMIN grants in the chain — flag these
   as critical anomalies.
4. Count total grants by object type (TABLE, SCHEMA, DATABASE, WAREHOUSE, etc.).
{user_filter}

Report what you find. Do NOT produce structured output yet.
"""

def build_usage_prompt(role: str, user: str, days: int) -> str:
    user_clause = f"AND USER_NAME = '{user}'" if user != "*" else ""
    return f"""\
Now cross-reference the grants against actual usage in the last {days} days.

Steps:
1. Query SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY for the last {days} days
   where ROLE_NAME = '{role}' {user_clause}. This shows which objects were
   actually accessed.
2. Compare the accessed objects against the grant inventory from the
   previous turn. Any grant whose object was NOT accessed is "unused".
3. Look for cross-schema or cross-database access patterns that suggest
   the role is broader than needed.
4. Check SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY for the user to spot
   unusual access times or client types.

Produce the final structured JSON output with:
- Complete grant details (marking each as used or unused)
- All anomalies found
- Least-privilege recommendations with REVOKE/GRANT SQL
- Risk rating for each recommendation (safe / test_first / breaking)
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(role: str, user: str, days: int) -> None:
    output_schema = AccessAuditReport.model_json_schema()

    print("Launching CoCo access audit agent (multi-turn)...")
    print(f"  role={role}  user={user}  period={days}d\n")

    hook_config = {
        "PreToolUse": [
            HookMatcher(
                matcher=None,
                hooks=[audit_sql_hook],
                timeout=10.0,
            ),
        ],
    }

    async with CortexCodeSDKClient(
        CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=SYSTEM_PROMPT,
            hooks=hook_config,
        )
    ) as client:
        # --- Turn 1: Inventory grants ---
        print("=== Turn 1: Inventorying grants ===\n")
        await client.query(build_inventory_prompt(role, user))
        async for msg in client.receive_response():
            if isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if hasattr(block, "text"):
                        print(block.text, end="")
            elif isinstance(msg, ResultMessage):
                print(f"\n  (turn 1 done, {msg.num_turns} agent turns)\n")

        # --- Turn 2: Cross-reference with usage and produce report ---
        print("=== Turn 2: Analyzing usage and producing recommendations ===\n")

        client._options = CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=SYSTEM_PROMPT,
            output_format={"type": "json_schema", "schema": output_schema},
            hooks=hook_config,
        )

        await client.query(build_usage_prompt(role, user, days))
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
                    report = AccessAuditReport.model_validate(msg.structured_output)
                    print("\n========== ACCESS AUDIT REPORT ==========")
                    print(json.dumps(report.model_dump(), indent=2))

                    if report.anomaly_count > 0:
                        print(f"\n*** {report.anomaly_count} anomaly(ies) detected ***")
                    print(f"Grants: {report.total_grants} total, "
                          f"{report.used_grants} used, {report.unused_grants} unused")
                else:
                    print("\nNo structured output returned.")

        if SQL_AUDIT_LOG:
            print(f"\n========== SQL AUDIT LOG ({len(SQL_AUDIT_LOG)} queries) ==========")
            print(json.dumps(SQL_AUDIT_LOG, indent=2))


def main():
    parser = argparse.ArgumentParser(description="Snowflake access audit for Qlik service accounts")
    parser.add_argument("--role", required=True,
                        help="Snowflake role to audit")
    parser.add_argument("--user", default="*",
                        help="Snowflake user to audit (default: all users of the role)")
    parser.add_argument("--days", type=int, default=30,
                        help="Lookback period in days (default: 30)")
    args = parser.parse_args()

    asyncio.run(run(args.role, args.user, args.days))


if __name__ == "__main__":
    main()
