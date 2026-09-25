# Qlik API Agent

A Snowflake Cortex Agent that works with Qlik Cloud from natural language. It can create Qlik Sense apps, set load scripts, reload apps, register Snowflake tables as Qlik datasets, and turn a Snowflake Semantic View into a documented Qlik Data Product.

## Architecture

```
User (Snowflake Intelligence / SQL / REST API)
  │
  ▼
Cortex Agent: QLIK_API_AGENT
  ├── generic tools ──► Python stored procedures
  │                       └── External Access Integration (QLIK_CLOUD_EAI)
  │                             ├── Network rule: egress to <tenant>.qlikcloud.com
  │                             ├── Secrets: Qlik API key, tenant hostname
  │                             ▼
  │                           Qlik Cloud REST API
  │
  ├── mcp_servers ────► External MCP Server (Qlik MCP)
  │                       spaces, search, glossaries, data products, sheets, master items
  │
  └── skills ─────────► SKILL.md files on @AGENT_SKILLS_STAGE
```

## Tools

### Stored-procedure tools (defined in `setup.sql`)

| Agent tool | Procedure | What it calls |
|---|---|---|
| `create_qlik_app` | `CREATE_QLIK_APP` | `POST /api/v1/apps`. `SPACE_ID` is required; without it the app would land in a personal space. |
| `set_qlik_app_script` | `SET_QLIK_APP_SCRIPT` | `POST /api/v1/apps/{appId}/scripts` |
| `reload_qlik_app` | `RELOAD_QLIK_APP` | `POST /api/v1/reloads`, then polls `GET /api/v1/reloads/{id}` every 10 s for up to 5 minutes |
| `create_qlik_dataset` | `CREATE_QLIK_DATASET` | `POST /api/v1/catalog/catalog-integration/actions/create-hierarchy-for-connected-datasets` (see below) |
| `link_glossary_to_data_product` | `LINK_GLOSSARY_TO_DATA_PRODUCT` | `GET` then `PATCH /api/data-governance/data-products/{id}` (JSON Patch `replace` on `/glossaryIds`) |
| `get_semantic_view_ddl` | `GET_SEMANTIC_VIEW_DDL` | Snowflake `GET_DDL('SEMANTIC VIEW', …)` |
| `get_table_columns` | `GET_TABLE_COLUMNS` | Snowflake `<db>.INFORMATION_SCHEMA.COLUMNS` |

### Qlik MCP tools

Everything else goes through the Qlik MCP server attached to the agent (the `mcp_servers` block in the agent spec). The skills use, among others: `qlik_search`, `qlik_search_spaces`, `qlik_create_glossary`, `qlik_create_glossary_term`, `qlik_create_data_product`, `qlik_update_data_product`, `qlik_get_data_product`, `qlik_create_dimension`, `qlik_create_measure`, `qlik_create_sheet` and `qlik_add_chart`.

The External MCP Server adds a server prefix to each tool name. The skills tell the agent to resolve the prefixed names by matching the suffix.

## Skills

| Skill | Workflow |
|---|---|
| [`create_data_product_from_sv`](skills/create_data_product_from_sv/SKILL.md) | Semantic View → Qlik Data Product. The agent reads the view DDL, creates one Qlik dataset per base table, creates a glossary with a term for every commented fact, dimension and metric, and creates a draft data product with those datasets attached. It then writes a README (tables, relationships, metrics) and links the glossary. |
| [`create_app_from_data_product`](skills/create_app_from_data_product/SKILL.md) | Qlik Data Product → Qlik Sense app. The agent finds the data product, generates a load script (linking tables through shared key fields, with composite keys combined and loops avoided), creates and reloads the app, creates master dimensions and measures from the glossary, and builds an overview sheet with KPIs, bar, line and table charts. |

Both skills stop at **GATE** checkpoints and wait for user confirmation. For example, the agent always asks which Qlik space to use, and it never activates a data product (it leaves it in draft).

## Prerequisites

- `ACCOUNTADMIN`, or a role that can create network rules, secrets, external access integrations, procedures, stages and agents.
- A Qlik Cloud tenant and an **API key** for a user who can create apps, datasets, glossaries and data products in the target spaces.
- An **External MCP Server** in Snowflake that points at the Qlik MCP server. Create it with [`mcp/create-mcp-agent.sql`](../../mcp/create-mcp-agent.sql), then complete the OAuth flow for each user.
- A **Snowflake data connection in Qlik Cloud**. The datasets and load scripts read Snowflake data through it.
- A Snowflake role for Qlik to use when it reads the tables. `CREATE_QLIK_DATASET` defaults to `QLIK_DATA_PRODUCT`; create that role or pass a different `SF_ROLE`.
- A warehouse to run the procedures.

## Setup

