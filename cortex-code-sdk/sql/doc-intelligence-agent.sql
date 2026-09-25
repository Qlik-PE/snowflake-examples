-- =============================================================================
-- Document Intelligence Agent (Cortex AI Functions + Coding Agent)
-- =============================================================================
--
-- This script creates a Cortex Agent that processes, parses, classifies, and
-- extracts structured information from documents stored on Snowflake stages.
-- It uses the code_toolset_all tool type (Coding Agent), giving the agent
-- full access to the CoCo sandbox runtime (bash, SQL, file read/write, grep,
-- glob, web search, and skills).
--
-- The agent's system instructions cover the Cortex AI document functions:
--
--   - AI_PARSE_DOCUMENT  Parse text, layout, tables, and images from PDFs,
--                        Word docs, and scanned documents (LAYOUT or OCR mode)
--   - AI_EXTRACT         Extract structured fields (entities, lists, tables)
--                        from documents using natural language schemas
--   - AI_CLASSIFY        Classify documents into user-defined categories
--                        (invoice, contract, receipt, etc.)
--   - AI_COMPLETE        General-purpose text generation and visual analysis
--                        of charts, diagrams, and images
--   - AI_SUMMARIZE       Summarize text, image, and document content
--   - AI_TRANSLATE       Translate extracted text between languages
--   - AI_SENTIMENT       Analyze sentiment of extracted text
--
-- The agent is configured with workflow patterns for:
--   - Single-document parsing and extraction
--   - Document classification and routing
--   - Batch processing across stage directories
--   - Incremental pipelines (stream + task + dynamic table)
--
-- Prerequisites:
--   - Snowflake account with Cortex AI functions enabled
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Documents uploaded to a Snowflake stage
--
-- Usage:
--   1. Set the target database and schema in Step 0
--   2. Run the script in a Snowflake worksheet or via Snowflake CLI
--   3. The agent appears in Snowflake Intelligence if registered (Step 2)
--
-- References:
--   - Cortex AI document functions: https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-documents
--   - AI_PARSE_DOCUMENT:            https://docs.snowflake.com/en/user-guide/snowflake-cortex/parse-document
--   - AI_EXTRACT:                   https://docs.snowflake.com/en/user-guide/snowflake-cortex/document-extraction
--   - Coding Agent (code_toolset_all): https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-coding-agent
--
-- =============================================================================

-- =============================================================================
-- Step 0: Configuration
-- =============================================================================

SET TARGET_DATABASE = 'CORTEX_CODE';
SET TARGET_SCHEMA   = 'PUBLIC';

USE DATABASE IDENTIFIER($TARGET_DATABASE);
USE SCHEMA IDENTIFIER($TARGET_SCHEMA);

-- =============================================================================
-- Step 1: Create the Document Intelligence Agent
-- =============================================================================

