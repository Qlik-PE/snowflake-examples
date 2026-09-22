-- =============================================================================
-- Qlik API Agent - Setup Script
-- Creates a Cortex Agent that interacts with Qlik Cloud REST API
-- =============================================================================
-- Prerequisites:
--   - ACCOUNTADMIN role (for EAI and integrations)
--   - A Qlik Cloud tenant with a valid API key
--   - An existing EXTERNAL MCP SERVER for Qlik Cloud (optional but recommended)
--   - Replace <QLIK_TENANT> with your tenant hostname
--   - Replace <QLIK_API_KEY> with your Qlik API key
--   - Replace <QLIK_MCP_SERVER> with your External MCP Server FQN (or NULL to skip)
-- =============================================================================

-- >>> CONFIGURE THESE VARIABLES BEFORE RUNNING <<<
SET QLIK_TENANT = '<your-tenant>.us.qlikcloud.com';           -- Qlik Cloud tenant hostname
SET TARGET_DB = '<your-database>';                             -- Database to create objects in
SET TARGET_SCHEMA = 'PUBLIC';                                  -- Schema to create objects in
SET WAREHOUSE = '<your-warehouse>';                            -- Warehouse for procedure execution
SET QLIK_MCP_SERVER = '<db>.<schema>.<mcp_server_name>';       -- FQN of existing EXTERNAL MCP SERVER

USE ROLE ACCOUNTADMIN;
USE DATABASE IDENTIFIER($TARGET_DB);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

-- =============================================================================
-- 1. Network Rule - Egress to Qlik Cloud
-- =============================================================================
CREATE OR REPLACE NETWORK RULE QLIK_CLOUD_NETWORK_RULE
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ($QLIK_TENANT);

-- =============================================================================
-- 2. Secrets - Qlik API Key and Tenant
-- =============================================================================
CREATE OR REPLACE SECRET QLIK_API_KEY_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = '<QLIK_API_KEY>';  -- Replace with your actual API key

CREATE OR REPLACE SECRET QLIK_TENANT_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = $QLIK_TENANT;

-- =============================================================================
-- 3. External Access Integration
-- =============================================================================
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION QLIK_CLOUD_EAI
  ALLOWED_NETWORK_RULES = (QLIK_CLOUD_NETWORK_RULE)
  ALLOWED_AUTHENTICATION_SECRETS = (QLIK_API_KEY_SECRET, QLIK_TENANT_SECRET)
  ENABLED = TRUE;

-- =============================================================================
-- 4. Stored Procedures
-- =============================================================================

-- 4a. Create Qlik App (POST /api/v1/apps)
CREATE OR REPLACE PROCEDURE CREATE_QLIK_APP(
  APP_NAME VARCHAR,
  SPACE_ID VARCHAR,
  APP_DESCRIPTION VARCHAR DEFAULT ''
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'create_app'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET, 'qlik_tenant' = QLIK_TENANT_SECRET)
AS
$$
import _snowflake
import requests

def create_app(session, app_name, space_id, app_description=''):
    if not space_id or space_id.strip() == '':
        return {'status_code': 400, 'response': 'SPACE_ID is required. Without it the app is created in personal space.'}
    space_id = space_id.strip()
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    tenant = _snowflake.get_generic_secret_string('qlik_tenant')
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}

    attributes = {'name': app_name, 'spaceId': space_id}
    if app_description:
        attributes['description'] = app_description
    body = {'attributes': attributes}
    resp = requests.post(f'https://{tenant}/api/v1/apps', headers=headers, json=body)
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text}
$$;

-- 4b. Set Qlik App Script (POST /api/v1/apps/{appId}/scripts)
CREATE OR REPLACE PROCEDURE SET_QLIK_APP_SCRIPT(
  APP_ID VARCHAR,
  SCRIPT VARCHAR,
  VERSION_MESSAGE VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'set_script'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET, 'qlik_tenant' = QLIK_TENANT_SECRET)
AS
$$
import _snowflake
import requests

