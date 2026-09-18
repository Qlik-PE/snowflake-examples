---
name: create_data_product_from_sv
description: Creates a Qlik Data Product from a Snowflake Semantic View. Validates prerequisites (auto-creates data asset if needed), registers datasets, creates a glossary, creates and links the data product, and verifies the result.
---

## Workflow: Create Qlik Data Product from Snowflake Semantic View

Follow these steps **strictly in order**. Do NOT skip steps. Do NOT proceed to the next step if the current step fails -- follow the rollback instructions instead.

Track all artifacts created during this run in a list: `created_artifacts = []`. This list is used for rollback.

### Step 0: Validate prerequisites

1. The user should provide:
   - The **fully qualified Semantic View name** (e.g. `DB.SCHEMA.MY_VIEW`). If not provided, ask.
   - The **Snowflake connection ID or name** in Qlik (e.g. `fe1bdad2-5b26-466a-b648-778258586334`). If not provided, ask.

2. Call `mcp__qlik-local__spaces__list` to list available Qlik spaces. Present them and ask the user to **choose a target space**. Store `spaceId` and `spaceName`.

3. **Validate the connection exists in Qlik**: Call `mcp__qlik-local__catalog__search` with `query` set to the connection name/ID and `resourceType` set to `connection`.
   - If NOT found: **STOP**. Tell the user the Snowflake connection is not registered in Qlik Cloud.
   - If found: extract and store:
     - `connectionId`: the connection UUID
     - `connectionTechnicalName`: the `technicalName` field from the connection result
     - `connectorType`: the `dataSourceId` or `type` field (e.g. `"Snowflake"`, `"qix-snowflake"`) -- this becomes `APP_TYPE`

4. **Discover the data asset**:

   **4a. Direct search**: Call `mcp__qlik-local__catalog__search` with `query` set to the connection technical name (or connection ID) and `resourceType` set to `dataasset`.
   - If found: extract `dataAssetId`. Skip to step 5.

   **4b. Discover via existing datasets**: If 4a returned nothing, search for datasets already linked to this connection. Call `mcp__qlik-local__catalog__search` with `query` set to the connection name/ID and `resourceType` set to `dataset`.
   - If datasets are found:
     - Extract `dataAssetInfo.id` from any of them — that is the `dataAssetId`.
     - Extract the `qri` field (e.g. `qri:db:snowflake://<hash>#<hash>`). Split on `#` and store the prefix (everything before `#`) as `qriPrefix`. This is the connection-level QRI base used to build QRIs for new datasets.
     - Also extract `dataAssetInfo.technicalName` if available.

   **4c. If BOTH 4a and 4b found nothing**: **STOP**. Tell the user:
   "The Snowflake connection exists but no data asset is registered. Please onboard the connection in Qlik Data Integration first, or provide a connection that is already onboarded."

   **Rules**:
   - Do NOT use `connectionId` as `dataAssetId` — they are different Qlik objects.
   - Do NOT attempt to create a data asset automatically.
   - Do NOT proceed without a confirmed `dataAssetId`.
   - Do NOT proceed without a `qriPrefix` (needed for building dataset QRIs).

5. Store final values: `spaceId`, `spaceName`, `connectionId`, `connectionTechnicalName`, `dataAssetId`, `qriPrefix`, `semanticViewName`.

**GATE 0**: All values captured. `dataAssetId` MUST be present and MUST NOT be the same as `connectionId`. If any validation failed, STOP here.

### Step 1: Inspect the Semantic View

1. Call `get_semantic_view_ddl` with `SEMANTIC_VIEW_NAME` set to the fully qualified name.
   - If this fails (view does not exist or not authorized): **STOP**. Report the error.
2. Parse the returned DDL to extract:
   - All **base tables** (physical table names from `FROM` clauses, preserving case/quotes)
   - All **columns/measures/dimensions** defined
   - All **descriptions** from `comment=` clauses
   - All **metrics** definitions
