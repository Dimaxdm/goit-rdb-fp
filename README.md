# Final Project — Infectious Diseases Data Engineering with PostgreSQL

An end-to-end SQL project that loads a dataset of infectious disease statistics into PostgreSQL, normalizes it to Third Normal Form (3NF), and analyzes it with aggregate queries, built-in date functions and user-defined SQL functions.

[![GitHub](https://img.shields.io/badge/GitHub-final__project__relational__db.ipynb-blue?logo=github)](final_project_relational_db.ipynb)  
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](final_project_relational_db.sql) — Standalone PostgreSQL script containing all data transformations.  
[![Open in Google Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/drive/1dW_JlmwGj2UhciEmPZlS86sTte9DB-s8?usp=sharing) — [Open notebook in Google Colab](https://colab.research.google.com/drive/1dW_JlmwGj2UhciEmPZlS86sTte9DB-s8?usp=sharing)

---

## Dataset

`infectious_cases.csv` — 10,521 rows × 12 columns, one row per entity (country or aggregated region) per year, 1920–2023.

| Column | Description |
|---|---|
| `Entity` | Country or region name |
| `Code` | ISO-3 country code (empty for aggregated regions such as *Africa* or *G20*) |
| `Year` | Year of observation |
| `Number_yaws`, `polio_cases`, `cases_guinea_worm`, `Number_rabies`, `Number_malaria`, `Number_hiv`, `Number_tuberculosis`, `Number_smallpox`, `Number_cholera_cases` | Number of cases per disease (empty if not recorded) |

## Tech stack

- **PostgreSQL** — database engine (installed inside Colab)
- **Python / pandas + SQLAlchemy** — CSV read directly from GitHub (`GITREPO` raw link) and imported via `DataFrame.to_sql()`
- **ipython-sql** — `%%sql` magic to run SQL directly in notebook cells
- **psql** — runs `final_project_relational_db.sql` end-to-end (data loaded with `\copy`)

## Project tasks and solution

Screenshots under each task show the output of the corresponding section of `final_project_relational_db.sql`; all images are stored in the [`screenshots/`](screenshots) folder.

The same solution is provided in two forms: the notebook (with executed results) and `final_project_relational_db.sql` (the SQL only, in the same order and with the same section numbers). The only difference is the import in step 1: the notebook reads the CSV from GitHub with pandas, the script loads `data/infectious_cases.csv` with psql's `\copy`.

### 1. Load the data
- `CREATE SCHEMA IF NOT EXISTS pandemic;`
- `SET search_path TO pandemic;` (plus `ALTER DATABASE ... SET search_path` so new connections use it too)
- **Notebook:** CSV read with `pd.read_csv(GITREPO)` from the raw GitHub link (pinned to a commit) and imported into `pandemic.infectious_cases` with pandas/SQLAlchemy; column names lower-cased, empty cells stored as `NULL`.
- **SQL script:** `CREATE TABLE infectious_cases (...)` with explicit types, then `\copy infectious_cases FROM 'data/infectious_cases.csv' WITH (FORMAT csv, HEADER true)`.
- Data profiled: column types, sample rows, row/entity counts, year range.


![Examine imported data — first 10 rows of pandemic.infectious_cases](screenshots/01_01_examine_imported_data.png)

![Examine imported data — 10,521 rows, 245 entities, 1,128 rows without code, years 1920–2023](screenshots/01_02_examine_imported_data.png)

### 2. Normalization to 3NF
`code` depends only on `entity`, not on the full key `(entity, year)`, so the table is split into:

| Table | Content | Keys |
|---|---|---|
| `entities` | Unique `(entity, code)` pairs — 245 rows | `id` PK, `UNIQUE(entity, code)` |
| `infectious_cases_normalized` | Yearly disease statistics — 10,521 rows | `id` PK, `entity_id` FK → `entities.id`, `UNIQUE(entity_id, year)` |

The join uses `IS NOT DISTINCT FROM` so that regions with a `NULL` code are matched correctly. Row counts are verified after loading.


![Verify normalization — row counts: original 10,521, entities 245, normalized 10,521](screenshots/02_01_verify_the_normalization.png)

![Verify normalization — first rows of the entities table](screenshots/02_02_verify_the_normalization.png)

![Verify normalization — first rows of infectious_cases_normalized with entity_id](screenshots/02_03_verify_the_normalization.png)

### 3. Analysis of `number_rabies`
AVG, MIN, MAX and SUM per entity (excluding `NULL`s), sorted by average descending, top 10 rows.


![Top 10 entities by average number_rabies](screenshots/03_01_analyze_number_rabies.png)

### 4. Year difference with built-in functions
`MAKE_DATE(year, 1, 1)`, `CURRENT_DATE` and `EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))` produce the start-of-year date, the current date and the number of full years between them.


![Year difference using built-in SQL functions](screenshots/04_01_difference_in_years_using_built-in_sql_functions.png)

### 5. Custom SQL functions
| Function | Purpose | Example |
|---|---|---|
| `fn_year_difference(p_year INT) → INT` | Full years between `p_year-01-01` and today | `fn_year_difference(1996)` |
| `fn_avg_cases_per_period(p_cases NUMERIC, p_divisor INT) → NUMERIC` | Yearly cases ÷ divisor (division by zero → `NULL`) | divisor `12` = month, `4` = quarter, `2` = half-year |

Both functions are used in queries on the normalized table. The first is verified to match the built-in calculation for all rows (0 mismatches); the second is applied only to rows where `number_rabies` is numeric (`IS NOT NULL`).


![fn_year_difference used on the table, same output as the built-in calculation](screenshots/05_01_check_if_builtin_function_matches_created_fuction.png)

![Validation: 0 mismatches between fn_year_difference and the built-in expression](screenshots/05_02_validation_of_mismatches_cases_of_the_created_fuction.png)

![fn_avg_cases_per_period with divisors 12, 4 and 2 on numeric records](screenshots/05_03_function_on_records_where_the_case_count_is_numeric.png)

## Repository structure

```
.
├── final_project_relational_db.ipynb    # Main notebook with all SQL and results
├── final_project_relational_db.sql      # Standalone SQL script with all transformations
├── data/
│   └── infectious_cases.csv             # Source dataset (loaded by the notebook via raw GitHub URL)
├── screenshots/                         # Execution results of query_solution.sql sections (01_* … 05_*)
├── requirements.txt                     # Python dependencies
└── README.md                            # Project documentation
```

## How to run

### Google Colab (recommended)
1. Open the notebook in Colab.
2. Run all cells. The first cell installs and starts PostgreSQL and installs the Python packages.
3. The dataset is downloaded automatically from GitHub, no manual upload needed.

### Locally
Requires a running PostgreSQL server with user `postgres` / password `postgres` on `localhost:5432`.

```bash
pip install -r requirements.txt
jupyter notebook final_project_relational_db.ipynb
```
An internet connection is needed to load the dataset from GitHub.

### SQL script only (psql)
Run from the repository root so the relative path `data/infectious_cases.csv` resolves:

```bash
psql "postgresql://postgres:postgres@localhost:5432/postgres" -f query_solution.sql
```
The script stops on the first error (`ON_ERROR_STOP`) and can be re-run: it drops and recreates its tables, and uses `CREATE OR REPLACE` for the functions.

In Colab, after cloning the repository:
```python
!git clone https://github.com/Dimaxdm/goit-rdb-fp.git
%cd goit-rdb-fp
!psql "postgresql://postgres:postgres@localhost:5432/postgres" -f final_project_relational_db.sql
```

## Notes
- `fn_year_difference` and Section 4 use `CURRENT_DATE`, so their outputs change depending on the day the notebook or script is run.
- The top of the rabies ranking is dominated by aggregated regions (e.g. *World*, *G20*), which is expected because they sum many countries; filtering on `code IS NOT NULL` ranks individual countries only.