def set_script(session, app_id, script, version_message=None):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    tenant = _snowflake.get_generic_secret_string('qlik_tenant')
    url = f'https://{tenant}/api/v1/apps/{app_id}/scripts'
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    body = {'script': script}
    if version_message:
        body['versionMessage'] = version_message
    resp = requests.post(url, headers=headers, json=body)
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text if resp.text else 'No response body'}
$$;

-- 4d. Get Semantic View DDL
CREATE OR REPLACE PROCEDURE GET_SEMANTIC_VIEW_DDL(
  SEMANTIC_VIEW_NAME VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
AS
BEGIN
  LET ddl VARCHAR;
  SELECT GET_DDL('SEMANTIC VIEW', :SEMANTIC_VIEW_NAME) INTO :ddl;
  RETURN OBJECT_CONSTRUCT('ddl', :ddl);
END;

-- 4e. Get Table Columns (INFORMATION_SCHEMA.COLUMNS)
CREATE OR REPLACE PROCEDURE GET_TABLE_COLUMNS(
  DATABASE_NAME VARCHAR,
  SCHEMA_NAME VARCHAR,
  TABLE_NAME VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'get_columns'
PACKAGES = ('snowflake-snowpark-python')
AS
$$
def get_columns(session, database_name, schema_name, table_name):
    query = f"""
        SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
        FROM {database_name}.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = '{schema_name}' AND TABLE_NAME = '{table_name}'
        ORDER BY ORDINAL_POSITION
    """
    rows = session.sql(query).collect()
    return [
        {
            'column_name': r['COLUMN_NAME'],
            'data_type': r['DATA_TYPE'],
            'numeric_precision': r['NUMERIC_PRECISION'],
            'numeric_scale': r['NUMERIC_SCALE']
        }
        for r in rows
    ]
$$;

-- 4b. Create Qlik Dataset (catalog-integration API)
-- Uses the internal create-hierarchy-for-connected-datasets endpoint
-- that the Qlik UI uses. Auto-discovers table metadata from INFORMATION_SCHEMA
-- and creates the dataset in a single call (no QRI/dataAsset discovery needed).
CREATE OR REPLACE PROCEDURE CREATE_QLIK_DATASET(
    DB VARCHAR, SCH VARCHAR, TBL VARCHAR,
    SPACE_ID VARCHAR DEFAULT NULL,
    CONNECTION_ID VARCHAR DEFAULT NULL,
    SF_ROLE VARCHAR DEFAULT 'QLIK_DATA_PRODUCT'
)
  RETURNS VARIANT
  LANGUAGE PYTHON
  RUNTIME_VERSION='3.10'
  EXTERNAL_ACCESS_INTEGRATIONS=(QLIK_CLOUD_EAI)
  PACKAGES=('snowflake-snowpark-python', 'requests')
  SECRETS=('qlik_api_key' = QLIK_API_KEY_SECRET, 'qlik_tenant' = QLIK_TENANT_SECRET)
  HANDLER = 'run'
AS
$$
import _snowflake, requests, json

# Snowflake type -> (JDBC dataType code, native type name)
TYPE_MAP = {
    'NUMBER':       (3,  'DECIMAL'),
    'DECIMAL':      (3,  'DECIMAL'),
    'NUMERIC':      (3,  'DECIMAL'),
    'INT':          (3,  'DECIMAL'),
    'INTEGER':      (3,  'DECIMAL'),
    'BIGINT':       (3,  'DECIMAL'),
    'SMALLINT':     (3,  'DECIMAL'),
    'TINYINT':      (3,  'DECIMAL'),
    'BYTEINT':      (3,  'DECIMAL'),
    'FLOAT':        (8,  'DOUBLE'),
    'FLOAT4':       (8,  'DOUBLE'),
    'FLOAT8':       (8,  'DOUBLE'),
    'DOUBLE':       (8,  'DOUBLE'),
    'DOUBLE PRECISION': (8, 'DOUBLE'),
    'REAL':         (8,  'DOUBLE'),
    'VARCHAR':      (12, 'VARCHAR'),
    'TEXT':         (12, 'VARCHAR'),
    'STRING':       (12, 'VARCHAR'),
    'CHAR':         (12, 'VARCHAR'),
    'CHARACTER':    (12, 'VARCHAR'),
    'BOOLEAN':      (16, 'BOOLEAN'),
    'DATE':         (91, 'DATE'),
    'TIMESTAMP_NTZ':(93, 'TIMESTAMP'),
    'TIMESTAMP_LTZ':(93, 'TIMESTAMP'),
    'TIMESTAMP_TZ': (93, 'TIMESTAMP'),
    'TIME':         (92, 'TIME'),
    'BINARY':       (-2, 'BINARY'),
    'VARBINARY':    (-2, 'BINARY'),
    'VARIANT':      (12, 'VARCHAR'),
    'OBJECT':       (12, 'VARCHAR'),
    'ARRAY':        (12, 'VARCHAR'),
}

def run(session, db, sch, tbl, space_id, connection_id, sf_role):
    rows = session.sql(f"""
        SELECT COLUMN_NAME, ORDINAL_POSITION, DATA_TYPE, IS_NULLABLE,
               COALESCE(NUMERIC_PRECISION, 0) AS PREC,
               COALESCE(NUMERIC_SCALE, 0) AS SCALE,
               COALESCE(CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, 38) AS SIZE
        FROM {db}.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = '{sch}' AND TABLE_NAME = '{tbl}'
        ORDER BY ORDINAL_POSITION
    """).collect()

    if not rows:
        return {"error": f"No columns found for {db}.{sch}.{tbl}"}

    fields = []
    select_cols = []
    for r in rows:
        col = r['COLUMN_NAME']
        dt = r['DATA_TYPE'].upper()
        jdbc_code, native = TYPE_MAP.get(dt, (12, 'VARCHAR'))
        nullable = 1 if r['IS_NULLABLE'] == 'YES' else 0
        size = int(r['SIZE']) if r['SIZE'] else 38
        scale = int(r['SCALE']) if r['SCALE'] else 0

        fields.append({
            "name": col, "fullName": col, "nativeType": native,
            "nativeFieldInfo": {
                "dataType": jdbc_code, "name": col, "nullable": nullable,
                "ordinalPostion": int(r['ORDINAL_POSITION']),
                "scale": scale, "size": size, "typeName": native
            },
            "isSelected": True
        })
        select_cols.append(f'"{col}"')

    fqn = f'"{db}"."{sch}"."{tbl}"'
    select_script = f'[{tbl}]:\nSELECT ' + ',\n\t'.join(select_cols) + f'\nFROM {fqn};'

    table_params = [
        {"name": "role", "value": sf_role},
        {"name": "database", "value": db},
        {"name": "owner", "value": sch}
    ]

    payload = {
        "spaceId": space_id,
        "connectionId": connection_id,
        "database": db,
        "schema": sch,
        "tables": [{
            "tableName": tbl,
            "selectionScript": select_script,
            "additionalProperties": {
                "fields": json.dumps(fields),
                "tableRequestParameters": json.dumps(table_params)
            }
        }]
    }

    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    tenant = _snowflake.get_generic_secret_string('qlik_tenant')
    resp = requests.post(
        f"https://{tenant}/api/v1/catalog/"
        "catalog-integration/actions/create-hierarchy-for-connected-datasets",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        },
        json=payload,
        timeout=30
    )
    return {
        "status": resp.status_code,
        "dataset_ids": resp.json() if resp.status_code == 201 else None,
        "error": resp.text if resp.status_code != 201 else None,
        "table": f"{db}.{sch}.{tbl}"
    }
$$;

-- 4f. Link Glossary to Data Product (PATCH /api/data-governance/data-products/{id})
CREATE OR REPLACE PROCEDURE LINK_GLOSSARY_TO_DATA_PRODUCT(
  DATA_PRODUCT_ID VARCHAR,
  GLOSSARY_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'link_glossary'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET, 'qlik_tenant' = QLIK_TENANT_SECRET)
AS
$$
import _snowflake
import requests
import json

def link_glossary(session, data_product_id, glossary_id):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    tenant = _snowflake.get_generic_secret_string('qlik_tenant')
    url = f'https://{tenant}/api/data-governance/data-products/{data_product_id}'
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    }

    # GET current glossaryIds
    get_resp = requests.get(url, headers=headers)
    if get_resp.status_code != 200:
        return {'linked': False, 'error': f'GET failed: {get_resp.status_code}'}

    dp = get_resp.json()
    existing = dp.get('glossaryIds', []) or []
    if glossary_id in existing:
        return {'linked': True, 'message': 'Already linked'}
    existing.append(glossary_id)

    # PATCH with replace on /glossaryIds
    patches = [{"op": "replace", "path": "/glossaryIds", "value": existing}]
    resp = requests.patch(url, headers=headers, data=json.dumps(patches))
    return {
        'status_code': resp.status_code,
        'linked': resp.status_code == 204,
        'data_product_id': data_product_id,
        'glossary_id': glossary_id
    }
