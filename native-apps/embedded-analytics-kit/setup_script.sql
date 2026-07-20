-- =============================================================================
-- Embedded Analytics Starter Kit - Setup Script
-- =============================================================================
--
-- This is the Native App setup script. It runs automatically when the app is
-- installed and creates all objects needed for the embedded analytics experience:
--
--   1. Sample SaaS metrics data model (accounts, subscriptions, revenue, usage)
--   2. Semantic View for Cortex Analyst text-to-SQL
--   3. Cortex Agent wired to both the Semantic View and Qlik MCP server
--   4. Application roles and grants
--
-- The agent provides a unified natural-language interface over:
--   - Snowflake data (via Semantic View / Cortex Analyst)
--   - Qlik Cloud analytics (via MCP server connection)
--
-- =============================================================================

-- =============================================================================
-- Schema
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS core;
GRANT USAGE ON SCHEMA core TO APPLICATION ROLE app_user;

-- =============================================================================
-- Application Role
-- =============================================================================

CREATE APPLICATION ROLE IF NOT EXISTS app_user;

-- =============================================================================
-- Reference Registration Callback
-- =============================================================================

CREATE OR REPLACE PROCEDURE core.register_reference(ref_name STRING, operation STRING, ref_or_alias STRING)
    RETURNS STRING
    LANGUAGE SQL
AS
BEGIN
    CASE (operation)
        WHEN 'ADD' THEN
            SELECT SYSTEM$SET_REFERENCE(:ref_name, :ref_or_alias);
        WHEN 'REMOVE' THEN
            SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
        WHEN 'CLEAR' THEN
            SELECT SYSTEM$REMOVE_REFERENCE(:ref_name);
    END CASE;
    RETURN 'OK';
END;

GRANT USAGE ON PROCEDURE core.register_reference(STRING, STRING, STRING)
    TO APPLICATION ROLE app_user;

-- =============================================================================
-- Sample Data: Accounts
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.accounts (
    account_id      INT,
    company_name    VARCHAR(100),
    segment         VARCHAR(20),    -- Enterprise, Mid-Market, SMB
    region          VARCHAR(20),    -- NA, EMEA, APAC, LATAM
    industry        VARCHAR(30),
    signup_date     DATE,
    status          VARCHAR(15)     -- Active, Churned, Trial
);

INSERT OVERWRITE INTO core.accounts VALUES
(1,  'Acme Corp',           'Enterprise',  'NA',    'Technology',     '2023-01-15', 'Active'),
(2,  'GlobalTech Inc',      'Enterprise',  'EMEA',  'Technology',     '2023-02-01', 'Active'),
(3,  'DataDriven Ltd',      'Mid-Market',  'NA',    'Financial',      '2023-03-10', 'Active'),
(4,  'CloudFirst SaaS',     'Mid-Market',  'APAC',  'Technology',     '2023-04-22', 'Active'),
(5,  'RetailMax',           'Enterprise',  'NA',    'Retail',         '2023-01-08', 'Active'),
(6,  'HealthPlus',          'Mid-Market',  'EMEA',  'Healthcare',     '2023-05-15', 'Churned'),
(7,  'EduLearn Online',     'SMB',         'NA',    'Education',      '2023-06-01', 'Active'),
(8,  'FinServ Solutions',   'Enterprise',  'NA',    'Financial',      '2023-02-20', 'Active'),
(9,  'ManuTech Global',     'Mid-Market',  'APAC',  'Manufacturing',  '2023-07-12', 'Active'),
(10, 'MediaFlow',           'SMB',         'EMEA',  'Media',          '2023-08-03', 'Active'),
(11, 'LogiChain',           'Mid-Market',  'LATAM', 'Logistics',      '2023-03-28', 'Churned'),
(12, 'InsureTech Pro',      'Enterprise',  'NA',    'Financial',      '2023-01-30', 'Active'),
(13, 'GreenEnergy Co',      'SMB',         'EMEA',  'Energy',         '2023-09-15', 'Active'),
(14, 'TravelWise',          'SMB',         'APAC',  'Travel',         '2023-10-01', 'Trial'),
(15, 'BioPharm Research',   'Enterprise',  'NA',    'Healthcare',     '2023-04-10', 'Active'),
(16, 'SmartHome Inc',       'Mid-Market',  'NA',    'Technology',     '2023-05-22', 'Active'),
(17, 'FoodTech Delivery',   'SMB',         'LATAM', 'Retail',         '2023-11-08', 'Active'),
(18, 'CyberShield',         'Mid-Market',  'EMEA',  'Technology',     '2023-06-14', 'Active'),
(19, 'AutoDrive Systems',   'Enterprise',  'APAC',  'Manufacturing',  '2023-02-28', 'Active'),
(20, 'EcoWaste Solutions',  'SMB',         'NA',    'Energy',         '2023-12-01', 'Trial');

