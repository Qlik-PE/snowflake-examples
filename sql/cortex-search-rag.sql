-- =============================================================================
-- Cortex Search + RAG Agent Demo
-- =============================================================================
--
-- This script demonstrates how to build a Retrieval-Augmented Generation (RAG)
-- pipeline using Cortex Search and a Cortex Agent:
--
--   1. Create a knowledge base of product documentation articles
--   2. Build a Cortex Search service over the corpus
--   3. Query the search service directly (hybrid search)
--   4. Create a Cortex Agent that uses the search service as a RAG tool
--   5. Test the agent with natural-language questions
--   6. (Optional) Register the agent with Snowflake Intelligence
--
-- Features covered:
--   - CREATE CORTEX SEARCH SERVICE (hybrid vector + keyword search)
--   - SEARCH_PREVIEW function for ad-hoc queries
--   - Cortex Search as a tool_spec in a Cortex Agent (type: cortex_search)
--   - Attribute-based filtering
--   - Analytical search (optional)
--
-- Prerequisites:
--   - Snowflake account with Cortex Search and Cortex Agents enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - A warehouse for search index builds and agent execution
--
-- Usage:
--   1. Fill in the parameters in Step 0
--   2. Run the entire script in a Snowflake worksheet
--   3. The agent appears in Snowflake Intelligence (CoWork) if registered
--
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Step 0: Configuration
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_DEMOS';
SET TARGET_SCHEMA   = 'PUBLIC';
SET WAREHOUSE       = 'COMPUTE';     -- Replace with your warehouse name
SET AGENT_NAME      = 'PRODUCT_DOCS_AGENT';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);
USE WAREHOUSE IDENTIFIER($WAREHOUSE);

-- =============================================================================
-- Step 1: Create the Knowledge Base
-- =============================================================================
-- A sample product documentation corpus. In production, this would be populated
-- from a document ingestion pipeline (e.g., PDF parsing via AI_PARSE_DOCUMENT,
-- or loading from an internal stage).
-- =============================================================================

CREATE OR REPLACE TABLE product_docs (
    doc_id      INT,
    title       VARCHAR(200),
    category    VARCHAR(50),     -- Filterable attribute
    product     VARCHAR(50),     -- Filterable attribute
    chunk_text  VARCHAR(5000),   -- The searchable text content
    last_updated DATE
);

INSERT INTO product_docs VALUES
-- Getting Started guides
(1, 'Getting Started with Snowflake Notebooks',
    'Getting Started', 'Notebooks',
    'Snowflake Notebooks provide an interactive development environment for Python and SQL. '
    || 'To create a notebook, navigate to the Notebooks section in Snowsight and click Create. '
    || 'Notebooks run on warehouse compute by default, but you can switch to a container runtime '
    || 'for GPU workloads. Each cell can be Python or SQL, and cells share state within a session. '
    || 'Use the sidebar to manage packages, upload files, and configure the runtime environment.',
    '2026-06-15'),

(2, 'Getting Started with Cortex Agents',
    'Getting Started', 'Cortex Agents',
    'Cortex Agents are AI-powered assistants that can answer questions using your Snowflake data. '
    || 'An agent combines an LLM with tools: Cortex Analyst for structured data (via Semantic Views), '
    || 'Cortex Search for unstructured text retrieval, and MCP servers for external integrations. '
    || 'Create an agent with CREATE AGENT ... FROM SPECIFICATION, defining instructions, tools, and '
    || 'tool_resources. Agents appear in Snowflake Intelligence (CoWork) when given a profile.',
    '2026-07-01'),

(3, 'Getting Started with Cortex Search',
    'Getting Started', 'Cortex Search',
    'Cortex Search provides low-latency hybrid (vector + keyword) search over your text data. '
    || 'Create a search service with CREATE CORTEX SEARCH SERVICE, specifying the text column to index, '
    || 'filterable attributes, a warehouse for index builds, and a target lag for refresh frequency. '
    || 'Query the service using SEARCH_PREVIEW (SQL), the Python API, or the REST API. '
    || 'Cortex Search handles embedding, indexing, and refresh automatically.',
    '2026-07-10'),

-- Troubleshooting articles
(4, 'Troubleshooting: Agent Returns Empty Responses',
    'Troubleshooting', 'Cortex Agents',
    'If your Cortex Agent returns empty or generic responses, check these common causes: '
    || '1. Verify the semantic view or search service referenced in tool_resources exists and is accessible. '
    || '2. Ensure the warehouse specified in execution_environment is running and the role has USAGE. '
    || '3. Check that the agent''s instructions clearly describe when to use each tool. '
    || '4. For MCP-connected agents, confirm OAuth authentication is complete with SYSTEM$START_USER_OAUTH_FLOW. '
    || '5. Review the agent spec with DESCRIBE AGENT to verify all tool references resolve correctly.',
    '2026-07-20'),

