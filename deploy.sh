#!/bin/bash

# Deploy _site/ to S3 + Cloudflare cache purge (manifest-based diff deploy)
# Usage: ./deploy.sh COUNCIL_NUMBER=<n> JEKYLL_DIR=<path> JEKYLL_BUILDER_IMAGE=<img> NGINX_DIR=<path> [FORCE_FULL=true]
#
# Credentials are injected via Doppler (cyberknight-s3-sync / prd).


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

get_timestamp() {
  perl -MTime::HiRes=time -e 'printf "%.2f", time'
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

if [ -w "$HOME/logs" ]; then
  LOG_DIR="$HOME/logs/cyberknight-council-template"
else
  LOG_DIR="./logs"
fi
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/deploy_${TIMESTAMP}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

START_TIME=$(get_timestamp)
echo "=== Deploy started at $(date) ==="

# ---------------------------------------------------------------------------
# Temporary file tracking for cleanup
# ---------------------------------------------------------------------------

TEMP_FILES=()

cleanup() {
  local exit_code=$?
  for f in "${TEMP_FILES[@]}"; do
    rm -f "$f"
  done
  exit $exit_code
}

trap cleanup EXIT

add_temp() {
  local tmpfile
  tmpfile=$(mktemp)
  TEMP_FILES+=("$tmpfile")
  echo "$tmpfile"
}

# ---------------------------------------------------------------------------
# Step 1: Argument parsing
# ---------------------------------------------------------------------------

FORCE_FULL=false

for arg in "$@"; do
  case "$arg" in
    *=*)
      varname=$(echo "$arg" | cut -d= -f1)
      varvalue=$(echo "$arg" | cut -d= -f2-)
      eval "$varname=\"$varvalue\""
      ;;
    *)
      echo "ERROR: Unknown argument '$arg'. Expected KEY=VALUE format."
      exit 1
      ;;
  esac
done

# Validate required arguments
arg_errors=()
if [ -z "$COUNCIL_NUMBER" ]; then
  arg_errors+=("COUNCIL_NUMBER is required")
fi
if [ -z "$JEKYLL_DIR" ]; then
  arg_errors+=("JEKYLL_DIR is required")
fi
if [ -z "$JEKYLL_BUILDER_IMAGE" ]; then
  arg_errors+=("JEKYLL_BUILDER_IMAGE is required")
fi
if [ -z "$NGINX_DIR" ]; then
  echo "WARNING: NGINX_DIR is not set. This is expected — deployment goes to S3."
fi

