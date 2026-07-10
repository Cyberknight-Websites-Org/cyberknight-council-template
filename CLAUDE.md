# Cyberknight Council Template

This repository is the Jekyll-based static site template that generates individual websites for Knights of Columbus councils. Each council gets a site deployed at `council-{N}.cyberknight-websites.com` (and optionally a custom domain). The template pulls live data from the Cyberknight Secure Portal API and converts it into fast, scalable static HTML.

This is a stateless, repeatable blueprint: the same repository is cloned and built for each council, with council number and API endpoint as the only variables. GitHub Actions triggers a rebuild of all council sites on every push to `main`.

## Build Pipeline

The build process (`server_build_script.sh`) has four stages:

1. **Fresh git clone** of this repository
2. **`sync_data.rb`** (`_scripts/sync_data.rb`) — pulls all council data from the Secure Portal API (`/public_api/get_all_council_info/{council_number}`) and writes Jekyll-compatible markdown files into `_events/`, `_posts/`, and `_announcements/` collections
3. **Jekyll build** inside Docker (`cyberknight-council-template-builder`, based on `ruby:3.3.6-alpine`)
4. **Manifest-based S3 deploy** — SHA256 hashes track what changed; only modified files upload, followed by Cloudflare cache purge of affected URL prefixes

### Build Script

```bash
sudo ./server_build_script.sh \
  COUNCIL_NUMBER=2431 \
  JEKYLL_DIR=/tmp/council-2431-build \
  JEKYLL_BUILDER_IMAGE=cyberknight-council-template-builder \
  NGINX_DIR=/
```

**Arguments (all `KEY=VALUE` style):**
- `COUNCIL_NUMBER` — council number. Determines S3 folder and Cloudflare hostname.
- `JEKYLL_DIR` — directory for the git clone and Jekyll build.
- `JEKYLL_BUILDER_IMAGE` — Docker image name for building.
- `FORCE_FULL=true` — optional, skip manifest diff and re-upload all files.

### Deploy Script

```bash
sudo ./deploy.sh \
  COUNCIL_NUMBER=2431 \
  JEKYLL_DIR=/tmp/council-2431-build \
  JEKYLL_BUILDER_IMAGE=cyberknight-council-template-builder \
  NGINX_DIR=/
```

Deploy-only: takes existing `_site/` and deploys with manifest-based diff.

### Argument Style Note

This repo uses `KEY=VALUE` style arguments. The corporate website (`cyberknight-corporate-website`) uses `--flag` style. Do not switch council scripts to `--flag` style without also updating the webhook caller in `cyberknight-build-webhooks`.

## Local Development

```bash
# Serve with data sync for council 2431
./jekyll_serve_dev.sh

# With custom council and port
./jekyll_serve_dev.sh 2431 https://secure.cyberknight-websites.com 4000
```

The dev script runs `sync_data.rb` then starts Jekyll with `--watch` on the specified port.

### Docker Image

Build the builder image locally:

```bash
docker build -t cyberknight-council-template-builder .
```

## Key Features

- **Leaflet.js interactive maps** — parish locations on homepage, event locations on event pages
- **Custom site support** — `sync_data.rb` detects a `website_assets_zip_url` in the API response and extracts agent-generated layouts/SCSS over the default template
- **Asset fingerprinting** (`_scripts/asset_fingerprint.rb`) — MD5 hashes appended to CSS/JS filenames for cache busting; sourcemaps removed before deploy
- **Pre-sorting hook** (`_scripts/presort_collections.rb`) — collections sorted in-place post-read so Liquid templates don't re-sort
- **Custom sitemap generator** (`_scripts/sitemap_generator.rb`) — fast Ruby XML generation instead of Liquid templates
- **Configurable homepage sections** — announcements, events, parishes, posts each toggleable in `_config.yml`
- **Snow effect** — seasonal toggle in `_config.yml` (`snow_effect.enabled`, with `start_date` / `end_date`)

## Collections

| Collection | Output Path | Contents |
|------------|-------------|---------|
| `_events/` | `/events/{id}` | Council events with maps, flyers, galleries |
| `_posts/` | `/posts/{id}` | Council news with OpenGraph metadata |
| `_announcements/` | `/announcements/{id}` | Email/SMS announcements with attachments |

All collections are populated by `sync_data.rb` at build time from the Secure Portal API.

## Jekyll Configuration

Key settings in `_config.yml`:

- **Permalinks**: `/:slug` for pages, `/events/:year/:month/:slug` and `/announcements/:year/:month/:slug` for collections
- **jekyll-archives** enabled for year, month, and tag archives on posts
- **Time zone**: `US/Pacific`
- **Date formats**: configurable per content type (`events_date_format`, `posts_date_format`)

## Infrastructure

- **S3 bucket**: `cyberknight-websites`, folder `council-<N>/`
- **Served via**: `cyberknight-sites-worker` at `council-N.cyberknight-websites.com`
- **Custom domains**: Cloudflare for SaaS with KV lookup in `cyberknight-sites-worker`
- **Credentials**: Doppler project `cyberknight-s3-sync`, config `prd`
- **Manifest**: stored at `s3://cyberknight-websites/council-<N>/.manifest.json`
- **CF purge chunk size**: 100 URLs per request
- **Logs**: written to `~/logs/cyberknight-council-template/`

## Integration Points

- **Triggered by**: `cyberknight-build-webhooks` — `build-council-website` and `build-all-council-websites` webhooks
- **Data source**: `cyberknight-secure-webapp` public API
- **Served by**: `cyberknight-sites-worker` Cloudflare Worker
- **Custom sites**: generated by `cyberknight-website-builder`, detected and applied by `sync_data.rb`

## Requirements

- Docker (for production builds)
- AWS CLI
- Cloudflare API token (via Doppler)
- Root access (scripts require root for deployment)
