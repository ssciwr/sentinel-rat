#!/usr/bin/env bash
# End-to-end smoke test of the docker compose stack.
# Written by Claude, checked by human.
#
# Starts a separate test stack (own project, image tag, ports, database and watch
# folder, so a running stack on the same machine is not touched), puts one image
# into the watch folder and checks that it flows through every service:
#   ML pipeline -> pipeline -> database -> daily analysis, and the dashboard is up.
# The test stack is removed at the end, also when a check fails.
#
# Usage (from the sentinel-rat directory, next to the other sentinel-rat repos):
#   ./smoke_test.sh          # build, test, clean up
#   ./smoke_test.sh --keep   # keep the test stack running afterwards, for debugging
#   ./smoke_test.sh --editable ../sentinel-rat-dashboard
#       # the pipeline and daily-analysis services use the dashboard package of this
#       # checkout (its current working tree) instead of the one installed in the
#       # pipeline image from GitHub, e.g. to test with unmerged dashboard changes
#
# Host ports can be changed with SMOKE_POSTGRES_PORT, SMOKE_ML_PIPELINE_PORT,
# SMOKE_PIPELINE_PORT and SMOKE_DASHBOARD_PORT, if the defaults are taken.

set -euo pipefail

usage() {
  echo "Usage: $0 [--keep] [--editable <path to sentinel-rat-dashboard>]" >&2
  exit 2
}

# --- check parameter values ---
KEEP=false
DASHBOARD_SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=true ;;
    --editable)
      [ $# -ge 2 ] || usage
      if [ ! -d "$2/src/dashboard/db" ]; then
        echo "No dashboard package in '$2' (expected $2/src/dashboard)." >&2
        exit 2
      fi
      DASHBOARD_SRC=$(cd "$2/src" && pwd) # absolute, before the cd below
      shift
      ;;
    *) usage ;;
  esac
  shift
done

# --- check that we are in the sentinel-rat directory ---
cd "$(dirname "$0")"
if [ ! -f docker-compose.yml ] || [ ! -f .env.example ]; then
  echo "Run this script from the sentinel-rat directory." >&2
  exit 2
fi

# --- prepare the test stack ---
PROJECT=sentinel-rat-test
TIMEOUT=120 # seconds to wait for each result
# capture time of the test image, in the file name; it must be a past day, since
# the daily analysis only aggregates days before today
IMAGE_NAME=image_20250601T120000Z.jpg
CAMERA=hd-zoo-01 # seeded by db-init

# inside the repo, not /tmp: Docker Desktop only mounts folders shared with it,
# such as the home directory
WORK_DIR=$(mktemp -d "$PWD/.smoke_test.XXXXXX")
WATCH_DIR="$WORK_DIR/watched-images"
ENV_FILE="$WORK_DIR/test.env"
# the camera folder exists before the stack starts, like on a server
mkdir -p "$WATCH_DIR/$CAMERA"
# readable by the user in the containers
chmod 755 "$WORK_DIR" "$WATCH_DIR" "$WATCH_DIR/$CAMERA"

# the defaults of .env.example, then the overrides of the test stack (later wins)
cp .env.example "$ENV_FILE"
cat >> "$ENV_FILE" <<EOF

# smoke test overrides
IMAGE_TAG=test
POSTGRES_PORT=${SMOKE_POSTGRES_PORT:-15432}
ML_PIPELINE_PORT=${SMOKE_ML_PIPELINE_PORT:-18000}
PIPELINE_PORT=${SMOKE_PIPELINE_PORT:-18001}
DASHBOARD_PORT=${SMOKE_DASHBOARD_PORT:-18501}
WATCH_FOLDER_HOST=$WATCH_DIR
BATCH_WINDOW_SECONDS=2
EOF

# --- extract values from the environment file ---
DASHBOARD_PORT=$(grep '^DASHBOARD_PORT=' "$ENV_FILE" | tail -1 | cut -d= -f2)
POSTGRES_USER=$(grep '^POSTGRES_USER=' "$ENV_FILE" | tail -1 | cut -d= -f2)
POSTGRES_DB=$(grep '^POSTGRES_DB=' "$ENV_FILE" | tail -1 | cut -d= -f2)

COMPOSE_FILES=(-f docker-compose.yml)

# --- use the dashboard package of a local checkout instead of the one installed in the pipeline image ---
if [ -n "$DASHBOARD_SRC" ]; then
  # mount the dashboard package into the containers of the pipeline image; it comes
  # first on PYTHONPATH, so it is imported instead of the installed one
  OVERRIDE_FILE="$WORK_DIR/editable-dashboard.yml"
  cat > "$OVERRIDE_FILE" <<EOF
services:
  sentinel-rat-pipeline: &editable-dashboard
    volumes:
      - $DASHBOARD_SRC/dashboard:/editable/dashboard:ro
    environment:
      PYTHONPATH: /editable:/workflow/src
  daily-analysis: *editable-dashboard
EOF
  COMPOSE_FILES+=(-f "$OVERRIDE_FILE")
fi

# -- helper functions for docker compose and the smoke test ---
compose() {
  docker compose -p "$PROJECT" --env-file "$ENV_FILE" "${COMPOSE_FILES[@]}" "$@"
}

