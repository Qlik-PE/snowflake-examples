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

| Tool | Procedure | Qlik API Endpoint |
|------|-----------|-------------------|
| `create_qlik_app` | `CREATE_QLIK_APP` | `POST /api/v1/apps` |
| `create_qlik_dataset` | `CREATE_QLIK_DATASET` | `POST /api/v1/data-sets` |
| `set_qlik_app_script` | `SET_QLIK_APP_SCRIPT` | `POST /api/v1/apps/{appId}/scripts` |
| `list_qlik_spaces` | `LIST_QLIK_SPACES` | `GET /api/v1/spaces` |
| `create_qlik_glossary` | `CREATE_QLIK_GLOSSARY` | `POST /api/v1/glossaries` |
| `create_qlik_glossary_term` | `CREATE_QLIK_GLOSSARY_TERM` | `POST /api/v1/glossaries/{id}/terms` |
| `create_qlik_data_product` | `CREATE_QLIK_DATA_PRODUCT` | `POST /api/v1/data-products` |
| `get_semantic_view_ddl` | `GET_SEMANTIC_VIEW_DDL` | Snowflake `GET_DDL()` |

## Skills

| Skill | Description |
|-------|-------------|
| `create_data_product_from_sv` | End-to-end workflow: inspect a Snowflake Semantic View, create Qlik datasets for each base table, create an app with load script, create a glossary with terms, and create a data product. |

## Prerequisites

- Snowflake account with ACCOUNTADMIN role
- Qlik Cloud tenant with a valid API key
- Warehouse for procedure execution

## Setup

1. Edit `setup.sql` and replace:
   - `<QLIK_API_KEY>` with your Qlik Cloud API key
   - `$QLIK_TENANT` with your tenant hostname (default: `partner-engineering-saas.us.qlikcloud.com`)
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
```

## Adding New Qlik API Endpoints

To add a new endpoint:

1. Create a stored procedure in `setup.sql` following the existing pattern (Python, EAI, requests)
2. Add a `tool_spec` entry in the agent specification (type: generic, with input_schema)
3. Add a `tool_resources` entry pointing to the procedure
4. Recreate the agent with `CREATE OR REPLACE AGENT`