(5, 'Troubleshooting: Cortex Search Service Not Refreshing',
    'Troubleshooting', 'Cortex Search',
    'If your Cortex Search service is not picking up new data, check these items: '
    || '1. Verify the warehouse specified in the service is not suspended and has capacity. '
    || '2. Check TARGET_LAG — the service only refreshes when data has been stale longer than this interval. '
    || '3. For incremental refresh, ensure change tracking is enabled on all source tables. '
    || '4. Run SHOW CORTEX SEARCH SERVICES to check the service status and last refresh time. '
    || '5. Use ALTER CORTEX SEARCH SERVICE ... REFRESH to force an immediate refresh. '
    || '6. If the service is stuck, check INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICE_REFRESH_HISTORY.',
    '2026-08-01'),

(6, 'Troubleshooting: Notebook Kernel Crashes',
    'Troubleshooting', 'Notebooks',
    'Notebook kernel crashes are typically caused by memory pressure. Common fixes: '
    || '1. Use a larger warehouse (MEDIUM or LARGE) for data-intensive workloads. '
    || '2. Avoid collecting large Snowpark DataFrames into Pandas — use .limit() or .sample(). '
    || '3. For GPU workloads, ensure your container runtime has a compute pool with sufficient GPU memory. '
    || '4. Check the notebook logs in the Activity section for OOM (out-of-memory) errors. '
    || '5. Split large operations across multiple cells to release intermediate results.',
    '2026-06-20'),

-- Best practices
(7, 'Best Practices: Designing Agent Instructions',
    'Best Practices', 'Cortex Agents',
    'Well-designed agent instructions dramatically improve response quality. Key principles: '
    || '1. Separate "response" instructions (tone, format, rules) from "orchestration" instructions (tool routing). '
    || '2. Be explicit about when to use each tool: "Use SaaSMetrics for revenue questions, use SearchTool for policy lookups." '
    || '3. Include sample questions in the spec to anchor the agent''s understanding. '
    || '4. For multi-tool agents, specify a priority order so the agent doesn''t call all tools for every question. '
    || '5. Keep instructions concise — overly long prompts increase latency and token costs. '
    || '6. Test instructions iteratively with DATA_AGENT_RUN before deploying to CoWork.',
    '2026-08-10'),

(8, 'Best Practices: Optimizing Cortex Search Quality',
    'Best Practices', 'Cortex Search',
    'Search quality depends on how you prepare and index your data. Key optimization strategies: '
    || '1. Chunk documents into passages of 200-500 tokens for optimal retrieval granularity. '
    || '2. Include metadata columns (title, category, date) as ATTRIBUTES for filtered search. '
    || '3. Use descriptive column names — the embedding model uses column context for relevance. '
    || '4. Set PRIMARY KEY on your search service for efficient incremental refreshes. '
    || '5. Choose an appropriate EMBEDDING_MODEL: snowflake-arctic-embed-l-v2.0 offers the best quality. '
    || '6. Use columns_and_descriptions in the agent tool config to help the agent filter effectively. '
    || '7. Monitor search quality with REQUEST_LOGGING = TRUE and review the logged queries.',
    '2026-08-15'),

-- How-to guides
(9, 'How to Connect Cortex Search to a Cortex Agent',
    'How-To', 'Cortex Search',
    'To wire a Cortex Search service as a retrieval tool in a Cortex Agent: '
    || '1. Create the search service: CREATE CORTEX SEARCH SERVICE ... ON chunk_text ATTRIBUTES category, product. '
    || '2. In the agent spec, add a tool with type "cortex_search" and a descriptive name. '
    || '3. In tool_resources, reference the search service FQN and configure max_results, title_column, id_column. '
    || '4. Add columns_and_descriptions to tell the agent what each column contains and whether it is searchable or filterable. '
    || '5. Grant USAGE on the search service to the role running the agent. '
    || '6. Test with SEARCH_PREVIEW first to verify the service returns relevant results for your expected queries.',
    '2026-08-05'),

(10, 'How to Enable Analytical Search on an Agent',
    'How-To', 'Cortex Agents',
    'Analytical search lets an agent analyze across many documents (counts, trends, aggregates) rather than '
    || 'just retrieving a few passages. To enable it: '
    || '1. Ensure your agent has a Cortex Search tool configured with detailed columns_and_descriptions. '
    || '2. Add orchestration.capabilities.analytical_search = true in the agent specification. '
    || '3. The agent will auto-route: simple questions use standard RAG, analytical questions trigger '
    || 'the full search-prune-extract-aggregate loop using AI_FILTER, AI_EXTRACT, and SQL. '
    || '4. Analytical search incurs additional AI function costs — monitor via CORTEX_AGENT_USAGE_HISTORY.',
    '2026-08-20');

