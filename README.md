# Snowflake Examples

Working examples and reference implementations for integrating **Snowflake** with **Qlik Cloud**, maintained by the **Qlik Partner Engineering** team.

The examples cover Cortex Agents, Cortex AI functions, Cortex Search, Model Context Protocol (MCP) connections to Qlik Cloud, Snowflake Native Apps, and Qlik Automate workflows. Each example is self-contained: it has its own setup script and either a local README or a detailed header comment.

## Pick an Example

| I want to… | Start here |
|---|---|
| Let a Cortex Agent query and build content in Qlik Cloud through MCP | [`mcp/create-mcp-agent.sql`](mcp/create-mcp-agent.sql) |
| Compare Qlik and a Snowflake Semantic View answering the same question | [`mcp/create-dual-source-agent.sql`](mcp/create-dual-source-agent.sql) |
| Use Qlik as the primary source, with Snowflake as a fallback | [`mcp/create-mcp-first-fallback-agent.sql`](mcp/create-mcp-first-fallback-agent.sql) |
| Connect Cortex Code (CLI or Desktop) to the Qlik MCP server | [`mcp/`](mcp/) setup guides |
| Call the Qlik Cloud REST API from a Cortex Agent (create apps, datasets, data products) | [`agents/qlik-api-agent/`](agents/qlik-api-agent/) |
| Trigger a Cortex Agent from a Qlik Automate workflow | [`automate/qlik-automate-agent-orchestration/`](automate/qlik-automate-agent-orchestration/) |
| Package a Cortex Agent + Semantic View + Qlik MCP as a Native App | [`native-apps/`](native-apps/) |
| Try Cortex AI functions, Cortex Search/RAG, or analyze agent token cost | [`sql/`](sql/) |
| Turn a Qlik Data Product into a Snowflake Semantic View | [`skills/qlik-dp-to-semantic-view.md`](skills/qlik-dp-to-semantic-view.md) |
| Write, review or speed up Qlik chart expressions and set analysis | [`skills/qlik-expression-authoring.md`](skills/qlik-expression-authoring.md) |

## Repository Structure

```
snowflake-examples/
├── mcp/                                     # Qlik Cloud MCP ↔ Snowflake Cortex Agents
├── agents/
│   └── qlik-api-agent/                      # Cortex Agent calling the Qlik Cloud REST API
├── automate/
│   └── qlik-automate-agent-orchestration/   # Qlik Automate → Cortex Agent freshness SLA monitor
├── native-apps/
│   ├── embedded-analytics-kit/              # Native App: agent over a Semantic View + Qlik MCP
│   └── qlik-connector-app/                  # Minimal Native App template
├── sql/                                     # Standalone Cortex AI / Search / cost scripts
└── skills/                                  # Cortex Code skills
```

## What's Included

### MCP Integrations ([`mcp/`](mcp/))

These scripts connect Snowflake Cortex Agents to the Qlik Cloud MCP server, so an agent can search Qlik apps, compute measures with the Qlik engine, and create sheets, charts and master items.

| File | What it does |
|---|---|
| [create-mcp-agent.sql](mcp/create-mcp-agent.sql) | **Start here.** Creates the OAuth API integration, the External MCP Server, a Cortex Agent wired to it, and the Snowflake Intelligence registration. |
| [create-dual-source-agent.sql](mcp/create-dual-source-agent.sql) | Agent that answers every question from **both** Qlik MCP and a Semantic View, then returns a side-by-side comparison (expression/SQL, tool calls, duration, estimated tokens). |
| [create-mcp-first-fallback-agent.sql](mcp/create-mcp-first-fallback-agent.sql) | Agent that tries Qlik MCP first and falls back to a Semantic View only when Qlik cannot answer. |
| [create-multi-mcp-agent.sql](mcp/create-multi-mcp-agent.sql) | Agent wired to **two** MCP servers (Qlik plus e.g. Salesforce, GitHub or Jira), with routing rules between them. |
| [coco-qlik-mcp-public-client-setup.md](mcp/coco-qlik-mcp-public-client-setup.md) | Connect the **Cortex Code CLI** to Qlik MCP with a public OAuth client (PKCE, no client secret). |
| [coco-desktop-qlik-mcp-public-client-setup-windows.md](mcp/coco-desktop-qlik-mcp-public-client-setup-windows.md) | The same setup for **Cortex Code Desktop** on Windows. |

The [mcp README](mcp/README.md) covers the Qlik OAuth app setup and troubleshooting.

### Qlik API Agent ([`agents/qlik-api-agent/`](agents/qlik-api-agent/))

