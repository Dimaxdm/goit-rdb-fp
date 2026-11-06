-- =============================================================================
-- Final Project — Infectious Diseases: SQL Data Engineering with PostgreSQL
-- -----------------------------------------------------------------------------
-- All transformations from final_project.ipynb as a single PostgreSQL script.
--
-- Run from the repository root with psql:
--     psql "postgresql://postgres:postgres@localhost:5432/postgres" -f query_solution.sql
--
-- The data is loaded with the psql meta-command \copy from data/infectious_cases.csv
-- (the same file the notebook reads from GitHub).
-- =============================================================================

\set ON_ERROR_STOP on

-- =============================================================================
-- 1. LOAD THE DATA
-- =============================================================================

-- 1.1 Create schema and set it as the default schema
CREATE SCHEMA IF NOT EXISTS pandemic;
SET search_path TO pandemic;
ALTER DATABASE postgres SET search_path TO pandemic, public;
SHOW search_path;

-- 1.2 Create the raw table and import infectious_cases.csv
--     Empty CSV cells are loaded as NULL.
DROP TABLE IF EXISTS infectious_cases_normalized;
DROP TABLE IF EXISTS entities;
DROP TABLE IF EXISTS infectious_cases;

CREATE TABLE infectious_cases (
    entity               TEXT,
    code                 TEXT,
    year                 BIGINT,
    number_yaws          DOUBLE PRECISION,
    polio_cases          DOUBLE PRECISION,
    cases_guinea_worm    DOUBLE PRECISION,
    number_rabies        DOUBLE PRECISION,
    number_malaria       DOUBLE PRECISION,
    number_hiv           DOUBLE PRECISION,
    number_tuberculosis  DOUBLE PRECISION,
    number_smallpox      DOUBLE PRECISION,
    number_cholera_cases DOUBLE PRECISION
);

\copy infectious_cases FROM 'data/infectious_cases.csv' WITH (FORMAT csv, HEADER true)

-- 1.3 Examine the data
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'pandemic' AND table_name = 'infectious_cases'
ORDER BY ordinal_position;

SELECT * FROM infectious_cases LIMIT 10;

SELECT
    COUNT(*)                             AS total_rows,
    COUNT(DISTINCT entity)               AS unique_entities,
    COUNT(DISTINCT (entity, code))       AS unique_entity_code_pairs,
    COUNT(*) FILTER (WHERE code IS NULL) AS rows_without_code,
    MIN(year)                            AS min_year,
    MAX(year)                            AS max_year,
    COUNT(number_rabies)                 AS rabies_non_null
FROM infectious_cases;

-- =============================================================================
-- 2. NORMALIZE infectious_cases TO THIRD NORMAL FORM (3NF)
--    code depends only on entity, so (entity, code) moves to its own table and
--    the statistics table references it by entity_id.
-- =============================================================================

-- 2.1 Table with unique combinations of entity and code
CREATE TABLE entities (
    id     SERIAL PRIMARY KEY,
    entity VARCHAR(255) NOT NULL,
    code   VARCHAR(20),
    CONSTRAINT uq_entity_code UNIQUE (entity, code)
);

INSERT INTO entities (entity, code)
SELECT DISTINCT entity, code
FROM infectious_cases
ORDER BY entity;

-- 2.2 Table with the disease statistics, entity/code replaced by entity_id
CREATE TABLE infectious_cases_normalized (
    id                   SERIAL PRIMARY KEY,
    entity_id            INT NOT NULL REFERENCES entities(id),
    year                 INT NOT NULL,
    number_yaws          DOUBLE PRECISION,
    polio_cases          DOUBLE PRECISION,
    cases_guinea_worm    DOUBLE PRECISION,
    number_rabies        DOUBLE PRECISION,
    number_malaria       DOUBLE PRECISION,
    number_hiv           DOUBLE PRECISION,
    number_tuberculosis  DOUBLE PRECISION,
    number_smallpox      DOUBLE PRECISION,
    number_cholera_cases DOUBLE PRECISION,
    CONSTRAINT uq_entity_year UNIQUE (entity_id, year)
);

-- code is NULL for regions, so the join uses IS NOT DISTINCT FROM (NULL-safe equality)
INSERT INTO infectious_cases_normalized (
    entity_id, year, number_yaws, polio_cases, cases_guinea_worm, number_rabies,
    number_malaria, number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases
)
SELECT
    e.id, ic.year, ic.number_yaws, ic.polio_cases, ic.cases_guinea_worm, ic.number_rabies,
    ic.number_malaria, ic.number_hiv, ic.number_tuberculosis, ic.number_smallpox, ic.number_cholera_cases
