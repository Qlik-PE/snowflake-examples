---
name: create_app_from_data_product
description: Creates a Qlik Sense app from an existing Qlik Data Product. Generates a load script from dataset metadata with glossary-sourced comments, creates master dimensions and measures, links the app to the glossary, builds a default analytics sheet with charts, and reloads the app.
---

## Workflow: Create Qlik Sense App from Data Product

**MCP Server**: This skill uses the Qlik MCP server attached to this agent. All tool names below (e.g. `catalog__search`, `apps__create`) refer to tools provided by that server. Tools `get_semantic_view_ddl`, `get_table_columns`, and `create_qlik_dataset` are stored-procedure tools registered directly on this agent.

Follow these steps **strictly in order**. Do NOT skip steps. Do NOT proceed to the next step if the current step fails -- follow the rollback instructions instead.

Track all artifacts created during this run in a list: `created_artifacts = []`. This list is used for rollback.

### Step 0: Validate prerequisites and discover the data product

1. The user should provide:
   - The **data product name** (e.g. `Sales Data Product`). If not provided, ask.

2. **Resolve the Snowflake data connection**:
   - Call `catalog__search` with `query` set to `Snowflake` and `resourceType` set to `dataconnection`.
   - Filter the results to only connections with `dataSourceId` equal to `snowflake` (native Snowflake connections, not `mlgeneric`, `rest`, or `reptgt_qdisnowflake`).
   - Present the matching Snowflake connections to the user as a numbered list showing `name` and `id`.
   - Ask the user: "Which Snowflake data connection should this app use?"
   - Store the selected `connectionName`, `connectionId` (`resourceId` from the catalog item), and `connectionSpaceName` (the space name where the connection lives — from the catalog item's `space.name` field, or look up via `spaces__get` using the `spaceId`). The `connectionSpaceName` is needed for the `LIB CONNECT TO` statement.

3. **Discover the data product**:
   - Call `catalog__search` with `query` set to the data product name and `resourceType` set to `dataproduct`.
   - If multiple results match, present them with name, ID, description, and status. Ask the user to choose one.
   - If no results: **STOP**. Suggest the user check the name or create the data product first.
   - Store `dataProductId` and `dataProductName`.

4. **Get data product details**:
   - Call `data_products__get` with the `dataProductId`.
   - Extract:
     - List of linked **dataset IDs**
     - Data product `description`
     - Data product `spaceId` (the space the data product lives in)
   - If the data product has no linked datasets: **STOP**. Report "Data product has no datasets."

5. **Choose target space for the app**:
   - Call `spaces__list` to list all available Qlik spaces.
   - Present the spaces to the user as a numbered list showing `name`, `type` (shared/managed/data), and `id`.
   - Identify the data product's space from Step 4 and mark it as `(data product space)` in the list.
   - Ask the user: "Where should the app be created? Choose a space, or select the data product's space (`<spaceName>`)."
   - If the user says "same space" or doesn't specify, use the data product's `spaceId`.
   - Store `appSpaceId` and `appSpaceName`.

6. Store final values: `dataProductId`, `dataProductName`, `connectionId`, `connectionName`, `connectionSpaceName`, `appSpaceId`, `appSpaceName`, `datasetIds[]`.

**GATE 0**: Data product found with at least one dataset. Connection resolved (by user selection). Target space explicitly chosen by user.

### Step 1: Inspect datasets, collect schema metadata, derive relationships, and discover the glossary

For **each dataset ID** from Step 0:

1. Call `datasets__get_schema` with the `datasetId`.
   - Extract: `tableName`, and for each column: `name`, `dataType`, `description`, `nullable`.
2. Call `datasets__get` with the `datasetId`.
   - Extract: `name` (dataset display name), `description`, `technicalName` (the Snowflake `DB.SCHEMA.TABLE` path if available).

Collect into a list: `datasets[] = {datasetId, displayName, description, tableName, schemaName, databaseName, columns[]}`.

Parse the Snowflake table reference from each dataset. If the dataset metadata includes `secureQri` or `technicalDescription`, extract the database, schema, and table name. Otherwise, infer from `tableName`.

**Derive relationships between tables:**

Analyze all datasets to identify key columns and build a relationship map. Key columns are columns whose name ends in `_KEY`, `_ID`, `_CODE`, or `_SK`, or whose description mentions "primary key", "foreign key", "references", or "links to".

For each key column found across all datasets:
1. **Identify the primary table**: The table where the column is a primary key (unique identifier). This is typically the table named after the entity (e.g. `N_NATIONKEY` is the PK in the `NATION` table, `C_CUSTKEY` is the PK in `CUSTOMER`).
2. **Identify foreign key references**: Other tables that contain the same key column name. These are FK references (e.g. `SUPPLIER` has `S_NATIONKEY` which references `N_NATIONKEY` in `NATION`).
3. **Build a relationship map**: `relationships[] = {keyName, primaryTable, primaryColumn, foreignTable, foreignColumn}`.

Matching rules for key columns across tables:
- **Exact match**: Same column name in multiple tables (e.g. `L_ORDERKEY` in LINEITEM → `O_ORDERKEY` in ORDERS). Strip the table-specific prefix (single letter + `_`) to find the base key name.
- **Prefix pattern**: Columns like `<PREFIX>_<KEYNAME>` where `<KEYNAME>` matches across tables. For example, `N_NATIONKEY`, `S_NATIONKEY`, `C_NATIONKEY` all share the base key `NATIONKEY` — the `NATION` table owns it (prefix `N_`), others reference it.
- **Description-based**: If a column's description says "references <TABLE>" or "foreign key to <TABLE>", use that.

Store: `relationships[]` and a derived `keyRenameMap` — a dictionary mapping `{tableName, originalColumn}` → `renamedColumn` for use in the load script (see Step 2).

**Discover the glossary early** (needed for load script comments in Step 2):
- Call `catalog__search` with `query` set to "Glossary - <dataProductName>" and `resourceType` set to `glossary`.
- Also try with just `<dataProductName>` as query if the first search returns nothing.
- If a glossary is found, call `glossaries__export` with the `glossaryId` to get all terms with descriptions.
- Store `glossaryId`, `glossaryName`, and `glossaryTerms[]` (list of `{name, description}`).
- If no glossary is found, store `glossaryId = null`.

Present to the user:
- Table of datasets: display name, Snowflake table, column count
- Discovered relationships: table showing FK → PK links
- Glossary status: found (with term count) or not found
- Ask: "Proceed with creating app from these <N> datasets?"

**GATE 1**: User confirmed. All datasets resolved with column metadata. Relationships derived. Glossary discovered (or confirmed absent).

### Step 2: Build and set the load script

**Key field renaming strategy**: Qlik's associative engine links tables automatically when they share identically named fields. To establish relationships, rename foreign key columns in each table's LOAD statement so that:
- The **primary key column** in its owning table keeps a clean canonical name (e.g. `NATIONKEY`).
- **Foreign key columns** in referencing tables are renamed (via `AS`) to the same canonical name (e.g. `S_NATIONKEY AS NATIONKEY`).
- This creates automatic associations in Qlik without explicit JOIN statements.

Build the `keyRenameMap` from the relationships discovered in Step 1:
- For each relationship, the canonical key name is the base key (e.g. `NATIONKEY` from `N_NATIONKEY`).
- In the primary table: rename `<PREFIX>_<KEY>` → `<KEY>` (e.g. `N_NATIONKEY` AS `NATIONKEY` in NATION).
- In foreign tables: rename `<PREFIX>_<KEY>` → `<KEY>` (e.g. `S_NATIONKEY` AS `NATIONKEY` in SUPPLIER).
- Non-key columns keep their original names.

1. For each dataset, generate a Qlik load script block. **Include glossary-sourced comments** and **apply key renames**:

   ```
   // === <DATASET_DISPLAY_NAME> ===
   // <dataset description from data product>
   // Source: <DATABASE>.<SCHEMA>.<TABLE>
   // Relationships: <list of FK→PK links for this table>
   [<TABLE>]:
   LOAD
       "<ORIG_COL1>" AS "<RENAMED_COL1>",    // <comment> (PK/FK → <linked table>)
       "<ORIG_COL2>" AS "<RENAMED_COL2>",    // <comment> (FK → <linked table>)
       "<COL3>",                              // <comment> (no rename needed)
       ...
       "<COLn>";
   SQL SELECT
       "<ORIG_COL1>",
       "<ORIG_COL2>",
       "<COL3>",
       ...
       "<COLn>"
   FROM "<DATABASE>"."<SCHEMA>"."<TABLE>";
   ```

   Renaming rules:
   - If a column is in the `keyRenameMap` for this table, use `"<original>" AS "<canonical>"` in the LOAD section.
   - If a column is NOT a key, keep it as-is: `"<column>"`.
   - The SQL SELECT section always uses the **original** column names (no rename — that's the physical table).
   - Add a comment suffix for renamed keys: `// PK - links SUPPLIER, CUSTOMER` or `// FK → NATION`.

   Comment matching rules:
   - For each column, first check if a glossary term exists whose `name` matches the column name (case-insensitive). If yes, use the glossary term's `description` as the inline comment.
   - If no glossary term matches, check if the dataset schema has a `description` for that column. If yes, use that.
   - If neither exists, omit the comment for that column.
   - Keep comments concise (truncate to 80 characters if longer, append `...`).

2. Prepend a connection block at the top of the script:

   ```
   // Data Product: <dataProductName>
   // Generated from Qlik Data Product by Snowflake Cortex Agent
   // Connection: <spaceName>:<connectionName>

   LIB CONNECT TO '<spaceName>:<connectionName>';
   ```

   The LIB CONNECT format is `<spaceName>:<connectionName>` where `<spaceName>` is the name of the Qlik space that owns the data connection, and `<connectionName>` is the connection name selected by the user in Step 0. To find the space name for the connection, use the `spaceId` from the connection's catalog item (returned in Step 0) and look it up in the spaces list, or use the space name from the catalog result directly.

3. Concatenate all blocks into a single `fullScript` string separated by blank lines.

4. Call `apps__create` with:
   - `name`: "<dataProductName> Analytics"
   - `description`: "Auto-generated Qlik Sense app from data product: <dataProductName>"
   - `spaceId`: the `appSpaceId` from Step 0
5. Capture `appId` from the response. Add `{type: "app", id: <appId>}` to `created_artifacts`.
   - If creation fails: **STOP**.

6. Call `apps__set_script` with:
   - `appId`: the app ID
   - `script`: the `fullScript`
   - `reload`: `false` (we will reload separately in Step 3)
   - If this fails: **ROLLBACK**.

**GATE 2**: App created with load script set (including glossary comments).

### Step 3: Reload the app

1. Call `apps__reload` with the `appId`.
   - This triggers a full data reload from Snowflake into the Qlik app.
   - If the reload fails: Report the error with details. The app still exists with the script set.
     Common causes: expired Snowflake connection credentials, table permissions, connection name mismatch.
     Do NOT rollback — the app is still useful. The user can fix the connection and reload manually.

2. Wait for reload confirmation. Report: "App reloaded successfully. <N> tables loaded."

**GATE 3**: App reloaded with data. If reload failed, continue to Step 4 anyway (master items and sheets can still be created — they will populate once the app is reloaded).

### Step 4: Create master dimensions and measures

**Use the glossary terms discovered in Step 1 to create governed master items:**

1. If `glossaryTerms[]` is available (glossary was found in Step 1):
   - Classify each term:
     - Terms whose description or name references a numeric aggregation (sum, count, avg, min, max) or contains keywords like "revenue", "total", "amount", "rate", "count" → candidate **measures**.
     - All other terms → candidate **dimensions**.
   - If no glossary was found, fall back to schema-based classification (see below).

2. **Schema-based fallback** (used when no glossary exists, or to supplement glossary terms):
   - From the dataset columns collected in Step 1:
     - Columns with string/categorical types (VARCHAR, CHAR) and low implied cardinality (names ending in `_TYPE`, `_STATUS`, `_CATEGORY`, `_CODE`, `_NAME`, `_REGION`, `_SEGMENT`) → **dimensions**.
     - Columns with numeric types (NUMBER, FLOAT, DECIMAL, INTEGER) and names suggesting measures (`AMOUNT`, `PRICE`, `QTY`, `QUANTITY`, `REVENUE`, `COST`, `TOTAL`, `COUNT`, `BALANCE`) → **measures** (default aggregation: `Sum()`).
     - Date/timestamp columns → **dimensions** (with `=$(Year([field]))` and `=$(Month([field]))` derived dimensions).
     - Key columns (`*_ID`, `*_KEY`) → skip (not useful as master items).

3. **Create master dimensions**:
   For each dimension candidate, call `dimensions__create` with:
   - `appId`: the app ID
   - `title`: the glossary term name (or column name formatted as Title Case)
   - `field`: the Qlik field name (matching the column name in the load script)
   - `description`: the glossary term description (or empty)

   Log each result. Failures are non-fatal.

4. **Create master measures**:
   For each measure candidate, call `measures__create` with:
   - `appId`: the app ID
   - `title`: the glossary term name (or column name formatted as Title Case)
   - `expression`: the aggregation expression (e.g. `Sum([REVENUE])`, `Count([ORDER_ID])`)
     - If the glossary term includes an expression or formula, use that.
     - Otherwise, default to `Sum([<field>])` for amounts/totals, `Count([<field>])` for counts, `Avg([<field>])` for rates/averages.
   - `description`: the glossary term description (or empty)
   - `label`: short label for the measure (optional)

   Log each result. Failures are non-fatal.

5. Present summary: dimensions created, measures created, any failures.

**GATE 4**: Master items created. Failures are non-fatal — continue to Step 5.

### Step 5: Create default analytics sheet

1. Call `sheets__create` with:
   - `appId`: the app ID
   - `title`: "<dataProductName> Overview"
   - `description`: "Auto-generated overview sheet from data product: <dataProductName>"
2. Capture `sheetId`. Add `{type: "sheet", id: <sheetId>, appId: <appId>}` to `created_artifacts`.

3. **Add charts** using the master items from Step 4. Build a sensible default layout:

   a. **KPI tiles** (top row): For each master measure (up to 4), call `charts__add` with:
      - `appId`, `sheetId`
      - `chartType`: `kpi`
      - `title`: the measure title
      - `measures`: `[{libraryId: <measureLibraryId>}]`
      - `row`: 0, `col`: (index * 3), `colspan`: 3, `rowspan`: 3

   b. **Bar chart** (middle left): If there is at least one dimension and one measure, call `charts__add` with:
      - `chartType`: `barchart`
      - `title`: "<dimension> by <measure>"
      - `dimensions`: `[{libraryId: <firstDimensionLibraryId>}]`
      - `measures`: `[{libraryId: <firstMeasureLibraryId>}]`
      - `row`: 3, `col`: 0, `colspan`: 6, `rowspan`: 6

   c. **Line chart** (middle right): If there is a date/time dimension and a measure, call `charts__add` with:
      - `chartType`: `linechart`
      - `title`: "<measure> over time"
      - `dimensions`: `[{libraryId: <dateDimensionLibraryId>}]`
      - `measures`: `[{libraryId: <firstMeasureLibraryId>}]`
      - `row`: 3, `col`: 6, `colspan`: 6, `rowspan`: 6

   d. **Table** (bottom): Call `charts__add` with:
      - `chartType`: `table`
      - `title`: "Detail View"
      - `dimensions`: all dimension libraryIds (up to 5)
      - `measures`: all measure libraryIds (up to 3)
      - `row`: 9, `col`: 0, `colspan`: 12, `rowspan`: 6

   Chart creation failures are non-fatal — log and continue.

4. If no master items were created in Step 4 (no glossary, no classifiable columns), create a single **table** visualization using raw field names from the first dataset (use `field` in dimensions/measures instead of `libraryId`).

**GATE 5**: Sheet created with visualizations.

### Step 6: Link the app to the glossary

If a glossary was found in Step 1 (`glossaryId` is not null):

1. Call `catalog__search` with `query` set to the app name ("<dataProductName> Analytics") and `resourceType` set to `app`.
   - Find the catalog `itemId` for the newly created app.

2. Call `catalog__update` with:
   - `itemId`: the app's catalog item ID
   - `description`: append to the existing description: "\n\nLinked glossary: <glossaryName> (ID: <glossaryId>). Business definitions for fields and measures are sourced from this glossary."

3. Report: "App linked to glossary: <glossaryName>"

If no glossary exists, skip this step.

**GATE 6**: App linked to glossary (or skipped if no glossary).

### Step 7: Summary

Present:
- **App**: name, ID, space
- **Open your app**: `https://partner-engineering-saas.us.qlikcloud.com/sense/app/<appId>` (clickable link)
- **Data Product**: source name, ID
- **Connection**: name used in load script
- **Load Script**: number of tables, whether glossary comments were included
- **Reload Status**: success or failure details
- **Glossary**: linked (name, ID, term count) or not found
- **Master Dimensions**: count created, list with names
- **Master Measures**: count created, list with names and expressions
- **Sheet**: name, chart count, chart types
- **Artifacts Created**: full list for reference

IMPORTANT: Always include the clickable app URL prominently at the top of the summary so the user can open the app immediately.

### Rollback procedure

If rollback is needed at any point:

1. List all entries in `created_artifacts` (in creation order).
2. Ask user: "The workflow failed at Step X. The following artifacts were created. Delete them?"
3. If user confirms, delete in **reverse** order:
   - App: `apps__delete` with the `appId`. This removes all sheets, master items, and the load script in one operation.
4. Confirm deletion.
