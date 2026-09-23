# Snowflake Examples

A collection of example code and reference implementations for Snowflake, maintained by the **Qlik Partner Engineering** team.

## Overview

This repository contains working examples that demonstrate Snowflake + Qlik integration patterns, Cortex AI features, and Native App development. Each example is self-contained and includes setup instructions.

## Repository Structure

```
snowflake-examples/
├── cortex-code-sdk/                # Cortex Code Agent SDK (Python SDK + SQL CREATE AGENT)
│   ├── sdk/                        #   Python agents using the Cortex Code Agent SDK
│   ├── sql/                        #   SQL agents (code_toolset_all) with REST API examples
│   └── README.md                   #   Use case mapping, SDK vs REST comparison
├── mcp/                            # MCP server integrations (Qlik Cloud ↔ Snowflake)
├── sql/                            # SQL scripts and Cortex AI demos
├── native-apps/                    # Native App Framework examples
│   ├── embedded-analytics-kit/     #   Cortex Agent over Snowflake + Qlik dashboards
│   └── qlik-connector-app/         #   Boilerplate Native App with Qlik MCP
├── agents/                         # Cortex Agents with external API integrations
│   └── qlik-api-agent/            #   Qlik Cloud REST API agent (apps, datasets, glossaries, data products)
├── automate/                       # Qlik Automate workflow integrations
│   └── qlik-automate-agent-orchestration/  # Qlik Automate → Cortex Agent freshness SLA monitor
├── skills/                         # Cortex Code skills
```

## What's Included

### Cortex Code SDK (`cortex-code-sdk/`)

Seven operational use cases — failure RCA, cost attribution, semantic drift, pre-flight validation, SQL optimization, freshness monitoring, and access audit — each implemented as both a **Python SDK agent** and a **SQL `CREATE AGENT`** with REST API call examples. Plus a document intelligence agent (SQL only).

See the [cortex-code-sdk README](cortex-code-sdk/README.md) for the full use case mapping, SDK vs Cortex Agent comparison, and REST API calling guide.

### MCP Integrations (`mcp/`)

- **[create-mcp-agent.sql](mcp/create-mcp-agent.sql)** — End-to-end provisioning of a Qlik Cloud MCP integration (API integration, external MCP server, Cortex Agent, Snowflake Intelligence registration).
- **[create-dual-source-agent.sql](mcp/create-dual-source-agent.sql)** — Dual-source comparison agent: queries both Qlik MCP and a Snowflake Semantic View, returns a structured comparison (expression/SQL, tool calls, duration, token usage).
- **[create-multi-mcp-agent.sql](mcp/create-multi-mcp-agent.sql)** — Multi-MCP agent wired to two external MCP servers (e.g., Qlik + Salesforce/GitHub/Jira) with orchestration routing between tool namespaces.
- **[create-mcp-first-fallback-agent.sql](mcp/create-mcp-first-fallback-agent.sql)** — MCP-first agent with Semantic View fallback: routes every question to Qlik MCP first, falls back to Cortex Analyst only when Qlik cannot answer.
- **[coco-qlik-mcp-public-client-setup.md](mcp/coco-qlik-mcp-public-client-setup.md)** — Setup guide for connecting Cortex Code CLI to Qlik MCP using a public OAuth client with PKCE.
- **[coco-desktop-qlik-mcp-public-client-setup-windows.md](mcp/coco-desktop-qlik-mcp-public-client-setup-windows.md)** — Same as above, tailored for Cortex Code Desktop on Windows.

See the [mcp README](mcp/README.md) for OAuth setup, troubleshooting, and agent pattern details.

### SQL Demos (`sql/`)

- **[cortex-ai-functions.sql](sql/cortex-ai-functions.sql)** — Demonstrates Snowflake Cortex AI functions (COMPLETE, SUMMARIZE, SENTIMENT, TRANSLATE, EXTRACT_ANSWER) using a sample product reviews dataset.
- **[cortex-search-rag.sql](sql/cortex-search-rag.sql)** — End-to-end Cortex Search + RAG pipeline: creates a knowledge base, builds a hybrid search service, and wires it to a Cortex Agent for retrieval-augmented generation.
- **[cortex-agent-token-usage.sql](sql/cortex-agent-token-usage.sql)** — Cortex Agent cost and token analysis over `CORTEX_AGENT_USAGE_HISTORY`. Breaks consumption down by agent, service layer (`cortex_agents` vs `cortex_analyst`) and LLM model, with the input/output/cache token split and a cache-read percentage to spot agents that are missing prompt caching. Also reports total cost of ownership per agent — inference plus the warehouse credits burned by agent-generated SQL, which `TOKEN_CREDITS` alone omits — and includes a reconciliation query that proves the JSON flattening is lossless.

### Native Apps (`native-apps/`)

- **[Embedded Analytics Starter Kit](native-apps/embedded-analytics-kit/)** — A Cortex Agent providing a unified AI analytics experience over both Snowflake data (via a Semantic View) and Qlik Cloud dashboards (via MCP). Includes agent spec, semantic model, consumer setup, and sample questions.
- **[Qlik Connector App (Boilerplate)](native-apps/qlik-connector-app/)** — Minimal Native App template for any integration needing a Cortex Agent wired to both a Snowflake Semantic View and a Qlik MCP server.

### Agents (`agents/`)

- **[Qlik API Agent](agents/qlik-api-agent/)** — Cortex Agent that calls the Qlik Cloud REST API via stored procedures backed by an External Access Integration. Includes 8 tools (create apps, register datasets, set load scripts, list spaces, create glossaries/terms, create data products, inspect semantic views) and a skill that orchestrates end-to-end data product creation from a Snowflake Semantic View.

### Qlik Automate (`automate/`)

- **[Qlik Automate Agent Orchestration](automate/qlik-automate-agent-orchestration/)** — A Qlik Automate workflow that calls a Snowflake Cortex Agent via the REST API to monitor data freshness SLAs. On breach, the workflow sends Slack alerts, triggers Qlik app reloads as remediation, and writes audit records back to Snowflake. Includes the agent SQL, an importable Qlik Automate workflow definition, and a setup guide.

### Skills (`skills/`)

- **[qlik-dp-to-semantic-view.md](skills/qlik-dp-to-semantic-view.md)** — Cortex Code skill that converts a Qlik Talend Cloud Data Product into a Snowflake Semantic View, preserving governed metadata (descriptions, glossary definitions, trust scores).

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