CREATE OR REPLACE AGENT IDENTIFIER($TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.DOC_INTELLIGENCE')
  COMMENT = 'Parses, extracts, and answers questions about documents using Cortex AI functions'
  PROFILE = '{"display_name": "Doc Intelligence", "color": "orange"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    system: |
      You are a document intelligence specialist that processes, parses, classifies, and extracts
      structured information from documents stored on Snowflake stages. You use Cortex AI functions
      to build end-to-end document processing workflows directly in SQL.

      ## Core capabilities

      You have access to the following Cortex AI functions for document processing:

      - **AI_PARSE_DOCUMENT**: Extracts text, data, layout elements, and images from documents on stages.
        Supports two modes:
        - LAYOUT mode: preferred for complex documents with tables, headers, and layout relationships.
          Supports image extraction via `'extract_images': true`.
        - OCR mode: optimized for fast text extraction from scanned or text-heavy documents.
        Use `page_split` to separate multi-page documents into pages, and `page_filter` to process specific pages.
        Syntax: `SELECT AI_PARSE_DOCUMENT(TO_FILE('@stage_name', 'file.pdf'), {'mode': 'LAYOUT', 'page_split': true})`

      - **AI_EXTRACT**: Extracts structured information (entities, lists, tables, fields) from text or
        document files using natural language descriptions or a schema.
        Syntax: `SELECT AI_EXTRACT(TO_FILE('@stage_name', 'file.pdf'), {'field_name': 'description of what to extract'})`

      - **AI_CLASSIFY**: Classifies a document into one of a set of user-defined categories. Useful for
        routing mixed inbound document streams (invoices, contracts, statements) to different workflows.
        Syntax: `SELECT AI_CLASSIFY(TO_FILE('@stage_name', 'file.pdf'), ['invoice', 'contract', 'receipt', 'report'])`

      - **AI_COMPLETE**: General-purpose text generation and analysis. Can analyze charts, diagrams,
        and images when given a file reference. Choose a model explicitly.
        Syntax: `SELECT AI_COMPLETE('claude-3-5-sonnet', TO_FILE('@stage_name', 'image.png'), {'prompt': 'Describe this chart'})`

      - **AI_SUMMARIZE**: Generates concise summaries of text, image, and document content.
      - **AI_TRANSLATE**: Translates text between languages.
      - **AI_SENTIMENT**: Analyzes sentiment of extracted text content.

      ## Workflow patterns

      1. **Parse then extract**: Use AI_PARSE_DOCUMENT to get the full text, then AI_EXTRACT on the parsed
         output to pull structured fields.
      2. **Classify then route**: Use AI_CLASSIFY to determine document type, then apply type-specific
         extraction schemas with AI_EXTRACT.
      3. **Batch processing**: Process multiple files from a stage using directory listings and SQL joins.
         AI_PARSE_DOCUMENT is horizontally scalable for batch workloads.
      4. **Pipeline building**: Combine functions into incremental pipelines using streams, tasks, and
         dynamic tables to keep outputs fresh as new files land on stages.

      ## Important rules

      - Always use `TO_FILE('@stage_name', 'filename')` to reference documents on stages.
      - When the user mentions a file, first check if the stage exists with `SHOW STAGES` or `LIST @stage_name`.
      - For multi-page documents, default to `'page_split': true` so results are organized by page.
      - Prefer LAYOUT mode unless the user specifically needs only raw text (OCR mode).
      - When extracting structured data, ask the user what fields they need if not specified.
      - Present extracted data in clean, tabular format when possible.
      - For batch operations over many files, use `DIRECTORY(@stage_name)` to list files and process them
        with a SQL query that applies AI functions across rows.

    response: |
      Present extracted information in a clear, structured format:
      - Use tables for tabular data (entities, fields, key-value pairs).
      - Show document classification results with confidence when available.
      - For parsed text, preserve the document's logical structure (headings, sections, lists).
      - When multiple documents are processed, summarize results per document before any aggregate analysis.
      - Include the SQL used so the user can reproduce or modify the workflow.

    sample_questions:
      - question: "Parse the document invoice.pdf from @my_stage and extract the vendor name, invoice number, date, and total amount."
      - question: "Classify all documents in @incoming_docs as either invoice, contract, receipt, or report."
      - question: "Extract the full text and layout from the PDF at @reports/quarterly_report.pdf, preserving tables and headers."
      - question: "What are the key terms and obligations in the contract stored at @legal_docs/agreement.pdf?"
      - question: "Build a batch extraction pipeline that processes all invoices on @invoices_stage and outputs vendor, amount, and date into a table."
      - question: "Summarize the document at @my_stage/whitepaper.pdf and translate the summary into Spanish."

  tools:
    - tool_spec:
        type: code_toolset_all
        name: code_toolset_all

  tool_resources:
    code_toolset_all:
      permission_policy:
        type: always_allow
  $$;

-- =============================================================================
-- Step 2 (Optional): Register with Snowflake Intelligence
-- =============================================================================
-- Uncomment the following to make the agent available in the Snowflake
-- Intelligence (CoWork) sidebar for interactive use.
--
-- ALTER AGENT IDENTIFIER($TARGET_DATABASE || '.' || $TARGET_SCHEMA || '.DOC_INTELLIGENCE')
--   SET IS_COWORK_VISIBLE = TRUE;

-- =============================================================================
-- Step 3: Call the agent
-- =============================================================================
-- NOTE: The examples below call the agent at its default location
-- (CORTEX_CODE.PUBLIC). Adjust them if you changed TARGET_DATABASE/SCHEMA.
-- Replace @my_stage/sample.pdf with an actual file on one of your stages.

-- Option A: SQL via DATA_AGENT_RUN
--
-- SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--   'CORTEX_CODE.PUBLIC.DOC_INTELLIGENCE',
--   $$
--   {
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Parse the document sample.pdf from @my_stage using LAYOUT mode and extract all tables."
--           }
--         ]
--       }
--     ]
--   }
--   $$,
--   TRUE
-- ) AS response;

-- Option B: REST API via curl (streaming SSE)
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/DOC_INTELLIGENCE:run" \
--   --header 'Content-Type: application/json' \
--   --header 'Accept: text/event-stream' \
--   --header "Authorization: Bearer $PAT" \
--   --data '{
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Parse the document sample.pdf from @my_stage using LAYOUT mode and extract all tables."
--           }
--         ]
--       }
--     ]
--   }'

-- Option C: REST API — non-streaming JSON
--
-- curl -X POST "$SNOWFLAKE_ACCOUNT_BASE_URL/api/v2/databases/CORTEX_CODE/schemas/PUBLIC/agents/DOC_INTELLIGENCE:run" \
--   --header 'Content-Type: application/json' \
--   --header 'Accept: application/json' \
--   --header "Authorization: Bearer $PAT" \
--   --data '{
--     "stream": false,
--     "messages": [
--       {
--         "role": "user",
--         "content": [
--           {
--             "type": "text",
--             "text": "Classify all documents in @incoming_docs as either invoice, contract, receipt, or report."
--           }
--         ]
--       }
--     ]
--   }'
