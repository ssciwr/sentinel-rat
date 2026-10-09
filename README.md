# Sentinel Rat

Work in progress...

## Overview

Orchestration repository for the SENTINEL-RAT project.

General purpose: Rodent and predator (peacock / snake) detection from RGB and thermal cameras for leptospirosis risk in Sri Lanka.

## Version

| Version | Date | Notes |
|---------|------|------|
| 0.0.1 | 2026-07-30 | Initial version with scaffolded code for all components. |

## Developers
- Tuyen Le, ssc@iwr.uni-heidelberg.de

## Components

- `database` — PostgreSQL 17 with PostGIS extension. Located in the same repository with `dashboard`.
- `ml-pipeline` — FastAPI microservice for animal detection and species classification. Located in [sentinel-rat-ml-pipeline](https://github.com/ssciwr/sentinel-rat-ml-pipeline) repository.
- `pipeline` — Orchestration service for processing images and storing results in the database. Located in [sentinel-rat-pipeline](https://github.com/ssciwr/sentinel-rat-pipeline) repository.
- `dashboard` — R Shiny app for displaying analysis results. Located in [sentinel-rat-dashboard](https://github.com/ssciwr/sentinel-rat-dashboard) repository.

## General workflow

1. Place images in the `watch folder`.
2. The watcher of `pipeline` detects new images and triggers the `ml-pipeline`.
3. The `ml-pipeline` analyzes the image and returns the results (if there are animals detected and what species they are with corresponding amount and confidence scores).
4. The `pipeline` persists the results in the database.
5. The `dashboard` displays the results retrieved from the database.

## Quick Start (Docker Compose)

No local Python, R, or conda installation is required. Everything runs inside Docker containers.

### Step 1: Setup the environment

Clone the repository and run the setup script `setup.sh` from the `sentinel-rat` directory to initialize the environment with the specified watch folder path.

**Note**: the watch folder path must be an absolute path or a relative path from the `sentinel-rat` directory.

```bash
git clone https://github.com/ssciwr/sentinel-rat.git
cd sentinel-rat
./setup.sh /path/to/your/watch/folder
```

The setup script will:

* clone other repositories (ML pipeline, dashboard, and orchestration pipeline)
* create a `.env` inside `sentinel-rat` folder file with the `WATCH_FOLDER_HOST` pointing to the given path
    * This is a Docker Compose config file with key-value pairs for environment variables
    * You can edit `.env` later if you want to change ports, passwords, or the watch folder path

### Step 2: Start all services

Run Docker command from the `sentinel-rat` directory:

```bash
docker compose up --build
```

Docker Compose will:
1. Start PostgreSQL 17 and wait for it to be healthy
2. Run the one-shot `db-init` service, which creates the database schema and loads the required **seed data** (reference data such as cameras and taxonomy, from `seed_db.py`), then exits
3. Start the `dashboard`, `ml-pipeline`, and `pipeline` services (they wait for `db-init` to finish so the schema and seed data exist first)
4. The `pipeline` service will start watching the watch folder for new images
5. The `daily-analysis` service aggregates the detections of each past day into the `daily_analysis_result` table, every night at `ANALYSIS_TIME` in the timezone `ANALYSIS_TZ` (see below)

> **Note**: the watcher resolves the camera for each image from the filename prefix (e.g. `HDCAM01_...jpg` → camera `HDCAM01`). That camera must exist in the database (it is created by the seed data), otherwise persistence of the image is skipped.

### Optional: load sample (demo) data

The seed data above is the minimum the system needs to run. To additionally load **illustrative sample data** (e.g. example image captures) so the dashboard has something to display, enable the `demo` profile:

```bash
docker compose --profile demo up load-sample-data
```

This runs the one-shot `load-sample-data` service (defined in `sample_data.py`), which loads demo rows after `db-init` has completed, then exits. It is safe to re-run — it skips rows that already exist. A normal `docker compose up` does **not** load this data, so it never ends up in a real deployment.

### Optional: run the daily analysis by hand

The `daily-analysis` service runs on its own every night. To run it once by hand, e.g. after a downtime or to rebuild a day:

```bash
# aggregate all past days that have images not aggregated yet
docker compose run --rm daily-analysis --once
# aggregate one day (in ANALYSIS_TZ); --recompute rebuilds it from all its images
docker compose run --rm daily-analysis --date 2026-10-01 --recompute
```

Without Docker Compose, use `docker run` with the pipeline image on the network of the stack:

```bash
docker run --rm --network sentinel-rat_sentinel-rat-net \
  -e DATABASE_URL=postgresql+psycopg://sentinel_user:sentinel_pass@db:5432/sentinel_db \
  -e ANALYSIS_TZ=Asia/Colombo \
  sentinel-rat-pipeline:local python -m sentinel_rat_pipeline.daily_analysis --once
```

### Step 3: View results

- **Dashboard**: open `http://localhost:8501` (or the port set in `.env`)
- **ML pipeline**: open `http://localhost:8000/docs` (or the port set in `.env`) to see the FastAPI Swagger UI

### Step 4: Stop the stack

Press `Ctrl+C` in the terminal where Docker Compose is running, then:

```bash
docker compose down
```

**Note**: use `docker compose down -v` to remove volumes (including the database) if you want a fresh start the next time you run `docker compose up --build`.

## Environment variables

See `.env.example`. Key variables:

- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_HOST`, `POSTGRES_PORT`
- `ML_PIPELINE_PORT`
- `PIPELINE_PORT`
- `WATCH_FOLDER_DOCKER` (watch folder path inside the Docker container)
- `WATCH_FOLDER_HOST` (watch folder path on the host machine)
- `DASHBOARD_PORT`
- `DATABASE_URL`
- `ANALYSIS_TZ` (timezone in which a day of the daily analysis starts and ends, default `Asia/Colombo`)
- `ANALYSIS_TIME` (local time at which the daily analysis runs every night, default `00:00`)

## What to expect with the scaffolded code (will be replaced with the actual implementation)

### 1. Database schema

`analysis_results` table in PostgreSQL (with PostGIS enabled):

| Column | Type | Notes |
|--------|------|-------|
| `id` | `SERIAL PRIMARY KEY` | Auto-increment PK |
| `detection_id` | `VARCHAR(50)` | Detection ID, e.g. `"%Y%m%d%H%M%S"` of the detection time |
| `image_path` | `TEXT` | Full path of the analyzed image |
| `animals_detected` | `INTEGER` | Total count |
| `species` | `JSONB` | Dict of detected species with counts |
| `confidence` | `DOUBLE PRECISION` | Model confidence |
| `detected_at` | `TIMESTAMPTZ` | Time of detection |

### 2. ML pipeline mock output

Given any image, the ML pipeline will return a mock output for testing purposes.

- 1 cat
- 1 rodent
- confidence = 0.95

### 3. Dashboard display

`sentinel-rat-dashboard` renders results from the database. The Shiny app displays results in a table. For example, if the ML pipeline returns the mock output above, the dashboard will display:

>SENTINEL-RAT Dashboard
>
>| detection_id | image_path | animals_detected | species | confidence | detected_at |
>|--------------|------------|------------------|---------|------------|-------------|
>|20260730115638|a-cat-and-a-mouse-are-eating-food-together-photo.jpg|2|{"cat": 1, "rodent": 1}|0.95|1785412598.89|

---

## Development

Rerfer to repository of each component for development instructions.