3. For **each base table**, call `get_table_columns` with the table's `DATABASE_NAME`, `SCHEMA_NAME`, and `TABLE_NAME` (unquoted) to get actual column types with precision/scale.
   - If `get_table_columns` returns empty (table doesn't exist or no access): **STOP**. Report which table is missing.
4. **Pre-validate DECIMAL fields**: scan all columns from `get_table_columns`. For any column where `data_type` = `NUMBER` and `numeric_scale` > 0, verify that `numeric_precision` and `numeric_scale` are both non-null. If either is null, default to `precision=38, scale=0` and treat as `INTEGER`.
5. Present to the user for confirmation:
   - List of base tables with column count
   - Any columns with descriptions
   - Any DECIMAL fields with their precision/scale
   - Ask: "Proceed with creating <N> datasets?"

**GATE 1**: User confirmed. All tables resolved with column types. All DECIMAL fields have valid precision/scale.

### Step 2: Create Qlik Datasets (one per base table)

**Important**: Create ALL datasets before creating the data product. If any dataset fails, do NOT proceed.

For **each base table**, call `create_qlik_dataset` with BODY as a JSON string:

```json
{
  "name": "<table_name>",
  "technicalName": "<fully_qualified_table_name>",
  "description": "<comment from DDL or 'Table from Semantic View X'>",
  "spaceId": "<spaceId>",
  "qri": "<qriPrefix>#<table_specific_hash_or_name>",
  "secureQri": "<qriPrefix>#<table_specific_hash_or_name>",
  "createdByConnectionId": "<connectionId>",
  "dataAssetInfo": {
    "id": "<dataAssetId>",
    "dataStoreInfo": {
      "id": "<dataAssetId>"
    }
  },
  "schema": {
    "dataFields": [
      {
        "name": "<COLUMN_NAME>",
        "dataType": {
          "type": "<mapped_type>",
          "properties": {}
        },
        "primaryKey": false,
        "nullable": true
      }
    ]
  }
}
```

**CRITICAL payload rules**:
- `qri` and `secureQri`: use the `qriPrefix` discovered in Step 0.4b (e.g. `qri:db:snowflake://<hash>`) plus `#` plus the table identifier. If the existing datasets use a hash after `#`, use the fully qualified table name as the fragment (e.g. `qri:db:snowflake://<hash>#CORTEX_DEMOS.PUBLIC.Customer_Master`). Inspect the existing dataset QRIs to match the pattern.
- `dataAssetInfo` has ONLY `id` and `dataStoreInfo.id`. Do NOT add `technicalName` inside.
- `technicalName` goes at the **top level** (the fully qualified Snowflake table name).
- `createdByConnectionId` links the dataset back to the Snowflake connection.
- `dataAssetInfo.id` and `dataStoreInfo.id` MUST use the `dataAssetId` -- NEVER the `connectionId`.
- Do NOT include `type: "CONNECTION"` -- omit the `type` field or match what existing datasets use.
- For DECIMAL fields, `properties` MUST include `{"precision": N, "scale": N}`. For all other types, `properties` can be `{}`.

**DECIMAL validation rule**: Every field with `dataType.type` = `DECIMAL` MUST include `properties: {"precision": N, "scale": N}` where both values are integers > 0. If precision or scale is missing/null from `get_table_columns`, use `precision=38, scale=0` and map to `INTEGER` instead. Validate this BEFORE sending the request.

Type mapping from `get_table_columns` results:
- TEXT/VARCHAR/STRING/CHAR → `STRING`
- NUMBER with numeric_scale=0 or null → `INTEGER`
- NUMBER with numeric_scale>0 AND both precision/scale non-null → `DECIMAL` (include `properties: {precision, scale}`)
- FLOAT/DOUBLE/REAL → `DOUBLE`
- DATE → `DATE`
- TIME → `TIME`
- TIMESTAMP/TIMESTAMP_NTZ/TIMESTAMP_LTZ/TIMESTAMP_TZ → `TIMESTAMP`
- BOOLEAN → `BOOLEAN`
- BINARY/VARBINARY → `BINARY`
- VARIANT/OBJECT/ARRAY → `STRING`
- Other → `STRING`

After each call, check `status_code`:
- **200/201**: Success. Collect the dataset ID. Add `{type: "dataset", id: <id>}` to `created_artifacts`.
- **400**: Bad request. Report the error detail. Try to fix and retry once.
- **404**: Data asset not found. **STOP** -- prerequisite validation missed something.
- **Other error**: **STOP**.

**GATE 2**: ALL datasets created successfully. Collect list of `{table_name, dataset_id}`.

If ANY dataset failed and could not be retried: **ROLLBACK**.

### Step 3: Create Glossary with documentation

1. Call `mcp__qlik-local__glossaries__create` with:
   - `name`: "Glossary - <semantic_view_short_name>"
   - `description`: "Business glossary from Snowflake Semantic View <full_name>"
2. Capture `glossaryId`. Add `{type: "glossary", id: <id>}` to `created_artifacts`.
3. Create a term for the **semantic view itself** using its top-level `comment=`.
4. For each fact, dimension, and metric that has a `comment=`, call `mcp__qlik-local__glossaries__create_term` with:
   - `glossaryId`: the glossary ID
   - `name`: the alias name from the DDL
   - `description`: the comment text

**GATE 3**: Glossary created with ID. Term creation failures are non-fatal (log and continue).

### Step 4: Create Data Product and link assets

1. Call `mcp__qlik-local__data_products__create` with:
   - `name`: "<semantic_view_short_name> Data Product"
   - `description`: "Data product from Snowflake Semantic View <full_name>. Contains <N> datasets and a business glossary."
   - `spaceId`: the spaceId from Step 0
2. Capture `dataProductId`. Add `{type: "data_product", id: <id>}` to `created_artifacts`.
   - If creation fails: **STOP**. Datasets and glossary remain as standalone assets.
3. **Link datasets**: Call `mcp__qlik__qlik_update_data_product` with:
   - `dataProductId`: the data product ID
   - For each dataset: add operation `{"op": "add", "path": "/datasets/-", "value": {"id": "<dataset_id>"}}`
   - If linking fails: Report but do NOT delete the data product. User can link manually.
4. **Activate**: Call `mcp__qlik__qlik_update_activate_data_product` with `dataProductId`.
   - If activation fails: Leave as draft. Report to user.

**GATE 4**: Data product created and linked.

### Step 5: Post-execution verification

1. Call `mcp__qlik-local__data_products__get` with `dataProductId` to confirm:
   - Status (active/draft)
   - Number of linked datasets matches expected count
2. For each dataset ID, call `mcp__qlik-local__datasets__get` to confirm it exists.
3. Call `mcp__qlik-local__catalog__search` with `query=<glossary_name>` to confirm the glossary is in the catalog.

Report any discrepancies.

### Step 6: Summary

Present:
- **Data Product**: name, ID, status, URL (https://<tenant>/data-product/<id>)
- **Datasets**: table with name, ID, and status for each
- **Glossary**: name, ID, number of terms created
- **Data Asset**: ID used (discovered from catalog)
- **Space**: name
- **Connection**: ID and technical name used
- **Semantic View**: source name
- **Verification**: PASS or list of issues

### Rollback procedure

If rollback is needed at any point:

1. List all entries in `created_artifacts` (in creation order).
2. Ask user: "The workflow failed at Step X. The following artifacts were created. Delete them?"
3. If user confirms, delete in **reverse** order:
   - Data product: `mcp__qlik-local__data_products__delete`
   - Glossary: `mcp__qlik-local__catalog__delete` with the glossary item ID
   - Datasets: `mcp__qlik-local__catalog__delete` for each dataset item ID
4. Confirm deletion of each artifact.
