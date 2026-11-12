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
3. Start the `sentinel-rat-dashboard`, `sentinel-rat-ml-pipeline`, `sentinel-rat-pipeline` and `daily-analysis` services (they wait for `db-init` to finish so the schema and seed data exist first)
4. The `sentinel-rat-pipeline` service will start watching the watch folder for new images
5. The `daily-analysis` service aggregates the detections of each past day into the `daily_analysis_result` table, every night at `ANALYSIS_TIME` in the timezone `ANALYSIS_TZ` (see below)

> [!NOTE]
> The images of each camera are stored in a sub-folder of the watch folder named after the camera (e.g. `watched-images/hd-zoo-01/...jpg` → camera `hd-zoo-01`). The watcher resolves the camera of each image as follows:
> - image in a sub-folder: the camera named after the sub-folder, else the `device_id` in the image's EXIF `ImageDescription`;
> - image directly in the watch folder: the `device_id` in the image's EXIF `ImageDescription`, else `DEFAULT_CAMERA_NAME` (default `hd-zoo-01`).
>
> That camera must exist in the database (`hd-zoo-01` is created by the seed data), otherwise persistence of the image is skipped.

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
# rebuild all past days with the thresholds in .env; run `docker compose up -d` first,
# so that the running services use the new thresholds as well
docker compose run --rm daily-analysis --recompute-all
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

- `IMAGE_TAG` (tag of the images built from `sentinel-rat-pipeline` and `sentinel-rat-dashboard`, default `local`; set another tag for a second stack on the same machine, e.g. a test stack, so that its builds don't replace the images of this one)
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_HOST`, `POSTGRES_PORT`
- `ML_PIPELINE_PORT`
- `PIPELINE_PORT`
- `WATCH_FOLDER_DOCKER` (watch folder path inside the Docker container)
- `WATCH_FOLDER_HOST` (watch folder path on the host machine)
- `DEFAULT_CAMERA_NAME` (camera of images directly in the watch folder without a `device_id` in their metadata, default `hd-zoo-01`)
- `DASHBOARD_PORT`
- `DATABASE_URL`
- `ANALYSIS_TZ` (timezone in which a day of the daily analysis starts and ends, default `Asia/Colombo`)
- `ANALYSIS_TIME` (local time at which the daily analysis runs every night, default `00:00`)
- `DET_CONF_THRESHOLD`, `CLAS_CONF_THRESHOLD` (results of all detection and classification models below these confidence thresholds are left out of the daily analysis, `0` to `1`, default `0`, which keeps all results)

## What to expect with the scaffolded code (will be replaced with the actual implementation)

### 1. Database schema

The database is PostgreSQL with PostGIS enabled. Its schema is defined in `src/dashboard/db/data_model.py` of [sentinel-rat-dashboard](https://github.com/ssciwr/sentinel-rat-dashboard) and created by the `db-init` service. See the [data model](https://github.com/ssciwr/sentinel-rat-dashboard#data-model) in its README for all columns and relations.

| Table | Content | Written by |
|-------|---------|------------|
| `camera` | Cameras, with their current location and status | `db-init` (seed data in `seed_db.py`) |
| `camera_location_history` | Previous locations of a camera | `sentinel-rat-dashboard` |
| `ml_model` | Detection and classification models | `sentinel-rat-pipeline` |
| `taxonomy` | Species, with `is_predator` | `sentinel-rat-pipeline` |
| `image_capture` | One row per image: camera, capture time, `analyzed_at` and `file_status` | `sentinel-rat-pipeline`; `daily-analysis` sets `analyzed_at` |
| `object_detection` | Detections of an image: bounding box, class and confidence | `sentinel-rat-pipeline` |
| `species_classification` | Species of a detection, with confidence | `sentinel-rat-pipeline` |
| `detection_correction`, `classification_correction` | Corrections of detections and species made by users | `sentinel-rat-dashboard` |
| `app_user` | Dashboard users | `sentinel-rat-dashboard` |
| `daily_analysis_result` | Count of each species per camera, day and detection model, with average classification confidence, confidence thresholds and image count | `daily-analysis`; `sentinel-rat-dashboard` rebuilds a day when a user corrects it |

### 2. ML pipeline mock output

Given any image, the ML pipeline returns the same mock output for testing purposes (defined in `src/ml_pipeline/services/` of [sentinel-rat-ml-pipeline](https://github.com/ssciwr/sentinel-rat-ml-pipeline)):

| Detection (model `megadetector` v5a) | Confidence | Bounding box (`x_min`, `y_min`, `x_max`, `y_max`) | Species (model `rodent-classifier` 0.1) |
|-----------|------------|--------------|---------|
| `animal` | 0.92 | 0.1, 0.2, 0.4, 0.5 | black rat (*Rattus rattus*), 0.87; brown rat (*Rattus norvegicus*), 0.1 |
| `person` | 0.81 | 0.6, 0.1, 0.9, 0.95 | — (only `animal` detections are classified) |

### 3. Dashboard display

`sentinel-rat-dashboard` renders results from the database. The Shiny app displays results in a table. For example, if the ML pipeline returns the mock output above, the dashboard will display:

>SENTINEL-RAT Dashboard
>
>| id |	image_capture_id | det_model_id | created_at | confidence | bbox | detected_class | species | species_confidence | role |
>| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
>| 1 | 1 | 1| 2026-10-28 14:54:02.802789 | 0.92 | x_max: 0.4, x_min: 0.1, y_max: 0.5, y_min: 0.2 | animal | black rat | 0.87 | not assessed |
>| 2 | 1 | 1 | 2026-10-28 14:54:02.802789 | 0.81 | x_max: 0.9, x_min: 0.6, y_max: 0.95, y_min: 0.1 | person | NA | NA | NA |

---

## Development

Rerfer to repository of each component for development instructions.