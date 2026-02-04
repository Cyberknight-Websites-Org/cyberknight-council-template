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
LOG_FILE="$LOG_DIR/build_all_councils_${TIMESTAMP}.log"

# Redirect all output to log file (and still show in stdout)
exec > >(tee -a "$LOG_FILE") 2>&1

# Capture start time
START_TIME=$(get_timestamp)
echo "=== Multi-Council Build Started at $(date) ==="

# Parse arguments KEY=VALUE
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

# Set default API URL if not provided
if [ -z "$API_URL" ]; then
  API_URL="http://secure.cyberknight-websites.com"
fi

# Validate required parameters
if [ -z "$JEKYLL_DIR_BASE" ]; then
  echo "ERROR: JEKYLL_DIR_BASE is not set. Exiting."
  exit 1
fi
if [ -z "$NGINX_DIR" ]; then
  echo "ERROR: NGINX_DIR is not set. Exiting."
  exit 1
fi
if [ -z "$JEKYLL_BUILDER_IMAGE" ]; then
  echo "ERROR: JEKYLL_BUILDER_IMAGE is not set. Exiting."
  exit 1
fi

echo "Configuration:"
echo "  JEKYLL_DIR_BASE: $JEKYLL_DIR_BASE"
echo "  NGINX_DIR: $NGINX_DIR"
echo "  JEKYLL_BUILDER_IMAGE: $JEKYLL_BUILDER_IMAGE"
echo "  API_URL: $API_URL"
echo ""

# Check for required dependencies
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is not installed. Please install jq to parse JSON."
  exit 1
fi

if ! command -v curl &> /dev/null; then
  echo "ERROR: curl is not installed. Please install curl to fetch API data."
  exit 1
fi

# Fetch council list from API
echo "Fetching council list from API..."
COUNCIL_DATA=$(curl -sL "$API_URL/public_api/get_all_council_websites" 2>&1)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -ne 0 ]; then
  echo "ERROR: Failed to fetch council list from API"
  echo "curl exit code: $CURL_EXIT_CODE"
  echo "Response: $COUNCIL_DATA"
  exit 1
fi

# Validate JSON response
if ! echo "$COUNCIL_DATA" | jq empty 2>/dev/null; then
  echo "ERROR: API response is not valid JSON"
  echo "Response: $COUNCIL_DATA"
  exit 1
fi

# Parse council data
readarray -t COUNCIL_IDS < <(echo "$COUNCIL_DATA" | jq -r '.council_websites[] | .council_id')
readarray -t COUNCIL_NAMES < <(echo "$COUNCIL_DATA" | jq -r '.council_websites[] | .council_name')

TOTAL_COUNCILS=${#COUNCIL_IDS[@]}

if [ $TOTAL_COUNCILS -eq 0 ]; then
  echo "ERROR: No councils found in API response"
  exit 1
fi

echo "Found $TOTAL_COUNCILS councils to build"
echo ""

# Initialize tracking arrays
declare -a SUCCESSFUL_COUNCILS
declare -a FAILED_COUNCILS
declare -a COUNCIL_TIMES

# Build each council
for i in "${!COUNCIL_IDS[@]}"; do
  COUNCIL_ID="${COUNCIL_IDS[$i]}"
  COUNCIL_NAME="${COUNCIL_NAMES[$i]}"
  JEKYLL_DIR="${JEKYLL_DIR_BASE}/council-${COUNCIL_ID}"

  echo "Building council $COUNCIL_ID ($COUNCIL_NAME)..."

  COUNCIL_START=$(get_timestamp)

  # Call the existing build script for this council
  ./server_build_script.sh \
    JEKYLL_DIR="$JEKYLL_DIR" \
    NGINX_DIR="$NGINX_DIR" \
    JEKYLL_BUILDER_IMAGE="$JEKYLL_BUILDER_IMAGE" \
    COUNCIL_NUMBER="$COUNCIL_ID"

  BUILD_EXIT_CODE=$?
  COUNCIL_END=$(get_timestamp)
  COUNCIL_DURATION=$(perl -e "printf '%.2f', $COUNCIL_END - $COUNCIL_START")

  # Track results
  if [ $BUILD_EXIT_CODE -eq 0 ]; then
    SUCCESSFUL_COUNCILS+=("$COUNCIL_ID|$COUNCIL_NAME|$COUNCIL_DURATION")
    echo "  ✓ Build completed in ${COUNCIL_DURATION}s"
  else
    FAILED_COUNCILS+=("$COUNCIL_ID|$COUNCIL_NAME|$COUNCIL_DURATION")
    echo "  ✗ Build failed with exit code $BUILD_EXIT_CODE in ${COUNCIL_DURATION}s"
  fi

  echo ""
done

# Calculate total time
END_TIME=$(get_timestamp)
TOTAL_DURATION=$(perl -e "printf '%.2f', $END_TIME - $START_TIME")

# Print summary report
echo "=============================================="
echo "=== Multi-Council Build Summary ==="
echo "=============================================="
echo "Total councils: $TOTAL_COUNCILS"
echo "Successful: ${#SUCCESSFUL_COUNCILS[@]}"
echo "Failed: ${#FAILED_COUNCILS[@]}"
echo "Total time: ${TOTAL_DURATION}s"
echo ""

if [ ${#SUCCESSFUL_COUNCILS[@]} -gt 0 ]; then
  echo "Successful builds:"
  for entry in "${SUCCESSFUL_COUNCILS[@]}"; do
    IFS='|' read -r id name duration <<< "$entry"
    echo "  ✓ $id ($name) - ${duration}s"
  done
  echo ""
fi

if [ ${#FAILED_COUNCILS[@]} -gt 0 ]; then
  echo "Failed builds:"
  for entry in "${FAILED_COUNCILS[@]}"; do
    IFS='|' read -r id name duration <<< "$entry"
    echo "  ✗ $id ($name) - ${duration}s"
  done
  echo ""
fi

echo "Master log: $LOG_FILE"
echo "Per-council logs: $LOG_DIR/build_*.log"
echo ""
echo "=== Multi-Council Build Completed at $(date) ==="

# Determine exit code
if [ ${#FAILED_COUNCILS[@]} -eq 0 ]; then
  # All successful
  exit 0
elif [ ${#SUCCESSFUL_COUNCILS[@]} -eq 0 ]; then
  # All failed
  exit 1
else
  # Partial success
  exit 2
fi
