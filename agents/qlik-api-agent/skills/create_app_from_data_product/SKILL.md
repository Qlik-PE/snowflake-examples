---
name: create_app_from_data_product
description: Creates a Qlik Sense app from an existing Qlik Data Product. Generates a load script from dataset metadata with glossary-sourced comments, creates master dimensions and measures, links the app to the glossary, builds a default analytics sheet with charts, and reloads the app.
---

## Workflow: Create Qlik Sense App from Data Product

**MCP Server**: This skill uses the Qlik MCP server attached to this agent. Tools `create_qlik_app`, `set_qlik_app_script`, `reload_qlik_app`, and `link_glossary_to_data_product` are stored-procedure tools registered directly on this agent — call them by their exact names.

**MCP Tool Name Resolution (MANDATORY before calling any MCP tool):**
The External MCP Server prepends a truncated server identifier to each tool name. The official Qlik MCP tool names (from Qlik Cloud documentation) are listed below. The actual registered names in your tool list will have a server prefix added, but end with the official name.

Before your first MCP tool call, list all available tools and build a mapping from the official names below to the actual prefixed names in your tool list. Match by **suffix**.

Official Qlik MCP tool names used by this skill:
- `qlik_search` — Search for resources (apps, datasets, data products, glossaries, spaces, etc.)
- `qlik_search_spaces` — Search for spaces
- `qlik_describe_app` — Get app metadata
- `qlik_get_data_product` — Get data product metadata
- `qlik_get_data_product_documentation` — Get data product README documentation
- `qlik_update_data_product` — Update data product properties
- `qlik_get_dataset` — Get dataset metadata
- `qlik_get_dataset_schema` — Get dataset column definitions
- `qlik_get_full_glossary_export` — Export complete glossary with all terms
- `qlik_create_glossary_term` — Create a glossary term
- `qlik_create_dimension` — Create a reusable library dimension
- `qlik_create_measure` — Create a reusable library measure
- `qlik_create_sheet` — Create a new sheet
- `qlik_add_chart` — Add a chart to a sheet
- `qlik_add_filter` — Add a filter panel to a sheet

Use the actual prefixed names in all tool calls. If a call returns "not found", re-check your tools list for the correct prefixed name.

**IMPORTANT RULES**:
- **Never create test/throwaway objects** (glossaries, apps, sheets) to probe tool names. If a tool call fails, report the error — do not create dummy objects as workarounds.
- **Always pass SPACE_ID** when creating apps. Never omit it — omitting it creates the app in personal space.
- Use stored procedure tool names exactly as listed above (e.g. `create_qlik_app`, not `apps__create`) for the stored procedure tools.

Follow these steps **strictly in order**. Do NOT skip steps. Do NOT proceed to the next step if the current step fails -- follow the rollback instructions instead.

Track all artifacts created during this run in a list: `created_artifacts = []`. This list is used for rollback.

### Step 0: Validate prerequisites and discover the data product

1. The user should provide:
   - The **data product name** (e.g. `Sales Data Product`). If not provided, ask.

