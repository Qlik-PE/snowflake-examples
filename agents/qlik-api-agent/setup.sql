-- =============================================================================
-- Qlik API Agent - Setup Script
-- Creates a Cortex Agent that interacts with Qlik Cloud REST API
-- =============================================================================
-- Prerequisites:
--   - ACCOUNTADMIN role (for EAI and integrations)
--   - A Qlik Cloud tenant with a valid API key
--   - Replace <QLIK_TENANT> with your tenant hostname
--   - Replace <QLIK_API_KEY> with your Qlik API key
-- =============================================================================

SET QLIK_TENANT = 'partner-engineering-saas.us.qlikcloud.com';
SET TARGET_DB = 'TORRA';
SET TARGET_SCHEMA = 'PUBLIC';
SET WAREHOUSE = 'COMPUTE';

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
-- 2. Secret - Qlik API Key
-- =============================================================================
CREATE OR REPLACE SECRET QLIK_API_KEY_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = '<QLIK_API_KEY>';  -- Replace with your actual API key

-- =============================================================================
-- 3. External Access Integration
-- =============================================================================
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION QLIK_CLOUD_EAI
  ALLOWED_NETWORK_RULES = (QLIK_CLOUD_NETWORK_RULE)
  ALLOWED_AUTHENTICATION_SECRETS = (QLIK_API_KEY_SECRET)
  ENABLED = TRUE;

-- =============================================================================
-- 4. Stored Procedures
-- =============================================================================

-- 4a. Create Qlik App (POST /api/v1/apps)
CREATE OR REPLACE PROCEDURE CREATE_QLIK_APP(
  APP_NAME VARCHAR,
  APP_DESCRIPTION VARCHAR DEFAULT '',
  SPACE_ID VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'create_app'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET)
AS
$$
import _snowflake
import requests

def create_app(session, app_name, app_description='', space_id=None):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    url = f'https://{session.sql("SELECT $QLIK_TENANT").collect()[0][0]}/api/v1/apps'
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    attributes = {'name': app_name}
    if app_description:
        attributes['description'] = app_description
    body = {'attributes': attributes}
    if space_id:
        body['spaceId'] = space_id
    resp = requests.post(url, headers=headers, json=body)
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text}
$$;

-- 4b. Create Qlik Dataset (POST /api/v1/data-sets)
CREATE OR REPLACE PROCEDURE CREATE_QLIK_DATASET(
  BODY VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'create_dataset'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET)
AS
$$
import _snowflake
import requests
import json

def create_dataset(session, body):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    url = f'https://{session.sql("SELECT $QLIK_TENANT").collect()[0][0]}/api/v1/data-sets'
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    resp = requests.post(url, headers=headers, json=json.loads(body))
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text}
$$;

-- 4c. Set Qlik App Script (POST /api/v1/apps/{appId}/scripts)
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
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET)
AS
$$
import _snowflake
import requests

def set_script(session, app_id, script, version_message=None):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    tenant = session.sql("SELECT $QLIK_TENANT").collect()[0][0]
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

-- 4e. List Qlik Spaces (GET /api/v1/spaces)
CREATE OR REPLACE PROCEDURE LIST_QLIK_SPACES()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'list_spaces'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET)
AS
$$
import _snowflake
import requests

def list_spaces(session):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    url = f'https://{session.sql("SELECT $QLIK_TENANT").collect()[0][0]}/api/v1/spaces'
    headers = {'Authorization': f'Bearer {api_key}'}
    resp = requests.get(url, headers=headers)
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text}
$$;

-- 4f. Create Qlik Glossary (POST /api/v1/glossaries)
CREATE OR REPLACE PROCEDURE CREATE_QLIK_GLOSSARY(
  NAME VARCHAR,
  DESCRIPTION VARCHAR DEFAULT ''
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'create_glossary'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET)
AS
$$
import _snowflake
import requests

def create_glossary(session, name, description=''):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    url = f'https://{session.sql("SELECT $QLIK_TENANT").collect()[0][0]}/api/v1/glossaries'
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    body = {'name': name}
    if description:
        body['description'] = description
    resp = requests.post(url, headers=headers, json=body)
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text}
$$;

-- 4g. Create Qlik Glossary Term (POST /api/v1/glossaries/{id}/terms)
CREATE OR REPLACE PROCEDURE CREATE_QLIK_GLOSSARY_TERM(
  GLOSSARY_ID VARCHAR,
  NAME VARCHAR,
  DESCRIPTION VARCHAR DEFAULT ''
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'create_term'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET)
AS
$$
import _snowflake
import requests

def create_term(session, glossary_id, name, description=''):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    tenant = session.sql("SELECT $QLIK_TENANT").collect()[0][0]
    url = f'https://{tenant}/api/v1/glossaries/{glossary_id}/terms'
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    body = {'name': name}
    if description:
        body['description'] = description
    resp = requests.post(url, headers=headers, json=body)
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text}
$$;

