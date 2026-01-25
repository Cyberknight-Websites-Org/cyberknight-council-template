#!/bin/bash

# Function to get timestamp with decimal precision
get_timestamp() {
  perl -MTime::HiRes=time -e 'printf "%.2f", time'
}

# Set up logging
LOG_DIR="/home/julian/logs/cyberknight-council-template"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/build_${TIMESTAMP}.log"

# Redirect all output to log file (and still show in stdout)
exec > >(tee -a "$LOG_FILE") 2>&1

# Capture start time
START_TIME=$(get_timestamp)
echo "=== Build started at $(date) ==="

# parse arguments KEY=VALUE
while [ $# -gt 0 ]; do
  case "$1" in
    *=*)
      varname=$(echo "$1" | cut -d= -f1)
      varvalue=$(echo "$1" | cut -d= -f2-)
      eval "$varname=\"$varvalue\""
      ;;
  esac
  shift
done

# add a check that exits if the variables are not set and exit with an error message
if [ -z "$JEKYLL_DIR" ]; then
  echo "JEKYLL_DIR is not set. Exiting."
  exit 1
fi
if [ -z "$NGINX_DIR" ]; then
  echo "NGINX_DIR is not set. Exiting."
  exit 1
fi
if [ -z "$JEKYLL_BUILDER_IMAGE" ]; then
  echo "JEKYLL_BUILDER_IMAGE is not set. Exiting."
  exit 1
fi
if [ -z "$COUNCIL_NUMBER" ]; then
  echo "COUNCIL_NUMBER is not set. Exiting."
  exit 1
fi

echo "Building council: $COUNCIL_NUMBER"
echo "JEKYLL_DIR: $JEKYLL_DIR"
echo "NGINX_DIR: $NGINX_DIR"
echo "JEKYLL_BUILDER_IMAGE: $JEKYLL_BUILDER_IMAGE"

# Remove JEKYLL_DIR if it exists and create a new one
STEP_START=$(get_timestamp)
if [ -d "$JEKYLL_DIR" ]; then
  rm -rf $JEKYLL_DIR
fi
mkdir -p $JEKYLL_DIR
CLEANUP_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")

# Git clone
echo "Cloning repository..."
STEP_START=$(get_timestamp)
git clone --depth 1 https://github.com/Cyberknight-Websites/cyberknight-council-template.git $JEKYLL_DIR
CLONE_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")

cd $JEKYLL_DIR

# Sync council data
echo "Syncing council data..."
STEP_START=$(get_timestamp)
docker run --rm -v $JEKYLL_DIR:/srv/jekyll -u $(id -u):$(id -g) $JEKYLL_BUILDER_IMAGE bundler exec ruby /srv/jekyll/_scripts/sync_data.rb --council $COUNCIL_NUMBER --url https://secure.cyberknight-websites.com
DOCKER_EXIT_CODE=$?
SYNC_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")
echo "  → Sync completed with exit code $DOCKER_EXIT_CODE in ${SYNC_TIME}s"

if [ $DOCKER_EXIT_CODE -ne 0 ]; then
  echo "ERROR: Data sync failed. Aborting build."
  exit 1
fi

# Jekyll build
echo "Building Jekyll site..."
STEP_START=$(get_timestamp)
docker run --rm -v $JEKYLL_DIR:/srv/jekyll -u $(id -u):$(id -g) $JEKYLL_BUILDER_IMAGE bundler exec jekyll build
DOCKER_EXIT_CODE=$?
BUILD_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")
echo "  → Build completed with exit code $DOCKER_EXIT_CODE in ${BUILD_TIME}s"

if [ $DOCKER_EXIT_CODE -ne 0 ]; then
  echo "ERROR: Jekyll build failed. Aborting deployment."
  exit 1
fi

# Copy to nginx
echo "Copying files to nginx directory..."
STEP_START=$(get_timestamp)
rm -rf $NGINX_DIR/council-$COUNCIL_NUMBER
mkdir -p $NGINX_DIR/council-$COUNCIL_NUMBER
cp -r $JEKYLL_DIR/_site/* $NGINX_DIR/council-$COUNCIL_NUMBER
COPY_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")

# Calculate build duration
END_TIME=$(get_timestamp)
DURATION=$(perl -e "printf '%.2f', $END_TIME - $START_TIME")

echo ""
echo "=== Build completed at $(date) ==="
echo "=== Total build time: ${DURATION} seconds ==="
echo ""
echo "Step-by-step breakdown:"
echo "  1. Cleanup directories:     ${CLEANUP_TIME}s"
echo "  2. Git clone repository:    ${CLONE_TIME}s"
echo "  3. Sync council data:       ${SYNC_TIME}s"
echo "  4. Jekyll build:            ${BUILD_TIME}s"
echo "  5. Copy to nginx:           ${COPY_TIME}s"