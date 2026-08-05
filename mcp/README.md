# MCP Integrations

Guides and scripts for connecting Snowflake to [Qlik Cloud](https://www.qlik.com/us/products/qlik-cloud) via the Model Context Protocol (MCP).

## Contents

| File | Description |
|------|-------------|
| [create-mcp-agent.sql](create-mcp-agent.sql) | End-to-end SQL script that provisions a Qlik Cloud MCP integration in Snowflake — creates an OAuth2 API integration, an external MCP server, a Cortex Agent wired to that server, and registers it with Snowflake Intelligence. |
| [coco-qlik-mcp-public-client-setup.md](coco-qlik-mcp-public-client-setup.md) | Setup guide for connecting **Cortex Code CLI** to the Qlik MCP server using a public OAuth client (Authorization Code + PKCE, no client secret). |
| [coco-desktop-qlik-mcp-public-client-setup-windows.md](coco-desktop-qlik-mcp-public-client-setup-windows.md) | Same as above, tailored for **Cortex Code Desktop** (VS Code-based IDE) on Windows. |

## Prerequisites

- A Snowflake account with Cortex AI enabled.
- A Qlik Cloud tenant with MCP activated by a tenant admin.
- For `create-mcp-agent.sql`: ACCOUNTADMIN (or equivalent privileges) and OAuth client credentials from Qlik.
- For the CoCo/Desktop guides: your user role must have **Qlik MCP → Allowed** under Qlik's *Features and actions → Agentic AI*.

## License

See [LICENSE](../LICENSE) for details.
