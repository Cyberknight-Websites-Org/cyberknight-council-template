# cyberknight-council-template

## Building the Docker Image

The production build process (`server_build_script.sh`) requires a Docker image called `cyberknight-council-template-builder`. This image contains Ruby, Jekyll, and all necessary dependencies.

From within the project directory run the following to build it: `docker build -t cyberknight-council-template-builder .`

---

## Build and Deploy

### `server_build_script.sh` — full pipeline (clone → data sync → build → deploy)

Intended for production use. Clones a fresh copy of the repository, syncs council data, builds the Jekyll site via Docker, and deploys to S3 with Cloudflare cache purge.

```bash
sudo ./server_build_script.sh \
  COUNCIL_NUMBER=2431 \
  JEKYLL_DIR=/tmp/council-2431-build \
  JEKYLL_BUILDER_IMAGE=cyberknight-council-template-builder \
  NGINX_DIR=/var/www/nginx
```

**Arguments (all `KEY=VALUE` style):**
- `COUNCIL_NUMBER` — council number (e.g. `2431`). Determines the S3 folder and Cloudflare hostname.
- `JEKYLL_DIR` — directory used for the git clone and Jekyll build.
- `JEKYLL_BUILDER_IMAGE` — name of the Docker image used for building.
- `NGINX_DIR` — accepted for backward compatibility with webhook callers; not used for deployment (site goes to S3).

**Optional:**
- `FORCE_FULL=true` — skip the manifest diff and re-upload all files regardless of what changed.

```bash
sudo ./server_build_script.sh COUNCIL_NUMBER=2431 JEKYLL_DIR=/tmp/council-2431-build \
  JEKYLL_BUILDER_IMAGE=cyberknight-council-template-builder NGINX_DIR=/ FORCE_FULL=true
```

Logs are written to `/home/julian/logs/cyberknight-council-template/build_TIMESTAMP.log` (or `./logs/` if that directory is not writable).

---

### `deploy.sh` — deploy only (no clone or build)

Deploys an existing `JEKYLL_DIR/_site/` directory to S3 using a manifest-based diff — only files that have changed since the last deploy are uploaded or deleted. Purges only the affected URLs from Cloudflare's cache.

```bash
sudo ./deploy.sh \
  COUNCIL_NUMBER=2431 \
  JEKYLL_DIR=/tmp/council-2431-build \
  JEKYLL_BUILDER_IMAGE=cyberknight-council-template-builder \
  NGINX_DIR=/
```

**Arguments (all `KEY=VALUE` style):**
- `COUNCIL_NUMBER` — **(required)** council number. Drives the S3 folder (`council-<N>/`), manifest path (`council-<N>/.manifest.json`), and Cloudflare purge hostname (`council-<N>.cyberknight-websites.com`).
- `JEKYLL_DIR` — **(required)** path to the directory containing `_site/`.
- `JEKYLL_BUILDER_IMAGE` — **(required)** Docker image name (accepted but not used by deploy.sh itself).
- `NGINX_DIR` — accepted for interface compatibility; not used for deployment.

**Optional:**
- `FORCE_FULL=true` — skip the manifest diff and re-upload all files, regenerating the manifest from scratch.

```bash
sudo ./deploy.sh COUNCIL_NUMBER=2431 JEKYLL_DIR=/tmp/council-2431-build \
  JEKYLL_BUILDER_IMAGE=cyberknight-council-template-builder NGINX_DIR=/ FORCE_FULL=true
```

**Dry-run invocation (for isolated testing):**

```bash
mkdir -p /tmp/cyberknight-dry-run/_site
echo "<html><body>Test</body></html>" > /tmp/cyberknight-dry-run/_site/index.html

DOPPLER_TOKEN="<token>" sudo -E ./deploy.sh \
  JEKYLL_DIR=/tmp/cyberknight-dry-run \
  COUNCIL_NUMBER=2431 \
  JEKYLL_BUILDER_IMAGE=cyberknight-council-template-builder \
  NGINX_DIR=/
```

**Requirements:** must be run as root. Requires `aws`, `doppler`, `jq`, `sha256sum`, `curl`, `pass`, and `perl` in PATH, and the `cyberknight/s3-sync-doppler-token` key in the root `pass` store (or `DOPPLER_TOKEN` pre-set in the environment).

Logs are written to `~/logs/cyberknight-council-template/deploy_TIMESTAMP.log` (or `./logs/` if that directory is not writable).

---

## Infrastructure

- **S3 bucket:** `cyberknight-websites`, folder `council-<COUNCIL_NUMBER>/`
- **Cloudflare zone:** `council-<COUNCIL_NUMBER>.cyberknight-websites.com`
- **Credentials:** managed via Doppler project `cyberknight-s3-sync`, config `prd`
- **Manifest:** stored at `s3://cyberknight-websites/council-<COUNCIL_NUMBER>/.manifest.json`
- **CF purge chunk size:** 100 URLs per request (plan limit for this zone; the corporate zone uses 500)

---

## Argument style asymmetry vs corporate website

The corporate website (`cyberknight-corporate-website`) uses `--flag` style arguments:

```bash
./deploy.sh --force-full          # corporate
./build_www.sh --force-full       # corporate
```

The council template uses `KEY=VALUE` style, consistent with `server_build_script.sh`:

```bash
./deploy.sh ... FORCE_FULL=true   # council
```

This is intentional — the council webhook caller already uses `KEY=VALUE` for all arguments, so `deploy.sh` follows the same convention. Future maintainers: do not switch council scripts to `--flag` style without also updating the webhook caller.
