# Snowflake Examples

A collection of example code and reference implementations for Snowflake, maintained by the **Qlik Partner Engineering** team.

## Overview

This repository contains working examples that demonstrate Snowflake + Qlik integration patterns, Cortex AI features, and Native App development. Each example is self-contained and includes setup instructions.

## Repository Structure

```
snowflake-examples/
├── mcp/                        # MCP server integrations (Qlik Cloud ↔ Snowflake)
├── sql/                        # SQL scripts and demos
├── native-apps/                # Native App Framework examples
│   ├── embedded-analytics-kit/ # Cortex Agent over Snowflake + Qlik dashboards
│   └── qlik-connector-app/     # Boilerplate Native App with Qlik MCP
├── skills/                     # Cortex Code skills for Qlik ↔ Snowflake workflows
├── coco-agent-sdk/             # Cortex Code Agent SDK prototypes (Python)
```

## What's Included

### MCP Integrations (`mcp/`)

- **[create-mcp-agent.sql](mcp/create-mcp-agent.sql)** — End-to-end SQL script to provision a Qlik Cloud MCP integration in Snowflake (API integration, external MCP server, Cortex Agent, Snowflake Intelligence registration).
- **[create-dual-source-agent.sql](mcp/create-dual-source-agent.sql)** — Creates a dual-source comparison agent that queries both Qlik MCP and a Snowflake Semantic View, then returns a structured comparison (expression/SQL, tool calls, duration, token usage).
- **[create-multi-mcp-agent.sql](mcp/create-multi-mcp-agent.sql)** — Creates a multi-MCP agent wired to two external MCP servers (e.g., Qlik + Salesforce/GitHub/Jira) with orchestration routing between tool namespaces.
- **[coco-qlik-mcp-public-client-setup.md](mcp/coco-qlik-mcp-public-client-setup.md)** — Setup guide for connecting Cortex Code CLI to Qlik MCP using a public OAuth client with PKCE.
- **[coco-desktop-qlik-mcp-public-client-setup-windows.md](mcp/coco-desktop-qlik-mcp-public-client-setup-windows.md)** — Same as above, tailored for Cortex Code Desktop on Windows.

### SQL Demos (`sql/`)

- **[cortex-ai-functions.sql](sql/cortex-ai-functions.sql)** — Demonstrates Snowflake Cortex AI functions (COMPLETE, SUMMARIZE, SENTIMENT, TRANSLATE, EXTRACT_ANSWER) using a sample product reviews dataset.
- **[cortex-search-rag.sql](sql/cortex-search-rag.sql)** — End-to-end Cortex Search + RAG pipeline: creates a knowledge base, builds a hybrid search service, and wires it to a Cortex Agent for retrieval-augmented generation.
- **[cortex-agent-token-usage.sql](sql/cortex-agent-token-usage.sql)** — Inspects token and credit consumption by Cortex Agents, broken down by agent and LLM model.

### Skills (`skills/`)

- **[qlik-dp-to-semantic-view.md](skills/qlik-dp-to-semantic-view.md)** — Cortex Code skill that converts a Qlik Talend Cloud Data Product into a Snowflake Semantic View, preserving governed metadata (descriptions, glossary definitions, trust scores) as first-class semantic metadata. Covers the full workflow: harvesting DP metadata via MCP, handling quoted-case identifiers, classifying fields, deriving metrics from glossary terms, building relationships, assembling DDL, and validating the result with Cortex Analyst.

### Native Apps (`native-apps/`)

- **[Embedded Analytics Starter Kit](native-apps/embedded-analytics-kit/)** — A Cortex Agent that provides a unified AI analytics experience over both Snowflake data (via a Semantic View) and Qlik Cloud dashboards (via MCP). Includes agent spec, semantic model, consumer setup, and sample questions.
- **[Qlik Connector App (Boilerplate)](native-apps/qlik-connector-app/)** — Minimal Native App template for any integration needing a Cortex Agent wired to both a Snowflake Semantic View and a Qlik MCP server. Copy and customize.

### Cortex Code Agent SDK (`coco-agent-sdk/`)

Python prototypes that embed the [Cortex Code Agent SDK](https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk) into Qlik integration workflows. Each script launches an agentic session that queries Snowflake autonomously and returns structured JSON suitable for consumption by Qlik Automate or the Qlik REST API.

- **[snowflake_rca_agent.py](coco-agent-sdk/snowflake_rca_agent.py)** — Investigates Snowflake-side failures when a Qlik reload or CDC pipeline errors out. Queries `QUERY_HISTORY` and `WAREHOUSE_EVENTS` and returns a root-cause report with remediation SQL.
- **[workload_cost_agent.py](coco-agent-sdk/workload_cost_agent.py)** — Attributes Snowflake credit consumption to Qlik-originated workloads. Breaks down costs by warehouse, surfaces the most expensive queries, and recommends scheduling or sizing optimizations.
- **[semantic_drift_agent.py](coco-agent-sdk/semantic_drift_agent.py)** — Compares a Qlik Data Product definition against a Snowflake Semantic View (multi-turn). Detects column drift, type mismatches, and broken verified queries, then produces reconciliation DDL.
- **[preflight_validator_agent.py](coco-agent-sdk/preflight_validator_agent.py)** — Pre-flight check before a Qlik pipeline runs: verifies target objects exist, the service role has required grants, warehouses are running, and dynamic tables are healthy. Includes a `PreToolUse` hook for SQL audit logging.
- **[legacy_translator_agent.py](coco-agent-sdk/legacy_translator_agent.py)** — Translates QlikView load scripts, QlikSense scripts, or Talend job XML into idiomatic Snowflake SQL (dynamic tables, COPY INTO, tasks). Rates confidence per statement and flags constructs needing manual review.
- **[data_freshness_agent.py](coco-agent-sdk/data_freshness_agent.py)** — SLA monitor that checks whether Qlik-managed tables meet freshness thresholds (multi-turn). Diagnoses root causes by cross-referencing `TASK_HISTORY` and produces remediation SQL.
- **[access_audit_agent.py](coco-agent-sdk/access_audit_agent.py)** — Audits Qlik service account grants against `ACCESS_HISTORY` to find unused privileges and access anomalies (multi-turn + audit hook). Returns least-privilege REVOKE/GRANT recommendations with risk ratings.

See the [coco-agent-sdk README](coco-agent-sdk/README.md) for setup, architecture diagrams, and the full SDK feature coverage matrix.

## Prerequisites

- A Snowflake account with Cortex AI enabled
- Appropriate roles and permissions for the features being demonstrated
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) (recommended)
- A Qlik Cloud tenant (for MCP and Native App examples)

## Getting Started

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd snowflake-examples
   ```

2. Navigate to the example you want to run and follow its local README or inline comments for setup instructions.

3. Configure your Snowflake connection using one of:
   - Snowflake CLI (`snow connection add`)
   - Environment variables (`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, etc.)
   - A `connections.toml` file

## Contributing

Contributions from the Qlik Partner Engineering team are welcome. When adding a new example:

1. Place it in the appropriate directory (or create a new one if needed).
2. Include a brief description at the top of the file or in a local README.
3. Ensure the example is self-contained and lists any prerequisites.
4. Test against a clean Snowflake environment before submitting.

## License

See [LICENSE](LICENSE) for details.

## Try Qlik Cloud

Ready to explore these integrations with your own data? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics) and see how Qlik + Snowflake work together.

## Contact

Maintained by the Qlik Partner Engineering team. For questions or issues, please open an issue in this repository.
