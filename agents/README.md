# Agents

Cortex Agents that reach external platforms by calling their REST APIs from Snowflake stored procedures. The procedures run behind an External Access Integration (EAI).

## Available Agents

| Agent | What it does | External platform |
|---|---|---|
| [qlik-api-agent](qlik-api-agent/) | Creates Qlik apps and load scripts, registers datasets, reloads apps, and builds Qlik Data Products from Snowflake Semantic Views | Qlik Cloud |

## Architecture Pattern

Every agent in this folder is built from the same layers:

```
Network Rule            allows egress to the external host
Secret(s)               API key, tenant hostname, ...
External Access Integration (EAI)
        │  (bundles the network rule and secrets)
        ▼
Stored Procedures       Python + requests, one per API operation
        │
        ▼
Cortex Agent            each procedure exposed as a "generic" tool
        +
MCP server (optional)   an External MCP Server for operations the vendor already exposes over MCP
        +
Skills                  multi-step workflows, stored as SKILL.md files on a stage
```

**When to use a procedure versus MCP:** write a stored procedure for operations the vendor's MCP server doesn't offer, or that need Snowflake-side data (for example, reading `INFORMATION_SCHEMA` to build a request). Use the vendor's MCP server for everything else, so you don't have to maintain that code.

## Adding a New Agent

1. Create a directory `agents/<agent-name>/`.
2. Add a `setup.sql` with all the DDL: network rule, secrets, EAI, procedures, skill stage and agent.
3. Put each skill at `skills/<skill_name>/SKILL.md`.
4. Add a `README.md` covering tools, skills, prerequisites and setup steps.
5. Add the agent to the table above and to the root [README](../README.md).
