# Snowflake Examples

A collection of example code and reference implementations for Snowflake, maintained by the **Qlik Partner Engineering** team.

## Overview

This repository contains working examples that demonstrate Snowflake + Qlik integration patterns, Cortex AI features, and Native App development. Each example is self-contained and includes setup instructions.

## Repository Structure

```
snowflake-examples/
├── mcp/                        # MCP server integrations (Qlik Cloud ↔ Snowflake)
├── sql/                        # SQL scripts and demos
└── native-apps/                # Native App Framework examples
    ├── embedded-analytics-kit/ # Cortex Agent over Snowflake + Qlik dashboards
    └── qlik-connector-app/     # Boilerplate Native App with Qlik MCP
```

## What's Included

### MCP Integrations (`mcp/`)

- **[create-mcp-agent.sql](mcp/create-mcp-agent.sql)** — End-to-end SQL script to provision a Qlik Cloud MCP integration in Snowflake (API integration, external MCP server, Cortex Agent, Snowflake Intelligence registration).
- **[coco-qlik-mcp-public-client-setup.md](mcp/coco-qlik-mcp-public-client-setup.md)** — Setup guide for connecting Cortex Code CLI to Qlik MCP using a public OAuth client with PKCE.
- **[coco-desktop-qlik-mcp-public-client-setup-windows.md](mcp/coco-desktop-qlik-mcp-public-client-setup-windows.md)** — Same as above, tailored for Cortex Code Desktop on Windows.

### SQL Demos (`sql/`)

- **[cortex-ai-functions.sql](sql/cortex-ai-functions.sql)** — Demonstrates Snowflake Cortex AI functions (COMPLETE, SUMMARIZE, SENTIMENT, TRANSLATE, EXTRACT, CLASSIFY, EMBED) using a sample product reviews dataset.

### Native Apps (`native-apps/`)

- **[Embedded Analytics Starter Kit](native-apps/embedded-analytics-kit/)** — A Cortex Agent that provides a unified AI analytics experience over both Snowflake data (via a Semantic View) and Qlik Cloud dashboards (via MCP). Includes agent spec, semantic model, consumer setup, and sample questions.
- **[Qlik Connector App (Boilerplate)](native-apps/qlik-connector-app/)** — Minimal Native App template for any integration needing a Cortex Agent wired to both a Snowflake Semantic View and a Qlik MCP server. Copy and customize.

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

## Contact

Maintained by the Qlik Partner Engineering team. For questions or issues, please open an issue in this repository.