$$;

-- 4g. Reload Qlik App (POST /api/v1/reloads)
CREATE OR REPLACE PROCEDURE RELOAD_QLIK_APP(
  APP_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'reload_app'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET, 'qlik_tenant' = QLIK_TENANT_SECRET)
AS
$$
import _snowflake
import requests
import time

def reload_app(session, app_id):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    tenant = _snowflake.get_generic_secret_string('qlik_tenant')
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    }

    # Trigger reload
    url = f'https://{tenant}/api/v1/reloads'
    body = {'appId': app_id}
    resp = requests.post(url, headers=headers, json=body)

    if resp.status_code not in (200, 201):
        try:
            return {'status_code': resp.status_code, 'reloaded': False, 'error': resp.json()}
        except:
            return {'status_code': resp.status_code, 'reloaded': False, 'error': resp.text}

    reload = resp.json()
    reload_id = reload.get('id', '')
    status = reload.get('status', '')

    # Poll for completion (max 5 minutes)
    poll_url = f'https://{tenant}/api/v1/reloads/{reload_id}'
    for i in range(30):
        if status in ('SUCCEEDED', 'FAILED', 'CANCELED', 'EXCEEDED_LIMIT'):
            break
        time.sleep(10)
        poll_resp = requests.get(poll_url, headers=headers)
        if poll_resp.status_code == 200:
            reload = poll_resp.json()
            status = reload.get('status', '')

    return {
        'status_code': resp.status_code,
        'reloaded': status == 'SUCCEEDED',
        'reload_id': reload_id,
        'reload_status': status,
        'app_id': app_id,
        'duration': reload.get('duration', ''),
        'error': reload.get('log', '') if status == 'FAILED' else None
    }