-- =============================================================================
-- Sample Data: Subscriptions
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.subscriptions (
    subscription_id INT,
    account_id      INT,
    plan_tier       VARCHAR(20),    -- Starter, Professional, Enterprise
    monthly_price   DECIMAL(10,2),
    start_date      DATE,
    end_date        DATE,           -- NULL if active
    status          VARCHAR(15)     -- Active, Cancelled, Upgraded
);

INSERT OVERWRITE INTO core.subscriptions VALUES
(101, 1,  'Enterprise',    4500.00, '2023-01-15', NULL,          'Active'),
(102, 2,  'Enterprise',    4500.00, '2023-02-01', NULL,          'Active'),
(103, 3,  'Professional',  1200.00, '2023-03-10', NULL,          'Active'),
(104, 4,  'Professional',  1200.00, '2023-04-22', NULL,          'Active'),
(105, 5,  'Enterprise',    6000.00, '2023-01-08', NULL,          'Active'),
(106, 6,  'Professional',  1200.00, '2023-05-15', '2024-02-15', 'Cancelled'),
(107, 7,  'Starter',        299.00, '2023-06-01', NULL,          'Active'),
(108, 8,  'Enterprise',    4500.00, '2023-02-20', NULL,          'Active'),
(109, 9,  'Professional',  1200.00, '2023-07-12', NULL,          'Active'),
(110, 10, 'Starter',        299.00, '2023-08-03', NULL,          'Active'),
(111, 11, 'Professional',  1200.00, '2023-03-28', '2024-01-28', 'Cancelled'),
(112, 12, 'Enterprise',    6000.00, '2023-01-30', NULL,          'Active'),
(113, 13, 'Starter',        299.00, '2023-09-15', NULL,          'Active'),
(114, 14, 'Starter',        149.00, '2023-10-01', NULL,          'Active'),
(115, 15, 'Enterprise',    4500.00, '2023-04-10', NULL,          'Active'),
(116, 16, 'Professional',  1500.00, '2023-05-22', NULL,          'Upgraded'),
(117, 17, 'Starter',        299.00, '2023-11-08', NULL,          'Active'),
(118, 18, 'Professional',  1200.00, '2023-06-14', NULL,          'Active'),
(119, 19, 'Enterprise',    6000.00, '2023-02-28', NULL,          'Active'),
(120, 20, 'Starter',        149.00, '2023-12-01', NULL,          'Active');

-- =============================================================================
-- Sample Data: Monthly Revenue
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.monthly_revenue (
    revenue_id      INT AUTOINCREMENT,
    account_id      INT,
    revenue_month   DATE,           -- First of month
    mrr             DECIMAL(10,2),  -- Monthly Recurring Revenue
    expansion_mrr   DECIMAL(10,2),  -- Upsell/cross-sell revenue
    contraction_mrr DECIMAL(10,2),  -- Downgrades
    churned_mrr     DECIMAL(10,2)   -- Lost revenue from churn
);

