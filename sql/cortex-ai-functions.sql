-- =============================================================================
-- Cortex AI Functions Demo
-- =============================================================================
--
-- This script demonstrates Snowflake Cortex AI functions using a sample
-- product reviews dataset. Each section is independent and can be run
-- separately.
--
-- Functions covered:
--   1. COMPLETE     - Generate text responses using LLMs
--   2. SUMMARIZE    - Summarize long-form text
--   3. SENTIMENT    - Score text sentiment (-1 to 1)
--   4. TRANSLATE    - Translate text between languages
--   5. EXTRACT_ANSWER - Extract specific answers from text
--
-- Prerequisites:
--   - Snowflake account with Cortex AI enabled
--   - A role with USAGE on a warehouse
--   - No external dependencies or integrations required
--
-- Usage:
--   Run the entire script in a Snowflake worksheet or execute sections
--   individually. The sample data uses a temporary table that is
--   automatically cleaned up when the session ends.
--
-- =============================================================================

-- =============================================================================
-- Step 0: Configuration
-- =============================================================================

SET MODEL = 'llama3.1-8b';  -- LLM model for COMPLETE (see docs for options)
SET WAREHOUSE = 'COMPUTE_WH';  -- Warehouse to use

USE WAREHOUSE IDENTIFIER($WAREHOUSE);

-- =============================================================================
-- Step 1: Create Sample Data
-- =============================================================================
-- A temporary table of product reviews for demonstration purposes.
-- This is automatically dropped when the session ends.
-- =============================================================================

CREATE OR REPLACE TEMPORARY TABLE product_reviews (
    review_id   INT,
    product     VARCHAR,
    reviewer    VARCHAR,
    rating      INT,
    review_text VARCHAR,
    language    VARCHAR
) AS
SELECT * FROM VALUES
(1, 'Wireless Headphones', 'Alice',  5, 'These headphones are absolutely fantastic! The noise cancellation is superb, battery lasts all day, and the sound quality is crystal clear. Best purchase I have made this year. Comfortable enough to wear during long flights without any ear fatigue.', 'en'),
(2, 'Smart Watch',         'Bob',    2, 'Disappointed with the battery life. It barely lasts a full day with normal use. The fitness tracking is inaccurate compared to my old device, and the screen is hard to read in sunlight. The app crashes frequently on my phone.', 'en'),
(3, 'Standing Desk',       'Carol',  4, 'Solid build quality and smooth height adjustment. Assembly took about 45 minutes with the included tools. The cable management tray is a nice touch. Only downside is it wobbles slightly at maximum height when typing aggressively.', 'en'),
(4, 'Mechanical Keyboard', 'David',  5, 'The tactile feedback is perfect for both coding and gaming. Cherry MX Brown switches provide a satisfying feel without being too loud for an office environment. The RGB lighting has tons of customization options. Build quality is exceptional with the aluminum frame.', 'en'),
(5, 'USB-C Hub',           'Eve',    1, 'Stopped working after two weeks. The HDMI port flickers constantly and the USB ports disconnect randomly. Customer support was unhelpful and the return process took over a month. Complete waste of money.', 'en'),
(6, 'Webcam',              'Frank',  3, 'Average quality for the price. Video is acceptable for meetings but noticeably grainy in low light. The built-in microphone picks up too much background noise. Auto-focus works well though and setup was plug-and-play.', 'en'),
(7, 'Monitor',             'Grace',  5, 'Incredible color accuracy out of the box. The 4K resolution makes text razor sharp and the 144Hz refresh rate is butter smooth for gaming. The USB-C port delivers 90W of power to my laptop, so one cable does everything. Worth every penny.', 'en'),
(8, 'Ergonomic Mouse',     'Hector', 4, 'Took a few days to adjust to the vertical grip but now my wrist pain is gone. The sensor is precise and the silent clicks are great for shared workspaces. Battery lasts about two months on a single charge. Wish it had more programmable buttons.', 'en'),
(9, 'Portable Charger',    'Iris',   2, 'Much heavier than expected and charges devices slowly. The capacity indicator is inaccurate - it shows full but dies quickly. Build quality feels cheap and the charging cable that comes with it broke within a week.', 'en'),
(10, 'Laptop Stand',       'Jack',   4, 'Simple but effective. Raises my laptop to the perfect eye level and improves airflow for cooling. Folds flat for travel. The aluminum finish matches my setup well. Non-slip pads keep everything stable.', 'en')
;

