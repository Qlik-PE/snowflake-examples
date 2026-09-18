---
name: create_data_product_from_sv
description: Creates a Qlik Data Product from a Snowflake Semantic View. Registers datasets, creates a glossary with documentation, creates a data product, and links everything together.
---

## Workflow: Create Qlik Data Product from Snowflake Semantic View

Follow these steps **in order**. Do NOT skip steps.

### Step 1: Gather inputs

1. The user should provide the **fully qualified Semantic View name** (e.g. `DB.SCHEMA.MY_VIEW`). If not provided, ask for it.
2. Call `mcp__qlik-local__spaces__list` to list all available Qlik spaces.
3. Present the spaces to the user and ask them to **choose a target space** for the data product.
4. Store the chosen `spaceId` and `spaceName`.

### Step 2: Inspect the Semantic View

1. Call `get_semantic_view_ddl` with `SEMANTIC_VIEW_NAME` set to the fully qualified semantic view name.
2. Parse the returned DDL to extract:
   - All **base tables** referenced (the physical tables behind the semantic view)
   - All **columns/measures/dimensions** defined
   - Any **descriptions** or documentation in the DDL
3. Present the list of base tables and columns to the user for confirmation.

### Step 3: Create Qlik Datasets (one per base table)

For **each base table** found in Step 2, call `create_qlik_dataset` with:
- **BODY**: a JSON string with:
  - `name`: the table name (e.g. `ORDERS`)
  - `technicalName`: the fully qualified Snowflake table name (e.g. `DB.SCHEMA.ORDERS`)
  - `description`: description from the semantic view if available, otherwise "Table from Semantic View <name>"
  - `type`: "CONNECTION"
  - `spaceId`: the spaceId chosen in Step 1
  - `qri` and `secureQri`: "qdf:Snowflake:SNOWFLAKE_MONITORING_DATA:<spaceId>:<fully_qualified_table_name>"
  - `dataAssetInfo`:
    - `id`: "Snowflake:SNOWFLAKE_MONITORING_DATA"
    - `dataStoreInfo`:
      - `id`: "Snowflake:SNOWFLAKE_MONITORING_DATA"
      - `technicalName`: "SNOWFLAKE_MONITORING_DATA"
  - `schema.dataFields`: array of fields, each with `name` and `dataType.type` mapped:
    - VARCHAR/STRING/TEXT -> STRING
    - NUMBER/INT/INTEGER/BIGINT/SMALLINT -> INTEGER
    - FLOAT/DOUBLE/REAL -> DOUBLE
    - DECIMAL/NUMERIC -> DECIMAL (include properties: {precision, scale})
    - DATE -> DATE
    - TIMESTAMP* -> TIMESTAMP
    - BOOLEAN -> BOOLEAN
    - BINARY/VARBINARY -> BINARY
    - Other -> STRING

Collect all returned dataset IDs.

### Step 4: Create a Qlik App with load script

1. Call `create_qlik_app` with:
   - `APP_NAME`: "Data Product - <semantic_view_short_name>"
   - `APP_DESCRIPTION`: "Auto-generated app for semantic view <semantic_view_name>"
   - `SPACE_ID`: the spaceId from Step 1
2. Capture the `appId` from the response (field: `attributes.id`).
3. Build a Qlik load script:
   ```
   LIB CONNECT TO 'Snowflake:SNOWFLAKE_MONITORING_DATA';

   <TableName>:
   LOAD *
   SQL SELECT * FROM <fully_qualified_table_name>;
   ```
   Repeat the LOAD block for each base table.
4. Call `set_qlik_app_script` with the `APP_ID`, the generated `SCRIPT`, and `VERSION_MESSAGE`: "Initial load script from Semantic View <name>".

### Step 5: Create a Glossary with documentation

1. Call `mcp__qlik-local__glossaries__create` with:
   - `name`: "Glossary - <semantic_view_short_name>"
   - `description`: "Business glossary auto-generated from Snowflake Semantic View <semantic_view_name>"
2. Capture the glossary ID from the response.
3. For each column/measure/dimension from the semantic view that has a description, call `mcp__qlik-local__glossaries__create_term` with:
   - `glossaryId`: the glossary ID
   - `name`: the column/measure/dimension name
   - `description`: the description from the semantic view DDL

### Step 6: Create the Data Product

1. Call `mcp__qlik-local__data_products__create` with:
   - `name`: "<semantic_view_short_name> Data Product"
   - `description`: "Data product from Snowflake Semantic View <semantic_view_name>. Contains <N> datasets and a business glossary."
   - `spaceId`: the spaceId from Step 1
2. Capture the dataProductId.

### Step 7: Summary

Present a final summary:
- **Data Product**: name and ID
- **Datasets created**: list with names and IDs
- **App created**: name and ID
- **Glossary created**: name, ID, and number of terms
- **Space**: name
