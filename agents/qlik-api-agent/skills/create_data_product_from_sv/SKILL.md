---
name: create_data_product_from_sv
description: Creates a Qlik Data Product from a Snowflake Semantic View. Registers datasets via the catalog-integration API, creates a glossary with documentation, creates a data product, and links everything together.
---

## Workflow: Create Qlik Data Product from Snowflake Semantic View

**MCP Server**: This skill uses the Qlik MCP server attached to this agent. Tools `get_semantic_view_ddl`, `get_table_columns`, and `create_qlik_dataset` are stored-procedure tools registered directly on this agent — call them by their exact names.

**MCP Tool Name Resolution (MANDATORY before calling any MCP tool):**
The External MCP Server prepends a truncated server identifier to each tool name. The official Qlik MCP tool names (from Qlik Cloud documentation) are listed below. The actual registered names in your tool list will have a server prefix added, but end with the official name.

Before your first MCP tool call, list all available tools and build a mapping from the official names below to the actual prefixed names in your tool list. Match by **suffix**.

Official Qlik MCP tool names used by this skill:
- `qlik_search` — Search for resources (apps, datasets, data products, glossaries, spaces, etc.)
- `qlik_search_spaces` — Search for spaces
- `qlik_create_glossary` — Create a new business glossary
- `qlik_create_glossary_term` — Create a new glossary term
- `qlik_get_full_glossary_export` — Export complete glossary with all terms
- `qlik_create_data_product` — Create a new data product
- `qlik_get_data_product` — Get metadata for a data product
- `qlik_update_data_product` — Update data product properties (name, description, readme, datasets)
- `qlik_delete_data_product` — Delete a data product
- `qlik_delete_glossary_term` — Delete a glossary term (used only for rollback)
- `qlik_get_dataset` — Get dataset metadata
- `qlik_get_dataset_schema` — Get dataset column definitions

Use the actual prefixed names in all tool calls. If a call returns "not found", re-check your tools list for the correct prefixed name.

Follow these steps **strictly in order**. Do NOT skip steps. Do NOT proceed to the next step if the current step fails -- follow the rollback instructions instead.

Track all artifacts created during this run in a list: `created_artifacts = []`. This list is used for rollback.

### Step 0: Validate prerequisites

1. The user should provide:
   - The **fully qualified Semantic View name** (e.g. `DB.SCHEMA.MY_VIEW`). If not provided, ask.
   - The **Snowflake data connection name** in Qlik Cloud (e.g. `Snowflake_PROD`). This is the name shown in Qlik Management Console > Data sources. If not provided, ask.

2. **Resolve the data connection ID**:
   - Call `qlik_search` with `query` set to the connection name provided by the user and `resourceType` set to `dataconnection`.
   - From the results, find the item whose `name` matches the user-provided connection name (case-insensitive).
   - Extract `resourceId` from the matching item — this is the `connectionId`.
   - If no match is found, report the error and list any partial matches so the user can correct the name. **STOP** until a valid connection name is provided.

3. Call `qlik_search_spaces` to list available Qlik spaces. Present them and ask the user to **choose a target space**. Store `spaceId` and `spaceName`.

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

1. Call `qlik_create_glossary` with:
   - `name`: "Glossary - <semantic_view_short_name>"
   - `description`: "Business glossary from Snowflake Semantic View <full_name>"
   - `spaceId`: the `spaceId` from Step 0 — **must match the data product space**
2. Capture `glossaryId`. Add `{type: "glossary", id: <id>}` to `created_artifacts`.
3. Create a term for the **semantic view itself** using its top-level `comment=`.
4. For each fact, dimension, and metric that has a `comment=`, call `qlik_create_glossary_term` with:
   - `glossaryId`: the glossary ID
   - `name`: the alias name from the DDL
   - `description`: the comment text

**GATE 3**: Glossary created with ID. Term creation failures are non-fatal (log and continue).

### Step 4: Create Data Product

1. Call `qlik_create_data_product` with:
   - `name`: "<semantic_view_short_name> Data Product"
   - `description`: "Data product from Snowflake Semantic View <full_name>. Contains <N> datasets and a business glossary."
   - `spaceId`: the spaceId from Step 0
   - If the tool's input schema accepts the datasets directly (e.g. a `datasetIds` / `datasets` parameter), pass the dataset IDs from GATE 2 here.
2. Capture `dataProductId`. Add `{type: "data_product", id: <id>}` to `created_artifacts`.
   - If creation fails: **STOP**. Datasets and glossary remain as standalone assets.
3. **Attach the datasets** (skip only if they were already passed in step 1): call `qlik_update_data_product` with `dataProductId` and the list of dataset IDs from GATE 2. Check the tool's input schema for the exact parameter name.
4. Call `qlik_get_data_product` and confirm that the number of linked datasets equals the number created in Step 2. If it doesn't, retry step 3 once; if it still doesn't match, report the missing dataset IDs and **ROLLBACK**.