INSERT OVERWRITE INTO core.monthly_revenue
(account_id, revenue_month, mrr, expansion_mrr, contraction_mrr, churned_mrr)
VALUES
-- Q1 2024
(1,  '2024-01-01', 4500.00, 500.00,  0.00,    0.00),
(2,  '2024-01-01', 4500.00, 0.00,    0.00,    0.00),
(3,  '2024-01-01', 1200.00, 0.00,    0.00,    0.00),
(4,  '2024-01-01', 1200.00, 300.00,  0.00,    0.00),
(5,  '2024-01-01', 6000.00, 0.00,    0.00,    0.00),
(7,  '2024-01-01', 299.00,  0.00,    0.00,    0.00),
(8,  '2024-01-01', 4500.00, 0.00,    0.00,    0.00),
(9,  '2024-01-01', 1200.00, 0.00,    0.00,    0.00),
(10, '2024-01-01', 299.00,  0.00,    0.00,    0.00),
(12, '2024-01-01', 6000.00, 1000.00, 0.00,    0.00),
(13, '2024-01-01', 299.00,  0.00,    0.00,    0.00),
(15, '2024-01-01', 4500.00, 0.00,    0.00,    0.00),
(16, '2024-01-01', 1500.00, 300.00,  0.00,    0.00),
(17, '2024-01-01', 299.00,  0.00,    0.00,    0.00),
(18, '2024-01-01', 1200.00, 0.00,    0.00,    0.00),
(19, '2024-01-01', 6000.00, 0.00,    0.00,    0.00),
(20, '2024-01-01', 149.00,  0.00,    0.00,    0.00),
-- Q2 2024
(1,  '2024-04-01', 5000.00, 0.00,    0.00,    0.00),
(2,  '2024-04-01', 4500.00, 800.00,  0.00,    0.00),
(3,  '2024-04-01', 1200.00, 0.00,    200.00,  0.00),
(4,  '2024-04-01', 1500.00, 0.00,    0.00,    0.00),
(5,  '2024-04-01', 6000.00, 1500.00, 0.00,    0.00),
(7,  '2024-04-01', 299.00,  0.00,    0.00,    0.00),
(8,  '2024-04-01', 4500.00, 500.00,  0.00,    0.00),
(9,  '2024-04-01', 1200.00, 0.00,    0.00,    0.00),
(10, '2024-04-01', 299.00,  0.00,    0.00,    0.00),
(12, '2024-04-01', 7000.00, 0.00,    0.00,    0.00),
(13, '2024-04-01', 299.00,  0.00,    0.00,    0.00),
(15, '2024-04-01', 4500.00, 1000.00, 0.00,    0.00),
(16, '2024-04-01', 1800.00, 0.00,    0.00,    0.00),
(17, '2024-04-01', 299.00,  0.00,    0.00,    0.00),
(18, '2024-04-01', 1200.00, 0.00,    0.00,    0.00),
(19, '2024-04-01', 6000.00, 500.00,  0.00,    0.00),
(20, '2024-04-01', 149.00,  0.00,    0.00,    0.00),
-- Churned accounts (partial quarter before leaving)
(6,  '2024-01-01', 1200.00, 0.00,    0.00,    1200.00),
(11, '2024-01-01', 1200.00, 0.00,    0.00,    1200.00);

-- =============================================================================
-- Sample Data: Usage Events (aggregated monthly)
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.usage_events (
    account_id      INT,
    event_month     DATE,
    logins          INT,
    api_calls       INT,
    reports_created INT,
    data_gb_scanned DECIMAL(8,2)
);

INSERT OVERWRITE INTO core.usage_events VALUES
(1,  '2024-01-01', 450, 12000, 35, 120.50),
(2,  '2024-01-01', 380, 9500,  28, 95.20),
(3,  '2024-01-01', 120, 3200,  12, 45.00),
(4,  '2024-01-01', 95,  2800,  15, 38.70),
(5,  '2024-01-01', 520, 15000, 42, 200.00),
(7,  '2024-01-01', 25,  400,   3,  5.20),
(8,  '2024-01-01', 310, 8900,  22, 88.50),
(9,  '2024-01-01', 85,  2100,  8,  32.10),
(10, '2024-01-01', 15,  200,   2,  3.80),
(12, '2024-01-01', 480, 14000, 38, 175.30),
(13, '2024-01-01', 18,  350,   4,  4.50),
(15, '2024-01-01', 400, 11000, 30, 145.00),
(16, '2024-01-01', 150, 4200,  18, 52.30),
(17, '2024-01-01', 20,  500,   2,  6.10),
(18, '2024-01-01', 110, 3000,  10, 40.00),
(19, '2024-01-01', 350, 9800,  25, 130.00),
(20, '2024-01-01', 8,   100,   1,  2.00),
-- Q2 usage (showing engagement trends)
(1,  '2024-04-01', 480, 13500, 40, 135.00),
(2,  '2024-04-01', 420, 11000, 32, 110.50),
(3,  '2024-04-01', 100, 2800,  10, 40.00),
(4,  '2024-04-01', 130, 3500,  20, 48.90),
(5,  '2024-04-01', 550, 16500, 48, 220.00),
(7,  '2024-04-01', 30,  500,   4,  6.00),
(8,  '2024-04-01', 340, 9500,  25, 95.00),
(9,  '2024-04-01', 75,  1800,  6,  28.00),
(10, '2024-04-01', 12,  150,   1,  3.00),
(12, '2024-04-01', 510, 15000, 42, 185.00),
(15, '2024-04-01', 430, 12000, 35, 155.00),
(16, '2024-04-01', 180, 5000,  22, 60.00),
(18, '2024-04-01', 125, 3400,  12, 44.00),
(19, '2024-04-01', 380, 10500, 28, 140.00);