1. **Edit `setup.sql`.** Set these values:

   | Where | Value |
   |---|---|
   | `SET QLIK_TENANT` | Tenant hostname, e.g. `mytenant.us.qlikcloud.com` (no `https://`) |
   | `SET TARGET_DB`, `SET TARGET_SCHEMA` | Where the objects are created |
   | `SET WAREHOUSE` | Warehouse for the procedures |
   | `SET QLIK_MCP_SERVER` | Fully qualified name of your External MCP Server |
   | `SECRET_STRING = '<QLIK_API_KEY>'` | Your Qlik API key |
   | `<WAREHOUSE>` (7×) and `<QLIK_MCP_SERVER>` (1×) **inside the agent specification** | The same values as above. The spec is a `$$` literal, so session variables are **not** substituted inside it. |

2. **Run the script:**
   ```bash
   snow sql -f agents/qlik-api-agent/setup.sql
   ```

3. **Upload the full skill files.** `setup.sql` only writes short placeholder `SKILL.md` stubs to the stage. Upload the real ones:
   ```sql
   PUT file://agents/qlik-api-agent/skills/create_data_product_from_sv/SKILL.md
       @AGENT_SKILLS_STAGE/create_data_product_from_sv/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   PUT file://agents/qlik-api-agent/skills/create_app_from_data_product/SKILL.md
       @AGENT_SKILLS_STAGE/create_app_from_data_product/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   ```

4. **Optional:** register the agent with Snowflake Intelligence and grant it to your users (commented out at the end of `setup.sql`).

5. **Test:**
   ```sql
   SELECT TRY_PARSE_JSON(
     SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
       '<DB>.<SCHEMA>.QLIK_API_AGENT',
       $${ "messages": [{ "role": "user", "content": [{ "type": "text",
           "text": "List my Qlik spaces" }] }] }$$,
       TRUE
     )
   ) AS resp;
   ```
   Then try a full workflow: *"Create a Qlik Data Product from the semantic view `MY_DB.MY_SCHEMA.MY_SV` using the `Snowflake_PROD` connection."*

## `CREATE_QLIK_DATASET` in detail

This procedure registers a Snowflake table as a Qlik dataset in a **single API call**, with no QRI or data-asset lookup. It:

- reads the table's columns from `<db>.INFORMATION_SCHEMA.COLUMNS`,
- maps Snowflake types to JDBC `dataType` codes (`NUMBER`→3, `DOUBLE`→8, `VARCHAR`→12, `BOOLEAN`→16, `DATE`→91, `TIME`→92, `TIMESTAMP_*`→93; any unmapped type falls back to `VARCHAR`),
- generates the Qlik selection script (`[TABLE]:\nSELECT "COL1", … FROM "DB"."SCHEMA"."TABLE";`),
- posts everything to the catalog-integration endpoint.

`SPACE_ID` and `CONNECTION_ID` are required. The procedure returns an error if either is missing.

```sql
CALL CREATE_QLIK_DATASET(
  'SNOWFLAKE_SAMPLE_DATA', 'TPCH_SF1', 'NATION',
  '<qlik-space-id>',
  '<qlik-connection-id>'
  -- , 'MY_QLIK_ROLE'   -- optional, defaults to QLIK_DATA_PRODUCT
);
```

On success the procedure returns `status: 201` and the created dataset IDs in `dataset_ids`.

> **Note:** the `create-hierarchy-for-connected-datasets` endpoint is the one the Qlik Cloud UI uses. It is not part of Qlik's documented public API. The payload below was captured from browser traffic and may change without notice.

<details>
<summary>Request payload</summary>

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
      "tableRequestParameters": "<JSON-stringified array of {name, value} pairs>"
    }
  }]
}
```

Each element of `fields`:

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

`ordinalPostion` is misspelled on purpose, because that is the spelling the API expects.

`tableRequestParameters` sets the Snowflake role, database and schema (`owner`):

```json
[
  {"name": "role",     "value": "QLIK_DATA_PRODUCT"},
  {"name": "database", "value": "MY_DB"},
  {"name": "owner",    "value": "MY_SCHEMA"}
]
```

</details>

## File Structure

```
qlik-api-agent/
├── setup.sql                                   # network rule, secrets, EAI, procedures, skill stage, agent
├── README.md
└── skills/
    ├── create_data_product_from_sv/SKILL.md    # Semantic View → Data Product
    └── create_app_from_data_product/SKILL.md   # Data Product → Qlik Sense app
```

## Adding a Qlik API Endpoint

1. Add a stored procedure to `setup.sql` that follows the existing pattern: Python, `EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)`, both secrets, and `requests` with a timeout.
2. Add a `tool_spec` entry (type `generic`, with an `input_schema` whose property names match the procedure's argument names).
3. Add a `tool_resources` entry that points to the procedure and a warehouse.
4. Re-run the `CREATE OR REPLACE AGENT` statement.
