---
name: create_data_product_from_sv
description: Creates a Qlik Data Product from a Snowflake Semantic View. Registers datasets, creates a glossary with documentation, creates a data product, and links everything together.
---

## Workflow: Create Qlik Data Product from Snowflake Semantic View

Follow these steps **in order**. Do NOT skip steps.

### Step 1: Gather inputs

1. The user should provide the **fully qualified Semantic View name** (e.g. `DB.SCHEMA.MY_VIEW`). If not provided, ask for it.
2. Ask the user which **Snowflake connection name** to use in Qlik (e.g. `Snowflake:SNOWFLAKE_MONITORING_DATA`). If they don't know, use `Snowflake:SNOWFLAKE_MONITORING_DATA` as default.
3. Call `mcp__qlik-local__spaces__list` to list all available Qlik spaces.
4. Present the spaces to the user and ask them to **choose a target space** for the data product.
5. Store the chosen `spaceId`, `spaceName`, and `connectionName`.

### Step 2: Inspect the Semantic View

1. Call `get_semantic_view_ddl` with `SEMANTIC_VIEW_NAME` set to the fully qualified semantic view name.
2. Parse the returned DDL to extract:
   - All **base tables** referenced (the physical tables behind the semantic view, including their physical names with quotes if needed)
   - All **columns/measures/dimensions** defined
   - Any **descriptions** or documentation in the DDL (from `comment=` clauses)
3. For **each base table**, run a SQL query to get the actual column types:
   ```sql
   SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
   FROM <database>.INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = '<schema>' AND TABLE_NAME = '<table_name>'
   ORDER BY ORDINAL_POSITION
   ```
4. Present the list of base tables, their columns with types, and the semantic view descriptions to the user for confirmation.

### Step 3: Create Qlik Datasets (one per base table)

For **each base table** found in Step 2, call `create_qlik_dataset` with:
- **BODY**: a JSON string with:
  - `name`: the table name (e.g. `Customer_Master`)
  - `technicalName`: the fully qualified Snowflake table name (e.g. `CORTEX_DEMOS.PUBLIC.Customer_Master`)
  - `description`: description from the semantic view if available, otherwise "Table from Semantic View <name>"
  - `type`: "CONNECTION"
  - `spaceId`: the spaceId chosen in Step 1
  - `qri`: `"qdf:<connectionName>:<spaceId>:<fully_qualified_table_name>"`
  - `secureQri`: same value as `qri`
  - `dataAssetInfo`:
    - `id`: the connectionName (e.g. `"Snowflake:SNOWFLAKE_MONITORING_DATA"`)
    - `technicalName`: the connection short name (e.g. `"SNOWFLAKE_MONITORING_DATA"`)
    - `dataStoreInfo`:
      - `id`: same as dataAssetInfo.id
      - `technicalName`: same as dataAssetInfo.technicalName
  - `schema.dataFields`: array built from INFORMATION_SCHEMA.COLUMNS results. For each column:
    - `name`: COLUMN_NAME
    - `dataType.type`: mapped from Snowflake DATA_TYPE:
      - TEXT/VARCHAR/STRING/CHAR -> `STRING`
      - NUMBER with NUMERIC_SCALE=0 -> `INTEGER`
      - NUMBER with NUMERIC_SCALE>0 -> `DECIMAL` (add `properties: {precision: NUMERIC_PRECISION, scale: NUMERIC_SCALE}`)
      - FLOAT/DOUBLE/REAL -> `DOUBLE`
      - DATE -> `DATE`
      - TIME -> `TIME`
      - TIMESTAMP/TIMESTAMP_NTZ/TIMESTAMP_LTZ/TIMESTAMP_TZ -> `TIMESTAMP`
      - BOOLEAN -> `BOOLEAN`
      - BINARY/VARBINARY -> `BINARY`
      - VARIANT/OBJECT/ARRAY -> `STRING`
      - Other -> `STRING`

Collect all returned **dataset IDs** from the responses.

### Step 4: Create a Glossary with documentation

1. Call `mcp__qlik-local__glossaries__create` with:
   - `name`: "Glossary - <semantic_view_short_name>"
   - `description`: "Business glossary auto-generated from Snowflake Semantic View <semantic_view_name>"
2. Capture the `glossaryId` from the response.
3. For each **fact, dimension, and metric** from the semantic view DDL that has a `comment=` description, call `mcp__qlik-local__glossaries__create_term` with:
   - `glossaryId`: the glossary ID
   - `name`: the column/measure/metric name (use the alias if present)
   - `description`: the comment text from the DDL
4. Also create a term for the **semantic view itself** using its top-level `comment=` as description.

### Step 5: Create the Data Product and link all assets

1. Call `mcp__qlik-local__data_products__create` with:
   - `name`: "<semantic_view_short_name> Data Product"
   - `description`: "Data product from Snowflake Semantic View <semantic_view_name>. Contains <N> datasets and a business glossary."
   - `spaceId`: the spaceId from Step 1
2. Capture the `dataProductId` from the response.
3. **Link datasets to the data product**: Call `mcp__qlik__qlik_update_data_product` with:
   - `dataProductId`: the data product ID
   - `datasetsOps`: an array of `{"op": "add", "path": "/datasets/-", "value": {"id": "<dataset_id>"}}` for each dataset created in Step 3
4. **Activate the data product**: Call `mcp__qlik__qlik_update_activate_data_product` with:
   - `dataProductId`: the data product ID

### Step 6: Summary

Present a final summary:
- **Data Product**: name, ID, and status (active/draft)
- **Datasets created**: list with names and IDs, all linked to the data product
- **Glossary created**: name, ID, and number of terms created
- **Space**: name where everything was created
- **Connection**: Snowflake connection used