-- =============================================================================
-- Grants on tables
-- =============================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA core TO APPLICATION ROLE app_user;

-- =============================================================================
-- Semantic View
-- =============================================================================
-- The semantic view is created from the YAML spec in semantic/saas_metrics.yaml.
-- In a production Native App, this would reference a staged file. For this
-- example, we inline the semantic view creation.
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW core.saas_metrics_sv
  COMMENT = 'SaaS metrics semantic model for Cortex Analyst'
AS
  -- Base tables
  TABLES (
    core.accounts AS accounts
      WITH SYNONYMS = ('customers', 'clients', 'companies')
      WITH COLUMNS (
        account_id WITH SYNONYMS = ('customer_id', 'client_id'),
        company_name WITH SYNONYMS = ('customer_name', 'account_name'),
        segment WITH SYNONYMS = ('tier', 'customer_segment'),
        region WITH SYNONYMS = ('geo', 'geography'),
        industry WITH SYNONYMS = ('vertical', 'sector'),
        signup_date WITH SYNONYMS = ('registration_date', 'created_date'),
        status WITH SYNONYMS = ('account_status')
      ),
    core.subscriptions AS subscriptions
      WITH SYNONYMS = ('plans', 'contracts')
      WITH COLUMNS (
        subscription_id,
        account_id,
        plan_tier WITH SYNONYMS = ('plan', 'pricing_tier', 'plan_name'),
        monthly_price WITH SYNONYMS = ('price', 'subscription_price'),
        start_date WITH SYNONYMS = ('subscription_start'),
        end_date WITH SYNONYMS = ('subscription_end', 'cancellation_date'),
        status WITH SYNONYMS = ('subscription_status')
      ),
    core.monthly_revenue AS monthly_revenue
      WITH SYNONYMS = ('revenue', 'mrr_data', 'financials')
      WITH COLUMNS (
        account_id,
        revenue_month WITH SYNONYMS = ('month', 'period', 'reporting_month'),
        mrr WITH SYNONYMS = ('monthly_recurring_revenue', 'recurring_revenue'),
        expansion_mrr WITH SYNONYMS = ('upsell', 'expansion_revenue', 'growth_revenue'),
        contraction_mrr WITH SYNONYMS = ('downgrades', 'contraction'),
        churned_mrr WITH SYNONYMS = ('churn_revenue', 'lost_revenue')
      ),
    core.usage_events AS usage_events
      WITH SYNONYMS = ('usage', 'activity', 'engagement')
      WITH COLUMNS (
        account_id,
        event_month WITH SYNONYMS = ('month', 'usage_month'),
        logins WITH SYNONYMS = ('login_count', 'sessions'),
        api_calls WITH SYNONYMS = ('api_usage', 'api_requests'),
        reports_created WITH SYNONYMS = ('reports', 'report_count'),
        data_gb_scanned WITH SYNONYMS = ('data_scanned', 'gb_processed')
      )
  )
  -- Relationships
  RELATIONSHIPS (
    accounts (account_id) REFERENCES subscriptions (account_id),
    accounts (account_id) REFERENCES monthly_revenue (account_id),
    accounts (account_id) REFERENCES usage_events (account_id)
  )
  -- Metrics
  METRICS (
    total_mrr AS SUM(monthly_revenue.mrr)
      WITH SYNONYMS = ('total monthly recurring revenue', 'aggregate mrr')
      WITH DESCRIPTION = 'Sum of all monthly recurring revenue across accounts',
    total_arr AS SUM(monthly_revenue.mrr) * 12
      WITH SYNONYMS = ('annual recurring revenue', 'arr')
      WITH DESCRIPTION = 'Annualized recurring revenue (MRR * 12)',
    total_expansion AS SUM(monthly_revenue.expansion_mrr)
      WITH SYNONYMS = ('expansion revenue', 'upsell revenue')
      WITH DESCRIPTION = 'Revenue gained from upsells and cross-sells',
    total_contraction AS SUM(monthly_revenue.contraction_mrr)
      WITH SYNONYMS = ('contraction revenue', 'downgrade revenue')
      WITH DESCRIPTION = 'Revenue lost from plan downgrades',
    total_churn AS SUM(monthly_revenue.churned_mrr)
      WITH SYNONYMS = ('churned revenue', 'lost revenue')
      WITH DESCRIPTION = 'Revenue lost from account cancellations',
    net_revenue_retention AS
      (SUM(monthly_revenue.mrr) + SUM(monthly_revenue.expansion_mrr)
       - SUM(monthly_revenue.contraction_mrr) - SUM(monthly_revenue.churned_mrr))
      / NULLIF(SUM(monthly_revenue.mrr), 0) * 100
      WITH SYNONYMS = ('NRR', 'net retention', 'dollar retention')
      WITH DESCRIPTION = 'Net revenue retention rate as a percentage',
    avg_mrr_per_account AS AVG(monthly_revenue.mrr)
      WITH SYNONYMS = ('ARPA', 'average revenue per account')
      WITH DESCRIPTION = 'Average MRR across all paying accounts',
    active_accounts AS COUNT(DISTINCT CASE WHEN accounts.status = 'Active' THEN accounts.account_id END)
      WITH SYNONYMS = ('paying customers', 'active customers')
      WITH DESCRIPTION = 'Count of accounts with Active status',
    churned_accounts AS COUNT(DISTINCT CASE WHEN accounts.status = 'Churned' THEN accounts.account_id END)
      WITH SYNONYMS = ('lost customers', 'cancelled accounts')
      WITH DESCRIPTION = 'Count of accounts that have churned',
    avg_logins AS AVG(usage_events.logins)
      WITH SYNONYMS = ('average logins', 'login frequency')
      WITH DESCRIPTION = 'Average monthly login count per account',
    total_api_calls AS SUM(usage_events.api_calls)
      WITH SYNONYMS = ('api volume', 'total api usage')
      WITH DESCRIPTION = 'Total API calls across all accounts'
  );