$$;

-- NOTE: The following Qlik operations are handled by the Qlik MCP server
-- registered in CoCo, not by stored procedures:
--   - List spaces:           mcp__qlik-local__spaces__list
--   - Create glossary:       mcp__qlik-local__glossaries__create
--   - Create glossary term:  mcp__qlik-local__glossaries__create_term
--   - Create data product:   mcp__qlik-local__data_products__create

-- =============================================================================
-- 5. Upload Skill to Stage
-- =============================================================================
CREATE STAGE IF NOT EXISTS AGENT_SKILLS_STAGE;

COPY INTO @AGENT_SKILLS_STAGE/create_data_product_from_sv/SKILL.md
  FROM (SELECT $$---
name: create_data_product_from_sv
description: Creates a Qlik Data Product from a Snowflake Semantic View. Registers datasets, creates a glossary with documentation, creates a data product, and links everything together.
---

Follow the steps in the skill file at skills/create_data_product_from_sv/SKILL.md
$$)
  FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE RECORD_DELIMITER = NONE FIELD_DELIMITER = NONE)
  OVERWRITE = TRUE SINGLE = TRUE;

COPY INTO @AGENT_SKILLS_STAGE/create_app_from_data_product/SKILL.md
  FROM (SELECT $$---
name: create_app_from_data_product
description: Creates a Qlik Sense app from an existing Qlik Data Product. Generates a load script from dataset metadata, creates master dimensions and measures from the glossary, builds a default analytics sheet with charts, and reloads the app.
---

Follow the steps in the skill file at skills/create_app_from_data_product/SKILL.md
$$)
  FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE RECORD_DELIMITER = NONE FIELD_DELIMITER = NONE)
  OVERWRITE = TRUE SINGLE = TRUE;

