---
name: create_data_product_from_sv
description: Creates a Qlik Data Product from a Snowflake Semantic View. Registers datasets via the catalog-integration API, creates a glossary with documentation, creates a data product, and links everything together.
---

## Workflow: Create Qlik Data Product from Snowflake Semantic View

**MCP Server**: This skill uses the Qlik MCP server attached to this agent. All tool names below (e.g. `catalog__search`, `spaces__list`) refer to tools provided by that server. Tools `get_semantic_view_ddl`, `get_table_columns`, and `create_qlik_dataset` are stored-procedure tools registered directly on this agent.

Follow these steps **strictly in order**. Do NOT skip steps. Do NOT proceed to the next step if the current step fails -- follow the rollback instructions instead.

Track all artifacts created during this run in a list: `created_artifacts = []`. This list is used for rollback.

### Step 0: Validate prerequisites

1. The user should provide:
   - The **fully qualified Semantic View name** (e.g. `DB.SCHEMA.MY_VIEW`). If not provided, ask.
   - The **Snowflake data connection name** in Qlik Cloud (e.g. `Snowflake_PROD`). This is the name shown in Qlik Management Console > Data sources. If not provided, ask.

2. **Resolve the data connection ID**:
   - Call `catalog__search` with `query` set to the connection name provided by the user and `resourceType` set to `dataconnection`.
   - From the results, find the item whose `name` matches the user-provided connection name (case-insensitive).
   - Extract `resourceId` from the matching item — this is the `connectionId`.
   - If no match is found, report the error and list any partial matches so the user can correct the name. **STOP** until a valid connection name is provided.

3. Call `spaces__list` to list available Qlik spaces. Present them and ask the user to **choose a target space**. Store `spaceId` and `spaceName`.

4. Store final values: `spaceId`, `spaceName`, `semanticViewName`, `connectionId`.

**GATE 0**: All values captured, including a resolved `connectionId`.

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

For **each base table**, call `create_qlik_dataset` with:
- `DB`: the database name
- `SCH`: the schema name
- `TBL`: the table name
- `SPACE_ID`: the `spaceId` from Step 0
- `CONNECTION_ID`: the `connectionId` resolved in Step 0

The procedure auto-discovers columns from INFORMATION_SCHEMA, maps Snowflake types to JDBC codes, generates the selection script, and calls the Qlik catalog-integration API.

After each call, check the returned `status`:
- **201**: Success. Collect the dataset ID from `dataset_ids`. Add `{type: "dataset", id: <id>}` to `created_artifacts`.
- **400**: Bad request. Report the error detail. Try to fix and retry once.
- **Other error**: **STOP**.

**GATE 2**: ALL datasets created successfully. Collect list of `{table_name, dataset_id}`.

If ANY dataset failed and could not be retried: **ROLLBACK**.

### Step 3: Create Glossary with documentation

1. Call `glossaries__create` with:
   - `name`: "Glossary - <semantic_view_short_name>"
   - `description`: "Business glossary from Snowflake Semantic View <full_name>"
2. Capture `glossaryId`. Add `{type: "glossary", id: <id>}` to `created_artifacts`.
3. Create a term for the **semantic view itself** using its top-level `comment=`.
4. For each fact, dimension, and metric that has a `comment=`, call `glossaries__create_term` with:
   - `glossaryId`: the glossary ID
   - `name`: the alias name from the DDL
   - `description`: the comment text

**GATE 3**: Glossary created with ID. Term creation failures are non-fatal (log and continue).

### Step 4: Create Data Product and link assets

1. Call `data_products__create` with:
   - `name`: "<semantic_view_short_name> Data Product"
   - `description`: "Data product from Snowflake Semantic View <full_name>. Contains <N> datasets and a business glossary."
   - `spaceId`: the spaceId from Step 0
2. Capture `dataProductId`. Add `{type: "data_product", id: <id>}` to `created_artifacts`.
   - If creation fails: **STOP**. Datasets and glossary remain as standalone assets.
3. **Activate**: Call `data_products__activate` with:
   - `dataProductId`: the data product ID
   - `name`: the data product name (same as used in step 1)
   - If activation fails: Leave as draft. Report to user.