if [ ${#arg_errors[@]} -gt 0 ]; then
  echo "ERROR: Missing required arguments:"
  for e in "${arg_errors[@]}"; do
    echo "  - $e"
  done
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Dependency checks
# ---------------------------------------------------------------------------

check_dependencies() {
  local failures=()

  # aws
  if ! command -v aws &>/dev/null; then
    failures+=("aws — binary not found in PATH")
  fi

  # doppler
  if ! command -v doppler &>/dev/null; then
    failures+=("doppler — binary not found in PATH")
  fi

  # jq
  if ! command -v jq &>/dev/null; then
    failures+=("jq — binary not found in PATH")
  fi

  # sha256sum
  if ! command -v sha256sum &>/dev/null; then
    failures+=("sha256sum — binary not found in PATH")
  fi

  # curl
  if ! command -v curl &>/dev/null; then
    failures+=("curl — binary not found in PATH")
  fi

  # pass
  if ! command -v pass &>/dev/null; then
    failures+=("pass — binary not found in PATH")
  fi

  # perl
  if ! command -v perl &>/dev/null; then
    failures+=("perl — binary not found in PATH")
  fi

  # Only check pass key and Doppler accessibility if DOPPLER_TOKEN is not already set
  if [ -z "$DOPPLER_TOKEN" ]; then
    local pass_token_check
    pass_token_check=$(pass show cyberknight/s3-sync-doppler-token 2>/dev/null) || true
    if [ -z "$pass_token_check" ]; then
      failures+=("pass key cyberknight/s3-sync-doppler-token is not accessible (missing GPG key or uninitialized password store?)")
    fi

    local doppler_token_check
    doppler_token_check=$(DOPPLER_TOKEN="$pass_token_check" doppler secrets get CLOUDFLARE_API_TOKEN --project cyberknight-s3-sync --config prd --plain 2>/dev/null) || true
    if [ -z "$doppler_token_check" ]; then
      failures+=("Doppler project cyberknight-s3-sync / prd is not accessible or CLOUDFLARE_API_TOKEN is missing")
    fi
  fi

  if [ ${#failures[@]} -gt 0 ]; then
    echo "ERROR: The following dependency checks failed:"
    for f in "${failures[@]}"; do
      echo "  - $f"
    done
    exit 1
  fi
}

check_dependencies

# ---------------------------------------------------------------------------
# Step 3: Configuration
# ---------------------------------------------------------------------------

S3_BUCKET="cyberknight-websites"
S3_FOLDER="council-${COUNCIL_NUMBER}"
SITE_DIR="${JEKYLL_DIR}/_site"
MANIFEST_KEY="${S3_FOLDER}/.manifest.json"
CF_ZONE_ID="9dbd179caf99bb5fd469db1545fbb431"
CF_HOSTNAME_DEFAULT="council-${COUNCIL_NUMBER}.cyberknight-websites.com"
CF_HOSTNAME_PRIMARY=$(grep '^url:' "${JEKYLL_DIR}/_config.yml" | sed 's|^url:[[:space:]]*https\?://||' | tr -d '[:space:]')
if [ -z "$CF_HOSTNAME_PRIMARY" ]; then
  CF_HOSTNAME_PRIMARY="$CF_HOSTNAME_DEFAULT"
fi
CF_HOSTNAMES=("$CF_HOSTNAME_PRIMARY")
if [ "$CF_HOSTNAME_DEFAULT" != "$CF_HOSTNAME_PRIMARY" ]; then
  CF_HOSTNAMES+=("$CF_HOSTNAME_DEFAULT")
fi
MAX_PARALLEL_UPLOADS=8

echo "Deploying council: $COUNCIL_NUMBER"
echo "JEKYLL_DIR: $JEKYLL_DIR"
echo "S3 folder: s3://${S3_BUCKET}/${S3_FOLDER}/"
echo "CF hostname (primary): $CF_HOSTNAME_PRIMARY"
if [ ${#CF_HOSTNAMES[@]} -gt 1 ]; then
  echo "CF hostname (also purging): $CF_HOSTNAME_DEFAULT"
fi

# ---------------------------------------------------------------------------
# Step 4: Doppler token
# ---------------------------------------------------------------------------

if [ -z "$DOPPLER_TOKEN" ]; then
  export DOPPLER_TOKEN="$(pass show cyberknight/s3-sync-doppler-token)"
  if [ -z "$DOPPLER_TOKEN" ]; then
    echo "ERROR: Could not retrieve Doppler token from pass. Exiting."
    exit 1
  fi
fi

if [ ! -d "$SITE_DIR" ]; then
  echo "ERROR: Site directory '${SITE_DIR}' not found. Run a Jekyll build first."
  exit 1
fi

export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --project cyberknight-s3-sync --config prd --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --project cyberknight-s3-sync --config prd --plain)

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "ERROR: Could not retrieve AWS credentials from Doppler. Exiting."
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 5: Fetch previous manifest
# ---------------------------------------------------------------------------

PREV_MANIFEST_FILE=$(add_temp)
FULL_UPLOAD=false

STEP_START=$(get_timestamp)
if ! aws s3 cp "s3://${S3_BUCKET}/${MANIFEST_KEY}" "$PREV_MANIFEST_FILE" --region us-east-1 2>/dev/null; then
  echo "No previous manifest found in S3. Performing full upload."
  FULL_UPLOAD=true
fi

PREV_FETCH_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")

if [ "$FORCE_FULL" = true ]; then
  FULL_UPLOAD=true
  echo "Full upload forced via FORCE_FULL=true flag."
fi

# ---------------------------------------------------------------------------
# Step 6: Generate current manifest
# ---------------------------------------------------------------------------

STEP_START=$(get_timestamp)
CURRENT_MANIFEST_FILE=$(add_temp)

# Build JSON object: { "relative/path": "sha256hash", ... }
MANIFEST_JSON="{}"

while IFS= read -r -d '' file; do
  rel_path="${file#${SITE_DIR}/}"
  hash=$(sha256sum "$file" | awk '{print $1}')
  MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq --arg key "$rel_path" --arg val "$hash" '. + {($key): $val}')
done < <(find "$SITE_DIR" -type f -print0 | sort -z)

echo "$MANIFEST_JSON" > "$CURRENT_MANIFEST_FILE"
HASH_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")

# ---------------------------------------------------------------------------
# Step 7: Diff the manifests
# ---------------------------------------------------------------------------

STEP_START=$(get_timestamp)

if [ "$FULL_UPLOAD" = true ]; then
  ADDED_MODIFIED_FILE=$(add_temp)
  jq -r 'keys[]' "$CURRENT_MANIFEST_FILE" | sort > "$ADDED_MODIFIED_FILE"
  ADDED_COUNT=$(wc -l < "$ADDED_MODIFIED_FILE")

  DELETED_FILE=$(add_temp)
  : > "$DELETED_FILE"
  DELETED_COUNT=0

  UNCHANGED_COUNT=0
else
  ADDED_MODIFIED_FILE=$(add_temp)
  DELETED_FILE=$(add_temp)
  UNCHANGED_FILE=$(add_temp)

  jq -rn --slurpfile prev "$PREV_MANIFEST_FILE" --slurpfile curr "$CURRENT_MANIFEST_FILE" '
    ($prev[0] // {}) as $p |
    ($curr[0]) as $c |
    [$c | keys[] | . as $k | select(($p[$k] // null) != $c[$k])] |
    sort |
    .[]
  ' > "$ADDED_MODIFIED_FILE"

  jq -rn --slurpfile prev "$PREV_MANIFEST_FILE" --slurpfile curr "$CURRENT_MANIFEST_FILE" '
    ($prev[0] // {}) as $p |
    ($curr[0]) as $c |
    [$p | keys[] | . as $k | select(($c[$k] // null) == null)] |
    sort |
    .[]
  ' > "$DELETED_FILE"

  jq -n --slurpfile prev "$PREV_MANIFEST_FILE" --slurpfile curr "$CURRENT_MANIFEST_FILE" '
    ($prev[0] // {}) as $p |
    ($curr[0]) as $c |
    [$c | keys[] | . as $k | select($p[$k] == $c[$k])] |
    length
  ' > "$UNCHANGED_FILE"

  ADDED_COUNT=$(wc -l < "$ADDED_MODIFIED_FILE")
  DELETED_COUNT=$(wc -l < "$DELETED_FILE")
  UNCHANGED_COUNT=$(cat "$UNCHANGED_FILE")
fi

DIFF_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")

echo "Manifest diff: ${ADDED_COUNT} added/modified, ${DELETED_COUNT} deleted, ${UNCHANGED_COUNT} unchanged"

if [ "$ADDED_COUNT" -eq 0 ] && [ "$DELETED_COUNT" -eq 0 ]; then
  echo "Nothing to deploy. Exiting."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 8: Upload changed files
# ---------------------------------------------------------------------------

STEP_START=$(get_timestamp)

echo "Uploading ${ADDED_COUNT} file(s) to S3..."
upload_pids=()
upload_failed=false

while IFS= read -r rel_path; do
  aws s3 cp "${SITE_DIR}/${rel_path}" "s3://${S3_BUCKET}/${S3_FOLDER}/${rel_path}" --region us-east-1 &
  upload_pids+=($!)
  if [ ${#upload_pids[@]} -ge "$MAX_PARALLEL_UPLOADS" ]; then
    wait "${upload_pids[0]}" || upload_failed=true
    upload_pids=("${upload_pids[@]:1}")
  fi
done < "$ADDED_MODIFIED_FILE"

for pid in "${upload_pids[@]}"; do
  wait "$pid" || upload_failed=true
done

if [ "$upload_failed" = true ]; then
  echo "ERROR: One or more uploads failed. Exiting."
  exit 1
fi

UPLOAD_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")
echo "  → S3 uploads complete in ${UPLOAD_TIME}s"

# Delete removed files
STEP_START=$(get_timestamp)

if [ "$DELETED_COUNT" -gt 0 ]; then
  echo "Deleting ${DELETED_COUNT} file(s) from S3..."
  delete_pids=()
  delete_failed=false

  while IFS= read -r rel_path; do
    aws s3 rm "s3://${S3_BUCKET}/${S3_FOLDER}/${rel_path}" --region us-east-1 &
    delete_pids+=($!)
    if [ ${#delete_pids[@]} -ge "$MAX_PARALLEL_UPLOADS" ]; then
      wait "${delete_pids[0]}" || delete_failed=true
      delete_pids=("${delete_pids[@]:1}")
    fi
  done < "$DELETED_FILE"

  for pid in "${delete_pids[@]}"; do
    wait "$pid" || delete_failed=true
  done

  if [ "$delete_failed" = true ]; then
    echo "ERROR: One or more deletes failed. Exiting."
    exit 1
  fi
fi

DELETE_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")
echo "  → S3 deletes complete in ${DELETE_TIME}s"

# ---------------------------------------------------------------------------
# Step 9: Update the manifest in S3
# ---------------------------------------------------------------------------

STEP_START=$(get_timestamp)
echo "Updating manifest in S3..."
aws s3 cp "$CURRENT_MANIFEST_FILE" "s3://${S3_BUCKET}/${MANIFEST_KEY}" --region us-east-1
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to update manifest in S3. Exiting."
  echo "WARNING: The next build will diff against stale state. Consider running with FORCE_FULL=true on the next deploy."
  exit 1
fi

MANIFEST_WRITE_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")
echo "  → Manifest updated in ${MANIFEST_WRITE_TIME}s"

# ---------------------------------------------------------------------------
# Step 10: Purge Cloudflare cache
# ---------------------------------------------------------------------------

STEP_START=$(get_timestamp)
echo "Purging Cloudflare cache..."

CF_TOKEN=$(doppler secrets get CLOUDFLARE_API_TOKEN --project cyberknight-s3-sync --config prd --plain)

HOSTS_JSON=$(printf '%s\n' "${CF_HOSTNAMES[@]}" | jq -R . | jq -s .)

PURGE_RESPONSE_FILE=$(add_temp)

HTTP_CODE=$(curl -s -o "$PURGE_RESPONSE_FILE" -w "%{http_code}" \
  -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"hosts\": ${HOSTS_JSON}}")

PURGE_TIME=$(perl -e "printf '%.2f', $(get_timestamp) - $STEP_START")

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: Cloudflare cache purge returned HTTP ${HTTP_CODE}."
  cat "$PURGE_RESPONSE_FILE" >&2
  echo "ERROR: Cloudflare cache purge failed. Exiting."
  exit 1
fi

echo "  → Cache purge complete in ${PURGE_TIME}s"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

END_TIME=$(get_timestamp)
DURATION=$(perl -e "printf '%.2f', $END_TIME - $START_TIME")

echo ""
echo "=== Deploy completed at $(date) ==="
echo "=== Total deploy time: ${DURATION}s ==="
echo ""
echo "Step-by-step breakdown:"
echo "  1. Manifest fetch:     ${PREV_FETCH_TIME}s"
echo "  2. Hashing:            ${HASH_TIME}s"
echo "  3. Diff:               ${DIFF_TIME}s"
echo "  4. S3 uploads:         ${UPLOAD_TIME}s"
echo "  5. S3 deletes:         ${DELETE_TIME}s"
echo "  6. Manifest write:     ${MANIFEST_WRITE_TIME}s"
echo "  7. Cache purge:        ${PURGE_TIME}s"
