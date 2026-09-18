---
name: create_data_product_from_sv
description: Creates a Qlik Data Product from a Snowflake Semantic View. Registers datasets via the catalog-integration API (V2), creates a glossary with documentation, creates a data product, and links everything together.
---

## Workflow: Create Qlik Data Product from Snowflake Semantic View

Follow these steps **strictly in order**. Do NOT skip steps. Do NOT proceed to the next step if the current step fails -- follow the rollback instructions instead.

Track all artifacts created during this run in a list: `created_artifacts = []`. This list is used for rollback.

### Step 0: Validate prerequisites

1. The user should provide:
   - The **fully qualified Semantic View name** (e.g. `DB.SCHEMA.MY_VIEW`). If not provided, ask.

2. Call `mcp__qlik-local__spaces__list` to list available Qlik spaces. Present them and ask the user to **choose a target space**. Store `spaceId` and `spaceName`.

3. Store final values: `spaceId`, `spaceName`, `semanticViewName`.

**GATE 0**: All values captured.

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
4. Present to the user for confirmation:
   - List of base tables with column count
   - Any columns with descriptions
   - Ask: "Proceed with creating <N> datasets?"

**GATE 1**: User confirmed. All tables resolved with column types.

### Step 2: Create Qlik Datasets (one per base table)

**Important**: Create ALL datasets before creating the data product. If any dataset fails, do NOT proceed.

For **each base table**, call `create_qlik_dataset_v2` with:
- `DB`: the database name
- `SCH`: the schema name
- `TBL`: the table name
- `SPACE_ID`: the `spaceId` from Step 0

The procedure auto-discovers columns from INFORMATION_SCHEMA, maps Snowflake types to JDBC codes, generates the selection script, and calls the Qlik catalog-integration API.

After each call, check the returned `status`:
- **201**: Success. Collect the dataset ID from `dataset_ids`. Add `{type: "dataset", id: <id>}` to `created_artifacts`.
- **400**: Bad request. Report the error detail. Try to fix and retry once.
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
- **Space**: name
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
