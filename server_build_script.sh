#!/bin/bash

# Function to get timestamp with decimal precision
get_timestamp() {
  perl -MTime::HiRes=time -e 'printf "%.2f", time'
}

# Set up logging
# Use /home/julian/logs if it exists and is writable, otherwise use current directory
if [ -w "/home/julian/logs" ] || mkdir -p "/home/julian/logs/cyberknight-council-template" 2>/dev/null; then
  LOG_DIR="/home/julian/logs/cyberknight-council-template"
else
  LOG_DIR="./logs"
  mkdir -p "$LOG_DIR"
fi
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
  # NGINX_DIR is no longer used for deployment but is kept in the signature
  # for backward compatibility with webhook callers. Log a warning and continue.
  echo "WARNING: NGINX_DIR is not set. This is expected — deployment now goes to S3."
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
echo "NGINX_DIR: ${NGINX_DIR:-<not set>}"
echo "JEKYLL_BUILDER_IMAGE: $JEKYLL_BUILDER_IMAGE"

# --- Doppler secrets ---
export HISTIGNORE='export DOPPLER_TOKEN*'
export DOPPLER_TOKEN="$(pass show cyberknight/s3-sync-doppler-token)"

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

# Sync to S3
echo "Syncing to S3..."
STEP_START=$(get_timestamp)
doppler run --project cyberknight-s3-sync --config prd -- \
  aws s3 sync $JEKYLL_DIR/_site/ s3://cyberknight-websites/council-$COUNCIL_NUMBER/ --delete
S3_EXIT_CODE=$?
S3_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")
echo "  → S3 sync completed with exit code $S3_EXIT_CODE in ${S3_TIME}s"

if [ $S3_EXIT_CODE -ne 0 ]; then
  echo "ERROR: S3 sync failed. Site may be partially deployed."
  exit 1
fi

# Purge Cloudflare cache
echo "Purging Cloudflare cache for council-$COUNCIL_NUMBER..."
STEP_START=$(get_timestamp)
doppler run --project cyberknight-s3-sync --config prd -- \
  sh -c 'curl -s -o /dev/null -w "%{http_code}" -X POST \
    "https://api.cloudflare.com/client/v4/zones/9dbd179caf99bb5fd469db1545fbb431/purge_cache" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"prefixes\": [\"council-'"$COUNCIL_NUMBER"'.cyberknight-websites.com/\"]}"'
CF_HTTP_CODE=$?
PURGE_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")
echo "  → Cache purge completed in ${PURGE_TIME}s"

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
echo "  5. S3 sync:                 ${S3_TIME}s"
echo "  6. Cloudflare cache purge:  ${PURGE_TIME}s"