**GATE 4**: Data product created.

### Step 5: Update Data Product Documentation

Write comprehensive documentation into the data product description that captures the full semantic view knowledge. This makes the data product self-documenting — anyone browsing it in Qlik Cloud can understand the data model without needing access to the Snowflake semantic view.

1. Build a rich Markdown documentation string from the semantic view DDL parsed in Step 1. Include ALL of the following sections:

   ```
   ## <Data Product Name>

   **Source**: Snowflake Semantic View `<full_semantic_view_name>`
   **Created**: <timestamp>
   **Datasets**: <N> tables from `<DATABASE>.<SCHEMA>`
   **Glossary**: <glossary_name> (<term_count> terms)

   ### Data Model

   | Table | Primary Key | Description | Columns |
   |-------|-------------|-------------|---------|
   | CUSTOMER | C_CUSTKEY | <comment from SV> | 8 |
   | ORDERS | O_ORDERKEY | <comment from SV> | 9 |
   | ... | ... | ... | ... |

   ### Relationships

   | Relationship | From | To | Join Key |
   |-------------|------|-----|----------|
   | ORDERS → CUSTOMERS | ORDERS.CUSTOMERID | CUSTOMERS.CUSTOMERID | CUSTOMERID |
   | ORDER_DETAILS → ORDERS | ORDER_DETAILS.ORDERID | ORDERS.ORDERID | ORDERID |
   | ... | ... | ... | ... |

   ### Metrics

   | Metric | Expression | Description |
   |--------|-----------|-------------|
   | TOTAL_REVENUE | SUM(UNITPRICE * QUANTITY * (1 - DISCOUNT)) | Total revenue after discount |
   | ORDER_COUNT | COUNT(DISTINCT ORDERID) | Number of distinct orders |
   | ... | ... | ... |

   ### Facts

   | Fact | Table | Description |
   |------|-------|-------------|
   | FREIGHT | ORDERS | Freight/shipping charge |
   | QUANTITY | ORDER_DETAILS | Quantity ordered |
   | ... | ... | ... |

   ### Key Dimensions

   | Dimension | Table | Description |
   |-----------|-------|-------------|
   | CATEGORYNAME | CATEGORIES | Category name |
   | COMPANYNAME | CUSTOMERS | Customer company |
   | ... | ... | ... |
   ```

   Populate every section from the parsed DDL:
   - **Tables**: from the `tables (...)` section — include table name, primary key, comment, and column count.
   - **Relationships**: from the `relationships (...)` section — list every FK→PK link with the join key.
   - **Metrics**: from the `metrics (...)` section — include the expression and comment for each.
   - **Facts**: from the `facts (...)` section — include fact name, owning table, and comment.
   - **Key Dimensions**: from the `dimensions (...)` section — include a representative set (skip key columns like `*_ID` that are already in the relationships table; focus on descriptive dimensions).

2. Call `link_glossary_to_data_product` with:
   - `DATA_PRODUCT_ID`: the data product ID
   - `GLOSSARY_ID`: the glossary ID from Step 3
   This links the glossary to the data product so it appears in the Qlik Cloud UI.

3. Call `data_products__update` with:
   - `dataProductId`: the data product ID
   - `readme`: the full Markdown documentation string built above

4. Report: "Data product documentation updated with data model, relationships, metrics, facts, and dimensions. Glossary linked."

**GATE 5**: Data product documentation updated with semantic view knowledge.

### Step 6: Post-execution verification

1. Call `data_products__get` with `dataProductId` to confirm:
   - Status (active/draft)
   - Number of linked datasets matches expected count
2. For each dataset ID, call `datasets__get` to confirm it exists.
3. Call `catalog__search` with `query=<glossary_name>` to confirm the glossary is in the catalog.

Report any discrepancies.

### Step 7: Summary

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
   - Data product: `data_products__delete` with `dataProductId`
   - Glossary: `catalog__delete` with the glossary item ID
   - Datasets: `catalog__delete` for each dataset item ID
4. Confirm deletion of each artifact.
