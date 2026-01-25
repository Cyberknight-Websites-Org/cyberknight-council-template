#!/bin/bash

# Configuration
COUNCIL_NUMBER=${1:-2431}
KOC_URL=${2:-https://secure.cyberknight-websites.com}
PORT=${3:-4000}
HOST="0.0.0.0"  # Bind to all interfaces for nginx reverse proxy access

# Step 1: Display startup info
echo "========================================="
echo "Starting Jekyll Development Server"
echo "========================================="
echo "Council Number: $COUNCIL_NUMBER"
echo "API URL: $KOC_URL"
echo "Port: $PORT"
echo "========================================="

# Step 2: Run data sync
echo "Syncing council data from API..."
bundle exec ruby _scripts/sync_data.rb --council "$COUNCIL_NUMBER" --url "$KOC_URL"

# Check sync success
if [ $? -ne 0 ]; then
    echo "ERROR: Data sync failed. Aborting."
    exit 1
fi

echo "Data sync completed successfully."
echo "========================================="

# Step 3: Start Jekyll server
echo "Starting Jekyll server..."
bundle exec jekyll serve --host "$HOST" --port "$PORT"

# Note: This runs in foreground, so the script stays active until Ctrl+C