A Cortex Agent that calls the Qlik Cloud REST API through Python stored procedures and an External Access Integration. It has seven procedure tools (create apps, set load scripts, reload apps, register datasets, link glossaries, inspect semantic views and table columns). It also uses the Qlik MCP server for spaces, glossaries and data products. Two skills orchestrate the end-to-end flows:

- **Semantic View → Qlik Data Product:** datasets, a glossary and a documented data product.
- **Qlik Data Product → Qlik Sense app:** load script, master items and a starter sheet.

### Qlik Automate Orchestration ([`automate/qlik-automate-agent-orchestration/`](automate/qlik-automate-agent-orchestration/))

A Qlik Automate workflow asks a Cortex Agent to check data-freshness SLAs through a Snowflake procedure. The procedure parses the agent's answer and writes an audit row. When an SLA is breached, the workflow sends a Slack alert and reloads a Qlik app. The folder includes the agent and procedure SQL, a workflow definition and a setup guide.

### Native Apps ([`native-apps/`](native-apps/))

- **[Embedded Analytics Starter Kit](native-apps/embedded-analytics-kit/):** a Native App that ships a SaaS-metrics data model, a Semantic View and a Cortex Agent. After installation you wire it to your own Qlik MCP server.
- **[Qlik Connector App](native-apps/qlik-connector-app/):** a minimal template for any Native App that needs a Cortex Agent wired to a Semantic View and a Qlik MCP server.

### SQL Scripts ([`sql/`](sql/))

| File | What it does |
|---|---|
| [cortex-ai-functions.sql](sql/cortex-ai-functions.sql) | Tour of `COMPLETE`, `SUMMARIZE`, `SENTIMENT`, `TRANSLATE` and `EXTRACT_ANSWER` over a sample product-review table. No setup is needed beyond a warehouse. |
| [cortex-search-rag.sql](sql/cortex-search-rag.sql) | Builds a small knowledge base and a hybrid Cortex Search service, then wires the service to a Cortex Agent for retrieval-augmented generation (RAG). |
| [cortex-agent-token-usage.sql](sql/cortex-agent-token-usage.sql) | Analyzes Cortex Agent cost from `CORTEX_AGENT_USAGE_HISTORY`: tokens and credits by agent, service and model, cache-hit rate, and total cost including warehouse credits spent by agent-generated SQL. |

### Skills ([`skills/`](skills/))

- **[qlik-dp-to-semantic-view.md](skills/qlik-dp-to-semantic-view.md):** a Cortex Code skill that converts a Qlik Talend Cloud Data Product into a Snowflake Semantic View. It keeps the governed metadata (descriptions, glossary definitions, trust score) as semantic-view comments, metrics and relationships.
- **[qlik-expression-authoring.md](skills/qlik-expression-authoring.md):** a Cortex Code skill for writing, reviewing and optimizing Qlik Sense / Qlik Cloud chart expressions. Covers the script-vs-expression placement decision, set analysis in place of `If()` inside aggregations, date and dollar-sign-expansion pitfalls, disciplined `Aggr()` use, master measures, and a performance and verification checklist.

## Prerequisites

- A Snowflake account with Cortex AI and Cortex Agents enabled, and the `SNOWFLAKE.CORTEX_USER` database role granted to your role.
- A role that can create the objects each script needs. Most scripts assume `ACCOUNTADMIN`; the script headers list narrower alternatives where they apply.
- A warehouse.
- For anything Qlik-related: a Qlik Cloud tenant. MCP examples also need MCP enabled by a tenant admin and an OAuth client (see the [mcp README](mcp/README.md)).
- Optional: [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) for running scripts and deploying Native Apps.

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/Qlik-PE/snowflake-examples.git
   cd snowflake-examples
   ```
2. Pick an example from the table above and open its README (or the header comment of the `.sql` file).
3. Fill in the configuration block at the top of the script (the `SET ...` statements or `<placeholder>` values).
4. Run the script in a Snowsight worksheet, or with the Snowflake CLI:
   ```bash
   snow sql -f mcp/create-mcp-agent.sql
   ```
   Some scripts contain several result-producing statements. Their headers say when to run statements one at a time.

## Contributing

Contributions from the Qlik Partner Engineering team are welcome. When adding an example:

1. Put it in the matching directory, or create a new one.
2. Describe it at the top of the file or in a local README: what it creates, prerequisites, and how to run it.
3. Keep it self-contained, with every environment-specific value in one configuration block.
4. Test it against a clean Snowflake account before submitting.
5. Add it to the **Pick an Example** table and the **What's Included** section above.

## License

See [LICENSE](LICENSE).

## Try Qlik Cloud

Want to try these integrations with your own data? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics).

## Contact

Maintained by the Qlik Partner Engineering team. For questions or problems, open an issue in this repository.