GRANT SELECT ON SEMANTIC VIEW core.saas_metrics_sv TO APPLICATION ROLE app_user;

-- =============================================================================
-- Cortex Agent
-- =============================================================================
-- The agent has two tool sources:
--   1. SaaSMetrics (Cortex Analyst) - queries the Semantic View for Snowflake data
--   2. Qlik MCP server - accesses Qlik Cloud apps, dashboards, and visualizations
--
-- The Qlik MCP server reference is parameterized. The consumer provides their
-- own MCP server name via the consumer_setup.sql script, which alters the agent
-- to include their server. Initially, the agent is created with only the
-- Semantic View tool.
-- =============================================================================

CREATE OR REPLACE AGENT core.analytics_agent
    FROM SPECIFICATION $$
models:
  orchestration: auto

instructions:
  response: |
    You are an embedded analytics assistant for SaaS companies. You have access to:

    1. **SaaS Metrics (Snowflake)** - Query subscription data, revenue metrics (MRR, ARR,
       churn, NRR, expansion), account details, and usage analytics directly from Snowflake
       via Cortex Analyst.

    2. **Qlik Cloud Analytics** (if connected) - Explore Qlik applications, dashboards,
       master items, create visualizations, manage bookmarks, and investigate data using
       Qlik's associative engine.

    ## When to use each tool:

    **Use SaaS Metrics (Cortex Analyst) when:**
    - User asks about specific metrics: MRR, ARR, churn, retention, revenue
    - User wants data by segment, region, plan tier, time period
    - User needs ad-hoc analysis or custom aggregations
    - User asks "what is..." or "how much..." type questions about the data

    **Use Qlik MCP tools when:**
    - User asks about existing dashboards or visualizations
    - User wants to create/modify charts or sheets
    - User asks to explore apps or find specific Qlik content
    - User wants governed master items (dimensions/measures)
    - User asks "show me..." or "create a chart..." type requests

    **Use both when:**
    - User wants to analyze data AND visualize it
    - User asks a metric question and wants a dashboard created
    - User needs to compare Snowflake data with Qlik dashboard findings

    ## Response guidelines:
    - Be concise and data-driven
    - When presenting metrics, include the time period and any filters applied
    - When creating Qlik visualizations, confirm the app ID with the user first
    - Format numbers clearly (e.g., $45,000 MRR, 95.2% NRR)

  orchestration: |
    Route questions about data metrics, trends, and analysis to the SaaSMetrics tool.
    Route questions about dashboards, apps, charts, and visualizations to Qlik MCP tools.
    For hybrid requests, query the data first, then create visualizations.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "SaaSMetrics"
      description: "Query SaaS subscription metrics including MRR, ARR, churn rate, net revenue retention, expansion revenue, account details, usage patterns, and customer segments from Snowflake."

tool_resources:
  SaaSMetrics:
    semantic_view: "core.saas_metrics_sv"
$$;

GRANT USAGE ON AGENT core.analytics_agent TO APPLICATION ROLE app_user;