SELECT '>>> Knowledge base created: ' || COUNT(*) || ' articles' AS status
FROM product_docs;

-- =============================================================================
-- Step 2: Create the Cortex Search Service
-- =============================================================================
-- This creates a hybrid search index over the chunk_text column.
-- The service automatically embeds text, builds the index, and keeps it
-- refreshed within the specified target lag.
-- =============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE product_docs_search
  ON chunk_text
  ATTRIBUTES category, product
  WAREHOUSE = IDENTIFIER($WAREHOUSE)
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
  AS (
    SELECT
        doc_id,
        title,
        category,
        product,
        chunk_text,
        last_updated
    FROM product_docs
  );

-- Verify the service was created
SHOW CORTEX SEARCH SERVICES LIKE 'PRODUCT_DOCS_SEARCH' IN SCHEMA;

-- =============================================================================
-- Step 3: Query the Search Service Directly
-- =============================================================================
-- Use SEARCH_PREVIEW for ad-hoc testing before wiring to an agent.
-- =============================================================================

-- 3a. Basic search query
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.PRODUCT_DOCS_SEARCH',
    '{
      "query": "how do I create a cortex agent",
      "columns": ["title", "category", "product", "chunk_text"],
      "limit": 3
    }'
  )
)['results'] AS results;

-- 3b. Filtered search (only troubleshooting articles)
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.PRODUCT_DOCS_SEARCH',
    '{
      "query": "agent not working empty responses",
      "columns": ["title", "category", "chunk_text"],
      "filter": {"@eq": {"category": "Troubleshooting"}},
      "limit": 3
    }'
  )
)['results'] AS results;

-- 3c. Filtered by product
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.PRODUCT_DOCS_SEARCH',
    '{
      "query": "optimize search quality best practices",
      "columns": ["title", "product", "chunk_text"],
      "filter": {"@eq": {"product": "Cortex Search"}},
      "limit": 3
    }'
  )
)['results'] AS results;

-- =============================================================================
-- Step 4: Create the RAG Agent
-- =============================================================================
-- The agent uses the Cortex Search service as a retrieval tool to ground
-- its responses in the knowledge base. It retrieves relevant articles
-- and synthesizes an answer.
-- =============================================================================

CREATE OR REPLACE AGENT IDENTIFIER($AGENT_NAME)
  FROM SPECIFICATION $$
models:
  orchestration: auto

instructions:
  response: |
    You are a helpful product documentation assistant. Your role is to answer
    questions about Snowflake products using the knowledge base.

    Rules:
    - ALWAYS cite the source article title when answering.
    - If the knowledge base does not contain relevant information, say so clearly.
    - Be concise — summarize the key points rather than quoting entire articles.
    - When listing steps, preserve the numbered format from the source.
    - If the user asks about multiple products, search for each separately.

  orchestration: |
    Use the ProductDocs search tool to find relevant articles before answering.
    For troubleshooting questions, filter by category "Troubleshooting".
    For best practices, filter by category "Best Practices".
    For setup/how-to questions, search across all categories.

tools:
  - tool_spec:
      type: "cortex_search"
      name: "ProductDocs"
      description: "Search the product documentation knowledge base for articles about Snowflake Notebooks, Cortex Agents, and Cortex Search. Use this tool to find getting started guides, troubleshooting steps, best practices, and how-to instructions."

tool_resources:
  ProductDocs:
    search_service: "<DB>.<SCHEMA>.PRODUCT_DOCS_SEARCH"
    max_results: 5
    title_column: "title"
    id_column: "doc_id"
    columns_and_descriptions:
      chunk_text:
        description: "The main text content of the documentation article"
        type: "string"
        searchable: true
        filterable: false
      category:
        description: "Article category. Valid values: Getting Started, Troubleshooting, Best Practices, How-To"
        type: "string"
        searchable: false
        filterable: true
      product:
        description: "Product the article is about. Valid values: Notebooks, Cortex Agents, Cortex Search"
        type: "string"
        searchable: false
        filterable: true
      title:
        description: "The article title"
        type: "string"
        searchable: true
        filterable: false

  sample_questions:
    - question: "How do I get started with Cortex Agents?"
    - question: "My agent is returning empty responses, what should I check?"
    - question: "What are the best practices for Cortex Search quality?"
    - question: "How do I connect a Cortex Search service to an agent?"
    - question: "What is analytical search and how do I enable it?"

execution_environment:
  type: warehouse
  warehouse: "<WAREHOUSE>"
$$;

