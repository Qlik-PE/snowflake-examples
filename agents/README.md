# Agents

Cortex Agents that integrate Snowflake with external platforms via stored procedures backed by External Access Integrations (EAI).

## Available Agents

| Agent | Description | External Platform |
|-------|-------------|-------------------|
| [qlik-api-agent](qlik-api-agent/) | Creates apps, registers datasets, sets load scripts, and builds data products from Snowflake Semantic Views | Qlik Cloud |

## Architecture Pattern

Each agent follows the same pattern:

```
Network Rule (egress to external host)
  +
Secret (API key / credentials)
  +
External Access Integration (EAI)
  |
  v
Stored Procedures (Python + requests)
  |
  v
Cortex Agent (generic tools -> procedures)
  +
Skills (workflow orchestration via SKILL.md on stage)
```

**Agent tools** (stored procedures via EAI) handle operations that require Snowflake-side execution or don't have MCP equivalents. **MCP tools** from CoCo handle operations where a Qlik MCP server is already registered.

## Adding a New Agent

1. Create a directory under `agents/` with the agent name
2. Add a `setup.sql` with all DDL (network rule, secret, EAI, procedures, agent)
3. Add a `README.md` documenting tools, skills, prerequisites, and setup
4. Put skills under `skills/<skill_name>/SKILL.md`
5. Update this README and the root `README.md`