-- =============================================================================
-- 6. Create the Agent
-- =============================================================================
CREATE OR REPLACE AGENT QLIK_API_AGENT
  COMMENT = 'Cortex Agent that integrates Snowflake with Qlik Cloud. Creates data products from semantic views, builds Qlik Sense apps with load scripts, glossaries, master items, and analytics sheets.'
  FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are an agent that integrates Snowflake with the Qlik Cloud REST API.

    **Capabilities:**
    - Create Qlik Sense apps, set load scripts, and trigger reloads.
    - Register Qlik datasets from Snowflake tables.
    - Inspect Snowflake semantic views and retrieve table column metadata.
    - Via the Qlik MCP server: list spaces, search the catalog, create glossaries
      and terms, create data products, manage dimensions/measures, create sheets
      and charts, and more.

    **Skills:**
    - `create_data_product_from_sv` — Creates a Qlik Data Product from a Snowflake
      Semantic View. Follow every step and respect every GATE.
    - `create_app_from_data_product` — Creates a full Qlik Sense app from a Data
      Product. Follow every step and respect every GATE.

    **IMPORTANT RULES:**
    - Before executing any skill, READ the full skill instructions from your context.
      Do NOT rely on cached or memorized versions — the skills may have been updated.
    - Do NOT activate data products. Always leave them in draft.
    - Always use fully qualified LIB CONNECT: `LIB CONNECT TO '<spaceName>:<connectionName>';`
    - Always ask the user which space to create the app in. This is a GATE.
  orchestration: |
    Use the appropriate tool for each operation.

    CRITICAL: Before executing a skill workflow, re-read the full skill instructions
    from your context. Do NOT rely on previous cached knowledge of the skill steps.
    The skill files are the source of truth — follow them exactly as written.

    The skills create_data_product_from_sv and create_app_from_data_product
    are loaded in your context. Do NOT call server_skill to load them.
    Follow the skill instructions directly.

    - To create a data product from a semantic view: follow create_data_product_from_sv
      strictly in order. Respect every GATE.
    - To create a Qlik app from a data product: follow create_app_from_data_product
      strictly in order. Respect every GATE.
    - If a step fails, follow the rollback instructions in the skill.
    - For dataset creation, always prefer create_qlik_dataset (handles column
      discovery, type mapping, and the API call in a single step).