SELECT '>>> Sample data created: ' || COUNT(*) || ' product reviews' AS status
FROM product_reviews;

-- =============================================================================
-- Step 2: SENTIMENT - Score Review Sentiment
-- =============================================================================
-- Returns a value between -1 (very negative) and 1 (very positive).
-- Useful for batch classification of customer feedback.
-- =============================================================================

SELECT
    review_id,
    product,
    rating,
    SNOWFLAKE.CORTEX.SENTIMENT(review_text) AS sentiment_score,
    CASE
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(review_text) > 0.3 THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(review_text) < -0.3 THEN 'Negative'
        ELSE 'Neutral'
    END AS sentiment_label
FROM product_reviews
ORDER BY sentiment_score DESC;

-- =============================================================================
-- Step 3: SUMMARIZE - Condense Long Text
-- =============================================================================
-- Generates a concise summary of the input text.
-- Useful for creating review snippets or executive summaries.
-- =============================================================================

SELECT
    review_id,
    product,
    SNOWFLAKE.CORTEX.SUMMARIZE(review_text) AS summary
FROM product_reviews
WHERE LENGTH(review_text) > 150
LIMIT 5;

-- =============================================================================
-- Step 4: COMPLETE - Generate Text with an LLM
-- =============================================================================
-- Send a prompt to an LLM and get a generated response.
-- Useful for classification, generation, reformatting, and more.
-- =============================================================================

-- 4a. Categorize reviews by topic
SELECT
    review_id,
    product,
    SNOWFLAKE.CORTEX.COMPLETE(
        $MODEL,
        'Categorize this product review into exactly one of these categories: '
        || 'Build Quality, Performance, Battery, Comfort, Value. '
        || 'Reply with only the category name. Review: ' || review_text
    ) AS category
FROM product_reviews
LIMIT 5;

-- 4b. Generate a one-line tagline for a product based on its reviews
SELECT
    product,
    SNOWFLAKE.CORTEX.COMPLETE(
        $MODEL,
        'Based on this customer review, write a short one-sentence marketing '
        || 'tagline for the product. Review: ' || review_text
    ) AS tagline
FROM product_reviews
WHERE rating >= 4
LIMIT 3;

-- =============================================================================
-- Step 5: TRANSLATE - Translate Text Between Languages
-- =============================================================================
-- Translates text from one language to another.
-- Supports many language pairs.
-- =============================================================================

SELECT
    review_id,
    product,
    review_text AS original_english,
    SNOWFLAKE.CORTEX.TRANSLATE(review_text, 'en', 'fr') AS french,
    SNOWFLAKE.CORTEX.TRANSLATE(review_text, 'en', 'es') AS spanish
FROM product_reviews
WHERE review_id IN (1, 5)
ORDER BY review_id;

-- =============================================================================
-- Step 6: EXTRACT_ANSWER - Question Answering Over Text
-- =============================================================================
-- Given a text and a question, extracts the most relevant answer.
-- Useful for structured extraction from unstructured reviews.
-- =============================================================================

SELECT
    review_id,
    product,
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        review_text,
        'What is the main complaint or negative aspect?'
    ) AS main_complaint
FROM product_reviews
WHERE rating <= 3;

SELECT
    review_id,
    product,
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        review_text,
        'What specific feature does the reviewer like most?'
    ) AS favorite_feature
FROM product_reviews
WHERE rating >= 4;

-- =============================================================================
-- Step 7: Combining Functions - Sentiment-Driven Summary Pipeline
-- =============================================================================
-- A practical pattern: filter negative reviews, summarize them, and
-- extract the core issue for a support team dashboard.
-- =============================================================================

SELECT
    product,
    rating,
    SNOWFLAKE.CORTEX.SENTIMENT(review_text) AS sentiment,
    SNOWFLAKE.CORTEX.SUMMARIZE(review_text) AS summary,
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        review_text,
        'What should the company fix or improve?'
    ) AS actionable_feedback
FROM product_reviews
WHERE rating <= 2
ORDER BY sentiment ASC;
