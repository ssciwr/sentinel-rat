set -e # stop on error

## SENTINEL-RAT SETUP SCRIPT ##

# check input argument
if [ -z "$1" ]; then
  echo "Usage: $0 <path_to_watch_folder_host>"
  exit 1
fi

WATCH_FOLDER_HOST="$1"

echo "Setting up SENTINEL-RAT with watch folder: $WATCH_FOLDER_HOST"

# clone repositories if they don't exist
declare -A REPOS=(
  ["sentinel-rat-dashboard"]="https://github.com/ssciwr/sentinel-rat-dashboard.git"
  ["sentinel-rat-ml-pipeline"]="https://github.com/ssciwr/sentinel-rat-ml-pipeline.git"
  ["sentinel-rat-pipeline"]="https://github.com/ssciwr/sentinel-rat-pipeline.git"
)

for NAME in "${!REPOS[@]}"; do
  if [ ! -d "$NAME" ]; then
    echo "Cloning $NAME..."
    git clone "${REPOS[$NAME]}" "$NAME"
  else
    echo "$NAME already exists. Skipping clone."
  fi
done

# create .env file inside sentinel-rat directory
# update WATCH_FOLDER_HOST in .env file with the provided argument
ENV_FILE="sentinel-rat/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Creating .env file in sentinel-rat directory..."
  cp sentinel-rat/.env.example "$ENV_FILE"
  sed -i "s|WATCH_FOLDER_HOST=.*|WATCH_FOLDER_HOST=$WATCH_FOLDER_HOST|" "$ENV_FILE"
else
  echo ".env file already exists in sentinel-rat directory."
  echo "Updating WATCH_FOLDER_HOST in .env file with $WATCH_FOLDER_HOST..."
  sed -i "s|WATCH_FOLDER_HOST=.*|WATCH_FOLDER_HOST=$WATCH_FOLDER_HOST|" "$ENV_FILE"
fi