tools:
  - tool_spec:
      type: generic
      name: create_qlik_app
      description: "Creates a new Qlik Sense app in a specified space. SPACE_ID is required."
      input_schema:
        type: object
        properties:
          APP_NAME:
            type: string
            description: "Name of the Qlik app"
          SPACE_ID:
            type: string
            description: "Target space ID - REQUIRED, app will fail without this"
          APP_DESCRIPTION:
            type: string
            description: "Description (optional)"
        required: [APP_NAME, SPACE_ID]
  - tool_spec:
      type: generic
      name: set_qlik_app_script
      description: "Sets the load script for a Qlik app via POST /api/v1/apps/{appId}/scripts"
      input_schema:
        type: object
        properties:
          APP_ID:
            type: string
            description: "The Qlik app ID"
          SCRIPT:
            type: string
            description: "The Qlik load script content"
          VERSION_MESSAGE:
            type: string
            description: "Version description (optional)"
        required: [APP_ID, SCRIPT]
  - tool_spec:
      type: generic
      name: get_semantic_view_ddl
      description: "Returns the DDL of a Snowflake Semantic View"
      input_schema:
        type: object
        properties:
          SEMANTIC_VIEW_NAME:
            type: string
            description: "Fully qualified semantic view name"
        required: [SEMANTIC_VIEW_NAME]
  - tool_spec:
      type: generic
      name: create_qlik_dataset
      description: "Creates a Qlik dataset from a Snowflake table using the catalog-integration API. Auto-discovers columns from INFORMATION_SCHEMA. No QRI or data asset discovery needed."
      input_schema:
        type: object
        properties:
          DB:
            type: string
            description: "Snowflake database name"
          SCH:
            type: string
            description: "Snowflake schema name"
          TBL:
            type: string
            description: "Snowflake table name"
          SPACE_ID:
            type: string
            description: "Qlik space ID (optional, defaults to Snowflake shared space)"
          CONNECTION_ID:
            type: string
            description: "Qlik connection ID for the Snowflake connection (optional)"
          SF_ROLE:
            type: string
            description: "Snowflake role for Qlik to use (optional, defaults to QLIK_DATA_PRODUCT)"
        required: [DB, SCH, TBL]
  - tool_spec:
      type: generic
      name: get_table_columns
      description: "Returns column names, data types, precision and scale for a Snowflake table via INFORMATION_SCHEMA"
      input_schema:
        type: object
        properties:
          DATABASE_NAME:
            type: string
            description: "Database name"
          SCHEMA_NAME:
            type: string
            description: "Schema name"
          TABLE_NAME:
            type: string
            description: "Table name"
        required: [DATABASE_NAME, SCHEMA_NAME, TABLE_NAME]
  - tool_spec:
      type: generic
      name: link_glossary_to_data_product
      description: "Links a Qlik glossary to a data product so it appears in the Qlik Cloud UI"
      input_schema:
        type: object
        properties:
          DATA_PRODUCT_ID:
            type: string
            description: "The Qlik data product ID"
          GLOSSARY_ID:
            type: string
            description: "The Qlik glossary ID to link"
        required: [DATA_PRODUCT_ID, GLOSSARY_ID]
  - tool_spec:
      type: generic
      name: reload_qlik_app
      description: "Triggers a data reload for a Qlik app and waits for completion (up to 5 minutes)"
      input_schema:
        type: object
        properties:
          APP_ID:
            type: string
            description: "The Qlik app ID to reload"
        required: [APP_ID]
tool_resources:
  reload_qlik_app:
    type: procedure
    identifier: RELOAD_QLIK_APP
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  link_glossary_to_data_product:
    type: procedure
    identifier: LINK_GLOSSARY_TO_DATA_PRODUCT
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  create_qlik_app:
    type: procedure
    identifier: CREATE_QLIK_APP
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  set_qlik_app_script:
    type: procedure
    identifier: SET_QLIK_APP_SCRIPT
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  get_semantic_view_ddl:
    type: procedure
    identifier: GET_SEMANTIC_VIEW_DDL
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  create_qlik_dataset:
    type: procedure
    identifier: CREATE_QLIK_DATASET
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  get_table_columns:
    type: procedure
    identifier: GET_TABLE_COLUMNS
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
skills:
  - name: create_data_product_from_sv
    source:
      type: STAGE
      path: "@AGENT_SKILLS_STAGE/create_data_product_from_sv"
  - name: create_app_from_data_product
    source:
      type: STAGE
      path: "@AGENT_SKILLS_STAGE/create_app_from_data_product"
mcp_servers:
  - server_spec:
      name: "QLIK_MCP_DB.PUBLIC.QLIK_MCP_SERVER"
$$;

-- =============================================================================
-- 7. Register agent in Snowflake CoWork
-- =============================================================================
-- If your account has a Snowflake CoWork object, add the agent to make it
-- visible in CoWork. Skip if no CoWork object exists (agents are still
-- accessible via SQL/REST API and direct link in Snowsight).
--
-- To check if a CoWork object exists:
--   SHOW SNOWFLAKE INTELLIGENCE;
--
-- To create one if needed:
--   CREATE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
--
-- Add the agent:
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  ADD AGENT QLIK_API_AGENT;

-- Grant USAGE so users can see and use the agent in CoWork:
-- GRANT USAGE ON AGENT QLIK_API_AGENT TO ROLE <user_role>;

-- =============================================================================
-- 8. Test the agent
-- =============================================================================
-- SELECT TRY_PARSE_JSON(
--   SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--     '<DB>.<SCHEMA>.QLIK_API_AGENT',
--     $${ "messages": [{ "role": "user", "content": [{ "type": "text",
--         "text": "Create a Qlik app called 'Test App'" }] }] }$$,
--     TRUE
--   )
-- ) AS resp;