-- 4h. Create Qlik Data Product (POST /api/v1/data-products)
CREATE OR REPLACE PROCEDURE CREATE_QLIK_DATA_PRODUCT(
  NAME VARCHAR,
  DESCRIPTION VARCHAR DEFAULT '',
  SPACE_ID VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'create_data_product'
EXTERNAL_ACCESS_INTEGRATIONS = (QLIK_CLOUD_EAI)
PACKAGES = ('snowflake-snowpark-python', 'requests')
SECRETS = ('qlik_api_key' = QLIK_API_KEY_SECRET)
AS
$$
import _snowflake
import requests

def create_data_product(session, name, description='', space_id=None):
    api_key = _snowflake.get_generic_secret_string('qlik_api_key')
    url = f'https://{session.sql("SELECT $QLIK_TENANT").collect()[0][0]}/api/v1/data-products'
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    body = {'name': name}
    if description:
        body['description'] = description
    if space_id:
        body['spaceId'] = space_id
    resp = requests.post(url, headers=headers, json=body)
    try:
        return {'status_code': resp.status_code, 'response': resp.json()}
    except:
        return {'status_code': resp.status_code, 'response': resp.text}
$$;

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

-- =============================================================================
-- 6. Create the Agent
-- =============================================================================
CREATE OR REPLACE AGENT QLIK_API_AGENT
  FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: >
    You are an agent that interacts with the Qlik Cloud REST API and Snowflake.
    You can create Qlik apps, register data sets, set app load scripts, list spaces,
    create glossaries and terms, create data products, and inspect Snowflake semantic views.
    When asked to create a data product from a semantic view, load and follow the
    create_data_product_from_sv skill step by step.
  orchestration: >
    Use the appropriate tool for each Qlik operation.
    When the user asks to create a data product from a semantic view, load and follow
    the create_data_product_from_sv skill step by step.
tools:
  - tool_spec:
      type: generic
      name: create_qlik_app
      description: "Creates a new Qlik Sense app via POST /api/v1/apps"
      input_schema:
        type: object
        properties:
          APP_NAME:
            type: string
            description: "Name of the Qlik app"
          APP_DESCRIPTION:
            type: string
            description: "Description (optional)"
          SPACE_ID:
            type: string
            description: "Space ID (optional)"
        required: [APP_NAME]
  - tool_spec:
      type: generic
      name: create_qlik_dataset
      description: "Creates a data set in Qlik catalog via POST /api/v1/data-sets. BODY is a JSON string."
      input_schema:
        type: object
        properties:
          BODY:
            type: string
            description: "JSON string with the data set payload"
        required: [BODY]
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
      name: list_qlik_spaces
      description: "Lists all available Qlik Cloud spaces via GET /api/v1/spaces"
      input_schema:
        type: object
        properties: {}
  - tool_spec:
      type: generic
      name: create_qlik_glossary
      description: "Creates a new glossary in Qlik via POST /api/v1/glossaries"
      input_schema:
        type: object
        properties:
          NAME:
            type: string
            description: "Glossary name"
          DESCRIPTION:
            type: string
            description: "Glossary description (optional)"
        required: [NAME]
  - tool_spec:
      type: generic
      name: create_qlik_glossary_term
      description: "Creates a term in a Qlik glossary via POST /api/v1/glossaries/{id}/terms"
      input_schema:
        type: object
        properties:
          GLOSSARY_ID:
            type: string
            description: "The glossary ID"
          NAME:
            type: string
            description: "Term name"
          DESCRIPTION:
            type: string
            description: "Term description (optional)"
        required: [GLOSSARY_ID, NAME]
  - tool_spec:
      type: generic
      name: create_qlik_data_product
      description: "Creates a data product in Qlik via POST /api/v1/data-products"
      input_schema:
        type: object
        properties:
          NAME:
            type: string
            description: "Data product name"
          DESCRIPTION:
            type: string
            description: "Description (optional)"
          SPACE_ID:
            type: string
            description: "Target space ID (optional)"
        required: [NAME]
tool_resources:
  create_qlik_app:
    type: procedure
    identifier: CREATE_QLIK_APP
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  create_qlik_dataset:
    type: procedure
    identifier: CREATE_QLIK_DATASET
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
  list_qlik_spaces:
    type: procedure
    identifier: LIST_QLIK_SPACES
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  create_qlik_glossary:
    type: procedure
    identifier: CREATE_QLIK_GLOSSARY
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  create_qlik_glossary_term:
    type: procedure
    identifier: CREATE_QLIK_GLOSSARY_TERM
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
  create_qlik_data_product:
    type: procedure
    identifier: CREATE_QLIK_DATA_PRODUCT
    execution_environment:
      type: warehouse
      warehouse: COMPUTE
skills:
  - name: create_data_product_from_sv
    source:
      type: STAGE
      path: "@AGENT_SKILLS_STAGE/create_data_product_from_sv"
$$;

-- =============================================================================
-- 7. Test the agent
-- =============================================================================
-- SELECT TRY_PARSE_JSON(
--   SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--     '<DB>.<SCHEMA>.QLIK_API_AGENT',
--     $${ "messages": [{ "role": "user", "content": [{ "type": "text",
--         "text": "Create a Qlik app called 'Test App'" }] }] }$$,
--     TRUE
--   )
-- ) AS resp;