FROM infectious_cases ic
JOIN entities e
  ON e.entity = ic.entity
 AND e.code IS NOT DISTINCT FROM ic.code
ORDER BY e.id, ic.year;

-- 2.3 Verify the normalization (row counts must match the original table)
SELECT 'infectious_cases (original)'  AS table_name, COUNT(*) AS row_count FROM infectious_cases
UNION ALL
SELECT 'entities',                    COUNT(*) FROM entities
UNION ALL
SELECT 'infectious_cases_normalized', COUNT(*) FROM infectious_cases_normalized;

SELECT * FROM entities LIMIT 10;
SELECT * FROM infectious_cases_normalized LIMIT 10;

-- =============================================================================
-- 3. ANALYZE number_rabies
--    AVG / MIN / MAX / SUM per entity, sorted by AVG desc, top 10.
-- =============================================================================

SELECT
    e.id                                    AS entity_id,
    e.entity,
    e.code,
    ROUND(AVG(n.number_rabies)::NUMERIC, 2) AS avg_rabies,
    ROUND(MIN(n.number_rabies)::NUMERIC, 2) AS min_rabies,
    ROUND(MAX(n.number_rabies)::NUMERIC, 2) AS max_rabies,
    ROUND(SUM(n.number_rabies)::NUMERIC, 2) AS sum_rabies
FROM infectious_cases_normalized n
JOIN entities e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
GROUP BY e.id, e.entity, e.code
ORDER BY avg_rabies DESC
LIMIT 10;

-- =============================================================================
-- 4. DIFFERENCE IN YEARS USING BUILT-IN SQL FUNCTIONS
-- =============================================================================

SELECT
    e.entity,
    n.year,
    MAKE_DATE(n.year, 1, 1)                                             AS year_start_date,
    CURRENT_DATE                                                        AS current_date,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(n.year, 1, 1)))::INT  AS year_difference
FROM infectious_cases_normalized n
JOIN entities e ON e.id = n.entity_id
ORDER BY n.id
LIMIT 10;

-- =============================================================================
-- 5. CUSTOM SQL FUNCTIONS
-- =============================================================================

-- 5.1 Function 1: difference in years between <year>-01-01 and the current date
CREATE OR REPLACE FUNCTION fn_year_difference(p_year INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INT;
$$;

-- Example: 1996 -> 1996-01-01 -> years until today
SELECT 1996                     AS input_year,
       MAKE_DATE(1996, 1, 1)    AS year_start_date,
       CURRENT_DATE             AS current_date,
       fn_year_difference(1996) AS year_difference;

-- Using the function on the table
SELECT
    e.entity,
    n.year,
    MAKE_DATE(n.year, 1, 1)    AS year_start_date,
    CURRENT_DATE               AS current_date,
    fn_year_difference(n.year) AS year_difference
FROM infectious_cases_normalized n
JOIN entities e ON e.id = n.entity_id
ORDER BY n.id
LIMIT 10;

-- Check: 0 mismatches = same result as the built-in expression from section 4
SELECT COUNT(*) AS mismatches
FROM infectious_cases_normalized
WHERE fn_year_difference(year)
   <> EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INT;

-- 5.2 Function 2: average number of cases per period (yearly cases / divisor)
--     12 = per month, 4 = per quarter, 2 = per half-year; divisor 0 -> NULL
CREATE OR REPLACE FUNCTION fn_avg_cases_per_period(p_cases NUMERIC, p_divisor INT)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT ROUND(p_cases / NULLIF(p_divisor, 0), 2);
$$;

-- Using the function only on records where the case count is numeric (NOT NULL)
SELECT
    e.entity,
    e.code,
    n.year,
    ROUND(n.number_rabies::NUMERIC, 2)                    AS rabies_per_year,
    fn_avg_cases_per_period(n.number_rabies::NUMERIC, 12) AS avg_per_month,
    fn_avg_cases_per_period(n.number_rabies::NUMERIC, 4)  AS avg_per_quarter,
    fn_avg_cases_per_period(n.number_rabies::NUMERIC, 2)  AS avg_per_half_year
FROM infectious_cases_normalized n
JOIN entities e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
ORDER BY n.id
LIMIT 10;