step() { echo; echo "==> $*"; }
pass() { echo "    ok: $*"; }

FAILED_STEP=""
fail() {
  FAILED_STEP="$*"
  echo "    FAILED: $*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if [ $status -ne 0 ]; then
    echo
    echo "==> Logs of the test stack (last 40 lines per service)"
    compose logs --no-color --tail 40 2>/dev/null || true
  fi
  if $KEEP; then
    echo
    echo "Test stack kept running. Inspect it with:"
    echo "  docker compose -p $PROJECT --env-file $ENV_FILE ps"
    echo "Remove it with:"
    echo "  docker compose -p $PROJECT --env-file $ENV_FILE down -v && rm -rf $WORK_DIR"
  else
    echo
    echo "==> Removing the test stack"
    compose --profile demo down -v --remove-orphans >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
  fi
  echo
  if [ $status -eq 0 ]; then
    echo "SMOKE TEST PASSED"
  else
    echo "SMOKE TEST FAILED${FAILED_STEP:+: $FAILED_STEP}"
  fi
  exit $status
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# run a query in the test database, print the result without headers
sql() {
  compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "$1"
}

# wait until the query returns the expected value, or fail
wait_for_sql() {
  local description=$1 query=$2 expected=$3 result=""
  for ((i = 0; i < TIMEOUT; i += 2)); do
    result=$(sql "$query" 2>/dev/null || true)
    if [ "$result" = "$expected" ]; then
      pass "$description"
      return
    fi
    sleep 2
  done
  fail "$description (expected '$expected', got '$result' after ${TIMEOUT}s)"
}

# --- show which dashboard code is being used ---
if [ -n "$DASHBOARD_SRC" ]; then
  step "Using the dashboard package of $DASHBOARD_SRC/dashboard in sentinel-rat-pipeline and daily-analysis"
  echo "    $(git -C "$DASHBOARD_SRC" log -1 --format='%D, commit %h' 2>/dev/null || echo 'not a git checkout')"
  # only the Python files of the mounted folder count; it also holds the R code of
  # the dashboard app, which the pipeline doesn't use (in git pathspecs, * also
  # matches subfolders)
  if [ -n "$(git -C "$DASHBOARD_SRC" status --porcelain -- 'dashboard/*.py' 2>/dev/null)" ]; then
    echo "    with uncommitted changes in the Python files of src/dashboard"
  fi
  # the dashboard image is always built from the build context in docker-compose.yml
  if [ "$DASHBOARD_SRC" != "$(cd ../sentinel-rat-dashboard/src 2>/dev/null && pwd)" ]; then
    echo "    note: the dashboard, db-init and load-sample-data services still use"
    echo "    ../sentinel-rat-dashboard, the build context in docker-compose.yml"
  fi
fi

# --- start the test stack and check that all services are up ---
step "Starting the test stack '$PROJECT' (building images with tag 'test')"
compose up --build --wait --wait-timeout 300 ||
  fail "a service did not start or is unhealthy, see the logs below"
pass "all services started"

step "Adding a test image to the watch folder"
cp tests/smoke_image.jpg "$WATCH_DIR/$CAMERA/$IMAGE_NAME"
chmod 644 "$WATCH_DIR/$CAMERA/$IMAGE_NAME"
pass "$CAMERA/$IMAGE_NAME"

step "Checking that the pipeline stored the image and the ML pipeline's results"
wait_for_sql "image stored for camera $CAMERA" \
  "SELECT count(*) FROM image_capture i JOIN camera c ON c.id = i.camera_id
   WHERE i.image_path = '$CAMERA/$IMAGE_NAME' AND c.name = '$CAMERA'" "1"
# the mock ML pipeline detects an animal and a person, and classifies the animal
wait_for_sql "2 detections (animal, person)" \
  "SELECT string_agg(detected_class, ',' ORDER BY detected_class) FROM object_detection" \
  "animal,person"
wait_for_sql "2 species candidates of the animal" \
  "SELECT count(*) FROM species_classification" "2"

step "Running the daily analysis"
compose run --rm daily-analysis --once || fail "daily analysis exited with an error"
pass "daily analysis exited with 0"
# the scheduler of the stack may have aggregated the image first; either way,
# there must be one result row: one black rat with the confidence of the mock
wait_for_sql "daily result: 1 black rat, avg confidence 0.87, 1 image" \
  "SELECT string_agg(t.genus || ' ' || t.species || '|' || r.taxonomy_count || '|'
          || round(r.avg_confidence::numeric, 2) || '|' || r.image_count, ';')
   FROM daily_analysis_result r JOIN taxonomy t ON t.id = r.taxonomy_id" \
  "Rattus rattus|1|0.87|1"
wait_for_sql "image marked as analyzed" \
  "SELECT count(*) FROM image_capture WHERE analyzed_at IS NOT NULL" "1"

step "Checking that the dashboard responds"
for ((i = 0; i < TIMEOUT; i += 2)); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$DASHBOARD_PORT/" || true)
  [ "$code" = "200" ] && break
  sleep 2
done
[ "$code" = "200" ] || fail "dashboard on port $DASHBOARD_PORT (HTTP $code after ${TIMEOUT}s)"
pass "dashboard answers with HTTP 200 on port $DASHBOARD_PORT"