-- Replace placeholders with actual values
-- (The spec uses placeholders because $$ blocks don't interpolate variables)
EXECUTE IMMEDIATE
$$
DECLARE
    v_db VARCHAR;
    v_schema VARCHAR;
    v_wh VARCHAR;
    v_agent VARCHAR;
    v_search_fqn VARCHAR;
BEGIN
    SELECT GETVARIABLE('TARGET_DATABASE') INTO v_db;
    SELECT GETVARIABLE('TARGET_SCHEMA') INTO v_schema;
    SELECT GETVARIABLE('WAREHOUSE') INTO v_wh;
    SELECT GETVARIABLE('AGENT_NAME') INTO v_agent;

    v_search_fqn := v_db || '.' || v_schema || '.PRODUCT_DOCS_SEARCH';

    EXECUTE IMMEDIATE 'ALTER AGENT ' || v_agent || ' MODIFY LIVE VERSION SET SPECIFICATION $$
models:
  orchestration: auto

instructions:
  response: |
    You are a helpful product documentation assistant. Your role is to answer
    questions about Snowflake products using the knowledge base.

    Rules:
    - ALWAYS cite the source article title when answering.
    - If the knowledge base does not contain relevant information, say so clearly.
    - Be concise — summarize the key points rather than quoting entire articles.
    - When listing steps, preserve the numbered format from the source.
    - If the user asks about multiple products, search for each separately.

  orchestration: |
    Use the ProductDocs search tool to find relevant articles before answering.
    For troubleshooting questions, filter by category "Troubleshooting".
    For best practices, filter by category "Best Practices".
    For setup/how-to questions, search across all categories.

  sample_questions:
    - question: "How do I get started with Cortex Agents?"
    - question: "My agent is returning empty responses, what should I check?"
    - question: "What are the best practices for Cortex Search quality?"
    - question: "How do I connect a Cortex Search service to an agent?"
    - question: "What is analytical search and how do I enable it?"

tools:
  - tool_spec:
      type: "cortex_search"
      name: "ProductDocs"
      description: "Search the product documentation knowledge base for articles about Snowflake Notebooks, Cortex Agents, and Cortex Search. Use this tool to find getting started guides, troubleshooting steps, best practices, and how-to instructions."

tool_resources:
  ProductDocs:
    search_service: "' || v_search_fqn || '"
    max_results: 5
    title_column: "title"
    id_column: "doc_id"
    columns_and_descriptions:
      chunk_text:
        description: "The main text content of the documentation article"
        type: "string"
        searchable: true
        filterable: false
      category:
        description: "Article category. Valid values: Getting Started, Troubleshooting, Best Practices, How-To"
        type: "string"
        searchable: false
        filterable: true
      product:
        description: "Product the article is about. Valid values: Notebooks, Cortex Agents, Cortex Search"
        type: "string"
        searchable: false
        filterable: true
      title:
        description: "The article title"
        type: "string"
        searchable: true
        filterable: false

execution_environment:
  type: warehouse
  warehouse: "' || v_wh || '"
$$';

    EXECUTE IMMEDIATE 'ALTER AGENT ' || v_agent || ' SET '
        || 'PROFILE = ''{"display_name": "Product Docs Assistant", "avatar": "SparklesAgentIcon"}''';
END;
$$;

-- =============================================================================
-- Step 5: Verify the Agent
-- =============================================================================

SELECT GET_DDL('CORTEX_AGENT', $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME);

-- =============================================================================
-- Step 6: Test the Agent
-- =============================================================================
-- Run a few sample questions to verify RAG retrieval + synthesis.
-- =============================================================================

-- 6a. General knowledge question
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "How do I get started with Cortex Search?"}]}]}'
) AS response;

-- 6b. Troubleshooting question (should filter to Troubleshooting category)
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "My Cortex Agent is returning empty responses. What should I check?"}]}]}'
) AS response;

-- 6c. Cross-product question
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    $TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.' || $AGENT_NAME,
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "How do I connect a Cortex Search service to a Cortex Agent and enable analytical search?"}]}]}'
) AS response;

-- =============================================================================
-- Step 7: Register with Snowflake Intelligence (Optional)
-- =============================================================================

CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

EXECUTE IMMEDIATE
$$
DECLARE
    v_agent_fqn VARCHAR;
BEGIN
    SELECT GETVARIABLE('TARGET_DATABASE') || '.' || GETVARIABLE('TARGET_SCHEMA') || '.' || GETVARIABLE('AGENT_NAME') INTO v_agent_fqn;
    EXECUTE IMMEDIATE 'ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT ' || v_agent_fqn;
END;
$$;

-- =============================================================================
-- Cleanup (run manually when done)
-- =============================================================================
-- DROP CORTEX SEARCH SERVICE PRODUCT_DOCS_SEARCH;
-- DROP AGENT PRODUCT_DOCS_AGENT;
-- DROP TABLE product_docs;
