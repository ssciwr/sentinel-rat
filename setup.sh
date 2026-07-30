set -e # stop on error

## SENTINEL-RAT SETUP SCRIPT ##

# check input argument
if [ -z "$1" ]; then
  echo "Usage: $0 <path_to_watch_folder_host>"
  exit 1
fi

WATCH_FOLDER_HOST="$1"

# check if docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Please install Docker and try again."
  exit 1
fi

echo "Docker found: $(docker --version)"

# check if docker-compose is installed
if ! docker compose version &> /dev/null; then
  echo "Docker Compose is not installed. Please install Docker Compose and try again."
  exit 1
fi

echo "Docker Compose found: $(docker compose version)"

# check if user has permission to run docker commands
if ! docker info &> /dev/null; then
  echo "You do not have permission to run Docker commands."
  echo "Run: sudo usermod -aG docker \$USER"
  echo "Then log out and log back in, or restart your session."
  echo "Please contact your system administrator if you do not have sudo privileges."
  exit 1
fi

echo "Docker environement is ready. Setting up SENTINEL-RAT with watch folder: $WATCH_FOLDER_HOST"

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