**IMPORTANT: Do NOT activate the data product. Leave it in draft.**

**GATE 4**: Data product created (in draft), with every dataset from Step 2 attached.

### Step 5: Set documentation, link glossary

**This step is MANDATORY — do not skip it.**

1. Build the full README Markdown string from the semantic view DDL parsed in Step 1.
   Include ALL of the following sections:

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

   **MANDATORY FORMAT — use this exact Markdown table. Do NOT use bullet points or prose.**

   Parse each line from the DDL `relationships (...)` block.
   DDL format: `TABLE_A(FK_COL) references TABLE_B(PK_COL)`
   Output format: one table row per line.

   | From Table | FK Column | → | To Table | PK Column |
   |-----------|-----------|---|----------|-----------|
   | CUSTOMER | C_NATIONKEY | → | NATION | N_NATIONKEY |
   | ORDERS | O_CUSTKEY | → | CUSTOMER | C_CUSTKEY |
   | LINEITEM | L_ORDERKEY | → | ORDERS | O_ORDERKEY |
   | NATION | N_REGIONKEY | → | REGION | R_REGIONKEY |
   | PARTSUPP | PS_PARTKEY | → | PART | P_PARTKEY |
   | PARTSUPP | PS_SUPPKEY | → | SUPPLIER | S_SUPPKEY |
   | SUPPLIER | S_NATIONKEY | → | NATION | N_NATIONKEY |

   ^^^ Example for TPCH — replace with actual DDL relationships.
   Include ALL relationships. One row per FK→PK column pair. No prose summaries.
   Composite keys: write one row per column pair, in order, with the same From/To tables
   (e.g. `LINEITEM(L_PARTKEY, L_SUPPKEY) references PARTSUPP(PS_PARTKEY, PS_SUPPKEY)` becomes
   `LINEITEM | L_PARTKEY | → | PARTSUPP | PS_PARTKEY` and `LINEITEM | L_SUPPKEY | → | PARTSUPP | PS_SUPPKEY`).
   The create_app_from_data_product skill regroups these rows into one composite link.

   ### Metrics

   | Metric | Expression | Description |
   |--------|-----------|-------------|
   | TOTAL_REVENUE | SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)) | Total revenue after discount |
   | ORDER_COUNT | COUNT(O_ORDERKEY) | Number of distinct orders |
   | ... | ... | ... |

   ### Facts

   | Fact | Table | Description |
   |------|-------|-------------|
   | L_EXTENDEDPRICE | LINEITEM | Extended price before discounts |
   | O_TOTALPRICE | ORDERS | Total price of the order |
   | ... | ... | ... |

   ### Key Dimensions

   | Dimension | Table | Description |
   |-----------|-------|-------------|
   | C_MKTSEGMENT | CUSTOMER | Market segment |
   | R_NAME | REGION | Region name |
   | ... | ... | ... |
   ```

   Populate every section from the parsed DDL:
   - **Tables**: from the `tables (...)` section — include table name, primary key, comment, and column count.
   - **Relationships**: from the `relationships (...)` section — one row per FK→PK mapping using the **exact column names** from the DDL (e.g. `ORDERS(O_CUSTKEY) references CUSTOMER(C_CUSTKEY)` becomes `ORDERS | O_CUSTKEY | → | CUSTOMER | C_CUSTKEY`). Include every relationship. Do NOT summarize in prose.
   - **Metrics**: from the `metrics (...)` section — include the **exact expression** and comment for each.
   - **Facts**: from the `facts (...)` section — include fact name, owning table, and comment.
   - **Key Dimensions**: from the `dimensions (...)` section — include a representative set (skip key columns like `*_KEY` that are already in the relationships table; focus on descriptive dimensions).

2. Call `qlik_update_data_product` with:
   - `dataProductId`: the data product ID from Step 4
   - `readme`: the full Markdown documentation string built above

3. Call `link_glossary_to_data_product` with:
   - `DATA_PRODUCT_ID`: the data product ID
   - `GLOSSARY_ID`: the glossary ID from Step 3
   (This stored procedure uses the PATCH API to link the glossary.)

4. Report: "Data product documentation set and glossary linked."

**GATE 5**: Data product has README documentation and glossary linked.

### Step 6: Post-execution verification

1. Call `qlik_get_data_product` with `dataProductId` to confirm:
   - Status (active/draft)
   - Number of linked datasets matches expected count
2. For each dataset ID, call `qlik_get_dataset` to confirm it exists.
3. Call `qlik_search` with `query=<glossary_name>` to confirm the glossary is in the catalog.

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
   - Data product: `qlik_delete_data_product` with `dataProductId`
   - Glossary: call `qlik_delete_glossary_term` for each term created. No available tool deletes the glossary itself, so report its ID and name for manual deletion in Qlik Cloud.
   - Datasets: no available tool deletes datasets, so report their IDs for manual cleanup in the Qlik Cloud catalog.
4. Confirm deletion of each artifact.