2. **Resolve the Snowflake data connection**:
   - Call `qlik_search` with `query` set to `Snowflake` and `resourceType` set to `dataconnection`.
   - Filter the results to only connections with `dataSourceId` equal to `snowflake` (native Snowflake connections, not `mlgeneric`, `rest`, or `reptgt_qdisnowflake`).
   - Present the matching Snowflake connections to the user as a numbered list showing `name` and `id`.
   - Ask the user: "Which Snowflake data connection should this app use?"
   - Store the selected `connectionName`, `connectionId` (`resourceId` from the catalog item), and `connectionSpaceName` (the space name where the connection lives — from the catalog item's `space.name` field, or look up via `qlik_search_spaces` using the `spaceId`). The `connectionSpaceName` is needed for the `LIB CONNECT TO` statement.

3. **Discover the data product**:
   - Call `qlik_search` with `query` set to the data product name and `resourceType` set to `dataproduct`.
   - If multiple results match, present them with name, ID, description, and status. Ask the user to choose one.
   - If no results: **STOP**. Suggest the user check the name or create the data product first.
   - Store `dataProductId` and `dataProductName`.

4. **Get data product details**:
   - Call `qlik_get_data_product` with the `dataProductId`.
   - Extract:
     - List of linked **dataset IDs**
     - Data product `description`
     - Data product `spaceId` (the space the data product lives in)
     - Data product `readme` (the full README documentation — contains the Relationships table needed in Step 1)
   - If the data product has no linked datasets: **STOP**. Report "Data product has no datasets."

5. **Choose target space for the app (GATE — must ask the user)**:
   - Call `qlik_search_spaces` to list available Qlik spaces.
   - Present them to the user as a numbered list showing `name`, `type`, and `id`.
   - Ask: "Which space should the app be created in?"
   - **Do NOT proceed until the user answers.** This is a GATE.
   - Store `appSpaceId` and `appSpaceName`.

**GATE 0**: Data product found with at least one dataset. Connection resolved (by user selection). Target space explicitly chosen by user.

### Step 1: Inspect datasets, collect schema metadata, derive relationships, and discover the glossary

For **each dataset ID** from Step 0:

1. Call `qlik_get_dataset_schema` with the `datasetId`.
   - Extract: `tableName`, and for each column: `name`, `dataType`, `description`, `nullable`.
2. Call `qlik_get_dataset` with the `datasetId`.
   - Extract: `name` (dataset display name), `description`, `technicalName` (the Snowflake `DB.SCHEMA.TABLE` path if available).

Collect into a list: `datasets[] = {datasetId, displayName, description, tableName, schemaName, databaseName, columns[]}`.

Parse the Snowflake table reference from each dataset. If the dataset metadata includes `secureQri` or `technicalDescription`, extract the database, schema, and table name. Otherwise, infer from `tableName`.

**Derive relationships from the data product documentation:**

The data product's README (from `qlik_get_data_product` in Step 0) contains a **Relationships** table with exact FK→PK mappings. Parse that table to build the relationship map. The table format is:

```
| From Table | FK Column | → | To Table | PK Column |
|-----------|-----------|---|----------|-----------|
| CUSTOMER | C_NATIONKEY | → | NATION | N_NATIONKEY |
| ORDERS | O_CUSTKEY | → | CUSTOMER | C_CUSTKEY |
| ... | ... | → | ... | ... |
```

For each row, extract: `{fromTable, fkColumn, toTable, pkColumn}`.

If the README does not contain a Relationships table or is empty, fall back to deriving relationships from column names:
- Key columns end in `_KEY`, `_ID`, `_CODE`, or `_SK`.
- Strip the table-specific prefix (single letter + `_`) to find the base key name.
- The table named after the entity owns the PK (e.g. `N_NATIONKEY` is PK in `NATION`).
- Other tables with the same base key have FK references.

Build: `relationships[] = {fromTable, fkColumn, toTable, pkColumn}`.

Store: `relationships[]` and a derived `keyRenameMap` — a dictionary mapping `{tableName, originalColumn}` → `renamedColumn` for use in the load script (see Step 2).

**Discover the glossary early** (needed for load script comments in Step 2):
- Call `qlik_search` with `query` set to "Glossary - <dataProductName>" and `resourceType` set to `glossary`.
- Also try with just `<dataProductName>` as query if the first search returns nothing.
- If a glossary is found, call `qlik_get_full_glossary_export` with the `glossaryId` to get all terms with descriptions.
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

2. Prepend a header block at the top of the script (locale settings + connection):

   ```
   SET ThousandSep=',';
   SET DecimalSep='.';
   SET MoneyThousandSep=',';
   SET MoneyDecimalSep='.';
   SET MoneyFormat='$ ###0.00;-$ ###0.00';
   SET TimeFormat='h:mm:ss TT';
   SET DateFormat='M/D/YYYY';
   SET TimestampFormat='M/D/YYYY h:mm:ss[.fff] TT';
   SET FirstWeekDay=6;
   SET BrokenWeeks=1;
   SET ReferenceDay=0;
   SET FirstMonthOfYear=1;
   SET CollationLocale='en-US';
   SET CreateSearchIndexOnReload=0;
   SET MonthNames='Jan;Feb;Mar;Apr;May;Jun;Jul;Aug;Sep;Oct;Nov;Dec';
   SET LongMonthNames='January;February;March;April;May;June;July;August;September;October;November;December';
   SET DayNames='Mon;Tue;Wed;Thu;Fri;Sat;Sun';
   SET LongDayNames='Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday';
   SET NumericalAbbreviation='3:k;6:M;9:G;12:T;15:P;18:E;21:Z;24:Y;-3:m;-6:μ;-9:n;-12:p;-15:f;-18:a;-21:z;-24:y';

   // Data Product: <dataProductName>
   // Generated from Qlik Data Product by Snowflake Cortex Agent
   // Connection: <connectionSpaceName>:<connectionName>

   LIB CONNECT TO '<connectionSpaceName>:<connectionName>';
   ```

   **CRITICAL — LIB CONNECT rules:**
   - The format MUST be `LIB CONNECT TO '<spaceName>:<connectionName>';` — this is a fully qualified connection reference.
   - `<spaceName>` is the `connectionSpaceName` captured in Step 0 (the Qlik space name where the data connection lives).
   - `<connectionName>` is the connection name selected by the user in Step 0.
   - Do NOT use bare connection names without the space prefix — they will fail if the app is in a different space.
   - Do NOT use `lib://DataFiles/`, QRI paths, or any other format. Only `LIB CONNECT TO '<space>:<connection>';`.
   - Example: `LIB CONNECT TO 'Snowflake:Snowflake_AYFRZOA-QLIK.snowflakecomputing.com';`

3. Concatenate all blocks into a single `fullScript` string separated by blank lines.

4. **Create the app** — Call `create_qlik_app` (stored procedure tool) with:
   - `APP_NAME`: "<dataProductName> Analytics"
   - `APP_DESCRIPTION`: "Auto-generated Qlik Sense app from data product: <dataProductName>"
   - `SPACE_ID`: the `appSpaceId` from Step 0. **THIS IS MANDATORY — never omit SPACE_ID. If SPACE_ID is omitted the app lands in the personal space which is wrong.**
5. Capture `appId` from the response. Add `{type: "app", id: <appId>}` to `created_artifacts`.
   - If creation fails: **STOP**.
   - **Verify** the app was created in the correct space by checking the response. If it was created in personal space, **ROLLBACK** and retry with the correct SPACE_ID.

6. Call `set_qlik_app_script` (stored procedure tool) with:
   - `APP_ID`: the `appId`
   - `SCRIPT`: the `fullScript`
   - `VERSION_MESSAGE`: "Initial load script from data product: <dataProductName>"
   - If this fails: **ROLLBACK**.

**GATE 2**: App created with load script set (including glossary comments).

### Step 3: Reload the app

1. Call `reload_qlik_app` with the `appId`.
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
   For each dimension candidate, call `qlik_create_dimension` with:
   - `appId`: the app ID
   - `title`: the glossary term name (or column name formatted as Title Case)
   - `field`: the Qlik field name (matching the column name in the load script)
   - `description`: the glossary term description (or empty)

   Log each result. Failures are non-fatal.

4. **Create master measures**:
   For each measure candidate, call `qlik_create_measure` with:
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

1. Call `qlik_create_sheet` with:
   - `appId`: the app ID
   - `title`: "<dataProductName> Overview"
   - `description`: "Auto-generated overview sheet from data product: <dataProductName>"
2. Capture `sheetId`. Add `{type: "sheet", id: <sheetId>, appId: <appId>}` to `created_artifacts`.

3. **Add charts** using the master items from Step 4. Build a sensible default layout:

   a. **KPI tiles** (top row): For each master measure (up to 4), call `qlik_add_chart` with:
      - `appId`, `sheetId`
      - `chartType`: `kpi`
      - `title`: the measure title
      - `measures`: `[{libraryId: <measureLibraryId>}]`
      - `row`: 0, `col`: (index * 3), `colspan`: 3, `rowspan`: 3

   b. **Bar chart** (middle left): If there is at least one dimension and one measure, call `qlik_add_chart` with:
      - `chartType`: `barchart`
      - `title`: "<dimension> by <measure>"
      - `dimensions`: `[{libraryId: <firstDimensionLibraryId>}]`
      - `measures`: `[{libraryId: <firstMeasureLibraryId>}]`
      - `row`: 3, `col`: 0, `colspan`: 6, `rowspan`: 6

   c. **Line chart** (middle right): If there is a date/time dimension and a measure, call `qlik_add_chart` with:
      - `chartType`: `linechart`
      - `title`: "<measure> over time"
      - `dimensions`: `[{libraryId: <dateDimensionLibraryId>}]`
      - `measures`: `[{libraryId: <firstMeasureLibraryId>}]`
      - `row`: 3, `col`: 6, `colspan`: 6, `rowspan`: 6

   d. **Table** (bottom): Call `qlik_add_chart` with:
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

1. Call `qlik_create_glossary_term_links` to link glossary terms to the app's master items
   where term names match dimension/measure names.

2. Report: "App linked to glossary: <glossaryName>"

If no glossary exists, skip this step.

**GATE 6**: App linked to glossary (or skipped if no glossary).

### Step 7: Summary

Present:
- **App**: name, ID, space
- **Open your app**: `https://<tenant>/sense/app/<appId>` (use the Qlik tenant from the data connection URL)
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
   - App: use `qlik_search` to find the app, then delete it via the Qlik API. Deleting the app removes all sheets, master items, and the load script.
4. Confirm deletion.
