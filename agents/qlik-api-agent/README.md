# Qlik API Agent

A Snowflake Cortex Agent that interacts with the Qlik Cloud REST API. It can create apps, register datasets, set load scripts, manage glossaries, and create data products -- all orchestrated by natural language.

## Architecture

```
User (CoWork / SQL / REST API)
  |
  v
Cortex Agent (QLIK_API_AGENT)
  |-- generic tools --> Stored Procedures (Python)
  |                       |-- External Access Integration (EAI)
  |                       |     |-- Network Rule (egress to qlikcloud.com)
  |                       |     |-- Secret (API key)
  |                       |     v
  |                       +-- Qlik Cloud REST API
  |
  +-- skill --> create_data_product_from_sv (SKILL.md on stage)
```

## Tools

### Agent tools (stored procedures via EAI)

| Tool | Procedure | Qlik API Endpoint |
|------|-----------|-------------------|
| `create_qlik_app` | `CREATE_QLIK_APP` | `POST /api/v1/apps` |
| `create_qlik_dataset` | `CREATE_QLIK_DATASET` | `POST /api/v1/catalog/catalog-integration/actions/create-hierarchy-for-connected-datasets` |
| `set_qlik_app_script` | `SET_QLIK_APP_SCRIPT` | `POST /api/v1/apps/{appId}/scripts` |
| `reload_qlik_app` | `RELOAD_QLIK_APP` | `POST /api/v1/reloads` (triggers reload, polls for completion up to 5 min) |
| `link_glossary_to_data_product` | `LINK_GLOSSARY_TO_DATA_PRODUCT` | `PATCH /api/data-governance/data-products/{id}` (JSON Patch: add glossaryIds) |
| `get_semantic_view_ddl` | `GET_SEMANTIC_VIEW_DDL` | Snowflake `GET_DDL()` |

### CoCo MCP tools (Qlik MCP server)

These are provided by the Qlik MCP server registered in CoCo and used by the skill workflow:

| MCP Tool | Qlik API Endpoint |
|----------|-------------------|
| `mcp__qlik-local__spaces__list` | `GET /api/v1/spaces` |
| `mcp__qlik-local__glossaries__create` | `POST /api/v1/glossaries` |
| `mcp__qlik-local__glossaries__create_term` | `POST /api/v1/glossaries/{id}/terms` |
| `mcp__qlik-local__data_products__create` | `POST /api/v1/data-products` |

## Skills

| Skill | Description |
|-------|-------------|
| `create_data_product_from_sv` | End-to-end workflow: inspect a Snowflake Semantic View, create Qlik datasets for each base table, create an app with load script, create a glossary with terms, and create a data product. |
| `create_app_from_data_product` | End-to-end workflow: discover a Qlik Data Product by name, generate a load script from dataset metadata, create a Qlik Sense app, reload it, create master dimensions and measures from the glossary, and build a default analytics sheet with KPIs, bar chart, line chart, and table. |

## Dataset Creation: `CREATE_QLIK_DATASET`

This approach:

- Creates the dataset in a **single call** (no QRI/dataAsset discovery needed)
- Auto-discovers table metadata from Snowflake `INFORMATION_SCHEMA.COLUMNS`
- Maps Snowflake types to JDBC `dataType` codes (NUMBER->3, VARCHAR->12, DOUBLE->8, TIMESTAMP->93, etc.)
- Generates the Qlik selection script in load-script format (`[TABLE]:\nSELECT ... FROM ...;`)
- Only requires `connectionId`, `database`, `schema`, and table metadata

**Usage:**
```sql
CALL CREATE_QLIK_DATASET('SNOWFLAKE_SAMPLE_DATA', 'TPCH_SF1', 'NATION');
```

**API contract** (reverse-engineered from browser network capture):
```json
{
  "spaceId": "<qlik-space-id>",
  "connectionId": "<qlik-connection-id>",
  "database": "<snowflake-database>",
  "schema": "<snowflake-schema>",
  "tables": [{
    "tableName": "<table-name>",
    "selectionScript": "[TABLE]:\nSELECT \"COL1\",\n\t\"COL2\"\nFROM \"DB\".\"SCHEMA\".\"TABLE\";",
    "additionalProperties": {
      "fields": "<JSON-stringified array of field objects>",
      "tableRequestParameters": "<JSON-stringified array of {name,value} pairs>"
    }
  }]
}
```

Each field object in the `fields` array:
```json
{
  "name": "COL_NAME",
  "fullName": "COL_NAME",
  "nativeType": "VARCHAR",
  "nativeFieldInfo": {
    "dataType": 12,
    "name": "COL_NAME",
    "nullable": 1,
    "ordinalPostion": 1,
    "scale": 0,
    "size": 16777216,
    "typeName": "VARCHAR"
  },
  "isSelected": true
}
```

The `tableRequestParameters` array sets the Snowflake role, database, and schema (owner):
```json
[
  {"name": "role", "value": "QLIK_DATA_PRODUCT"},
  {"name": "database", "value": "MY_DB"},
  {"name": "owner", "value": "MY_SCHEMA"}
]
```

Returns HTTP 201 with an array of created dataset IDs on success.

## Prerequisites

- Snowflake account with ACCOUNTADMIN role
- Qlik Cloud tenant with a valid API key
- Qlik MCP server registered in CoCo (for spaces, glossaries, data products)
- An existing `EXTERNAL MCP SERVER` object in Snowflake pointing to the Qlik MCP server (for server-side agent execution via CoWork/SQL)
- Warehouse for procedure execution

## Setup

1. Edit `setup.sql` and replace:
   - `<QLIK_API_KEY>` with your Qlik Cloud API key
   - `$QLIK_TENANT` with your tenant hostname (default: `partner-engineering-saas.us.qlikcloud.com`)
   - `$QLIK_MCP_SERVER` with the FQN of your existing External MCP Server for Qlik
   - `$TARGET_DB` / `$TARGET_SCHEMA` with your target database/schema
   - `$WAREHOUSE` with your warehouse name

2. Run `setup.sql` as ACCOUNTADMIN:
   ```sql
   !source setup.sql
   ```

3. Test the agent:
   ```sql
   SELECT TRY_PARSE_JSON(
     SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
       'TORRA.PUBLIC.QLIK_API_AGENT',
       $${ "messages": [{ "role": "user", "content": [{ "type": "text",
           "text": "Create a Qlik app called 'My Test App'" }] }] }$$,
       TRUE
     )
   ) AS resp;
   ```

## File Structure

```
qlik-api-agent/
  setup.sql                                    -- All DDL: network rule, secret, EAI, procedures, agent
  README.md                                    -- This file
  skills/
    create_data_product_from_sv/
      SKILL.md                                 -- Data product creation workflow
    create_app_from_data_product/
      SKILL.md                                 -- App creation from data product workflow
```

## Adding New Qlik API Endpoints

To add a new endpoint:

1. Create a stored procedure in `setup.sql` following the existing pattern (Python, EAI, requests)
2. Add a `tool_spec` entry in the agent specification (type: generic, with input_schema)
3. Add a `tool_resources` entry pointing to the procedure
4. Recreate the agent with `CREATE OR REPLACE AGENT`
