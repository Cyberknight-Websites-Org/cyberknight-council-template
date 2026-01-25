---
name: serve-jekyll
description: Serve Jekyll site accessible via VPN tunnel and Playwright. Use when the user asks to browse the Jekyll site, visit council-test.cyberknight-websites.com URLs, or access the Jekyll server with Playwright.
allowed-tools: Bash(./jekyll_serve_dev.sh, bundle exec*, ss *), mcp__playwright__browser_*
---

# Serve Jekyll Site via VPN

This skill starts the Jekyll development server configured for access through a WireGuard VPN tunnel via nginx reverse proxy.

## Quick Start

```bash
./jekyll_serve_dev.sh
```

The server will be accessible at: `http://council-test.cyberknight-websites.com` (via VPN)

## Configuration Details

### Network Binding
The Jekyll server binds to `0.0.0.0:4000` (jekyll_serve_dev.sh:7) to allow both nginx proxy and Playwright access:
- **Host**: `0.0.0.0` - Accepts connections from all interfaces
- **Port**: `4000` - Default development port

**Why 0.0.0.0**: The nginx reverse proxy needs to access the Jekyll server. Binding to all interfaces ensures both nginx and Playwright can reach it.

### Nginx Reverse Proxy
The site is proxied through nginx at `/etc/nginx/sites-enabled/council_test_cyberknight.conf`:

```nginx
server {
    listen 10.200.200.1:80;
    server_name council-test.cyberknight-websites.com;

    location / {
        proxy_pass http://127.0.0.1:4000;
        include /etc/nginx/proxy_params;
    }
}
```

**Key Points**:
- Nginx listens on WireGuard interface: `10.200.200.1:80`
- Proxies to local Jekyll server: `0.0.0.0:4000` (changed from `127.0.0.1` for Playwright compatibility)
- DNS resolves `council-test.cyberknight-websites.com` → `10.200.200.1`

## Accessing via Playwright

The Playwright MCP server runs in a Docker container with `--network host` mode, giving it direct access to the host's network stack.

### Why Host Networking

The Playwright MCP uses `--network host` instead of Docker's default bridge networking.

**Problem**: With bridge networking, containers cannot reliably access services on the host via the bridge gateway IP (`172.17.0.1`). Connection attempts time out even though the host can reach itself at that IP. This is a Docker networking limitation where packets from containers destined for the host's bridge interface aren't properly routed back to userspace.

**Solution**: Using `--network host` gives the container direct access to the host's network stack, allowing it to use `127.0.0.1` to reach local services like the Jekyll server.

**Configuration location**: `~/.claude.json` under `projects["<project-path>"].mcpServers.playwright`

```json
"playwright": {
  "command": "docker",
  "args": ["run", "-i", "--rm", "--init", "--pull=always", "--network", "host", "mcr.microsoft.com/playwright/mcp"]
}
```

### Direct Access URL

Playwright should access the Jekyll server using:
```
http://127.0.0.1:4000
```

**Why this works**:
- Playwright container uses `--network host` mode (configured in `~/.claude.json`)
- With host networking, `127.0.0.1` inside the container refers to the host's localhost
- This allows direct access to Jekyll without any network translation

### URL Translation for council-test.cyberknight-websites.com

When the user provides a URL starting with `http://council-test.cyberknight-websites.com`, translate it for Playwright access:

**User-provided URL format:**
```
http://council-test.cyberknight-websites.com/path
```

**Playwright access format:**
```
http://127.0.0.1:4000/path
```

### Translation Examples

| User Request | Playwright URL |
|--------------|----------------|
| `http://council-test.cyberknight-websites.com/` | `http://127.0.0.1:4000/` |
| `http://council-test.cyberknight-websites.com/calendar.html` | `http://127.0.0.1:4000/calendar.html` |
| `http://council-test.cyberknight-websites.com/2431/announcements` | `http://127.0.0.1:4000/2431/announcements` |

### Implementation Steps

1. **Detect** if user provides a URL starting with `http://council-test.cyberknight-websites.com`
2. **Translate** the URL:
   - Remove: `http://council-test.cyberknight-websites.com`
   - Add: `http://127.0.0.1:4000`
   - Keep: the entire path unchanged
3. **Navigate** using `mcp__playwright__browser_navigate`

### Available Playwright Tools

Once navigated, you can:
- Take snapshots with `mcp__playwright__browser_snapshot`
- Take screenshots with `mcp__playwright__browser_take_screenshot`
- Click elements with `mcp__playwright__browser_click`
- Fill forms with `mcp__playwright__browser_fill_form`
- Evaluate JavaScript with `mcp__playwright__browser_evaluate`

### Why Translation is Needed

- `council-test.cyberknight-websites.com` resolves to `10.200.200.1` (WireGuard VPN interface)
- Playwright container cannot access the VPN interface directly
- Using `127.0.0.1:4000` accesses Jekyll directly on the host
- This ensures Playwright can reach the Jekyll server reliably

### LiveReload Issue ⚠️

**IMPORTANT**: The `--livereload` flag is **disabled** for VPN access.

**Why**: LiveReload injects JavaScript that tries to establish a WebSocket connection to port 35729. This connection:
- Cannot traverse the nginx reverse proxy
- Causes the browser to hang indefinitely waiting for the WebSocket
- Results in infinite loading with no page render

**Symptom**: If LiveReload is enabled, the page will show infinite loading. When Jekyll is stopped, you'll see `502 Bad Gateway`, confirming nginx is working but the LiveReload JS is blocking.

**Solution**: Line 33 of `jekyll_serve_dev.sh` uses:
```bash
bundle exec jekyll serve --host "$HOST" --port "$PORT"
# NOT: --livereload
```

**Trade-off**: Manual browser refresh required to see changes.

## Script Arguments

```bash
./jekyll_serve_dev.sh [COUNCIL_NUMBER] [API_URL] [PORT]
```

- **COUNCIL_NUMBER**: Knights of Columbus council ID (default: 2431)
- **API_URL**: API endpoint for data sync (default: https://secure.cyberknight-websites.com)
- **PORT**: Server port (default: 4000)

## Testing

### From Server (Local)
```bash
curl http://127.0.0.1:4000/
curl http://0.0.0.0:4000/
curl -H "Host: council-test.cyberknight-websites.com" http://10.200.200.1/
```

### From Docker Container / Playwright
```bash
# Test from within a Docker container (with --network host)
curl http://127.0.0.1:4000/
```

Or use Playwright:
```
mcp__playwright__browser_navigate(url="http://127.0.0.1:4000/")
mcp__playwright__browser_snapshot()
```

### From VPN Client
```bash
# Test connectivity
ping 10.200.200.1

# Test DNS
nslookup council-test.cyberknight-websites.com

# Test HTTP
curl http://council-test.cyberknight-websites.com/
```

## Troubleshooting

### Infinite Loading
- **Cause**: LiveReload is enabled
- **Fix**: Remove `--livereload` from jekyll_serve_dev.sh:33

### 502 Bad Gateway
- **Cause**: Jekyll server not running
- **Fix**: Start with `./jekyll_serve_dev.sh`

### Connection Timeout
- **Check**: WireGuard tunnel is active
- **Check**: DNS resolves correctly
- **Check**: No firewall blocking port 80

### Port 4000 Already in Use
```bash
# Find process
ss -tlnp | grep :4000

# Stop background Jekyll
/tasks stop <task-id>
```

### Playwright Cannot Connect
- **Check**: Jekyll server is running (`ss -tlnp | grep :4000`)
- **Check**: Playwright MCP uses `--network host` (configured in `~/.claude.json`)
- **Check**: Using correct URL format `http://127.0.0.1:4000/`
- **Check**: Restart Claude Code after modifying MCP configuration

## Background Task Management

To run in background:
```bash
# Claude Code command
task_id=$(./jekyll_serve_dev.sh &)

# Stop later
/tasks stop <task-id>
```

## Complete Workflow Examples

### Example 1: Start Jekyll and Access with Playwright

**User Request:** "Start the Jekyll server and open it in Playwright"

**Actions:**
1. Run startup script:
   ```bash
   ./jekyll_serve_dev.sh
   ```
   (This runs in foreground, so you may want to run in background)

2. Navigate with Playwright:
   ```
   mcp__playwright__browser_navigate(url="http://127.0.0.1:4000/")
   ```

3. Take snapshot to show the page:
   ```
   mcp__playwright__browser_snapshot()
   ```

4. Report to user: "Jekyll server is running and accessible via Playwright at http://127.0.0.1:4000/"

### Example 2: Visit Specific Page Using council-test.cyberknight-websites.com URL

**User Request:** "Visit http://council-test.cyberknight-websites.com/calendar.html"

**Actions:**
1. Recognize URL starts with `http://council-test.cyberknight-websites.com`

2. Translate URL:
   - Original: `http://council-test.cyberknight-websites.com/calendar.html`
   - Translated: `http://127.0.0.1:4000/calendar.html`

3. Navigate to translated URL:
   ```
   mcp__playwright__browser_navigate(url="http://127.0.0.1:4000/calendar.html")
   ```

4. Take snapshot:
   ```
   mcp__playwright__browser_snapshot()
   ```

5. Report to user: "Navigated to the calendar page"

### Example 3: Run Jekyll in Background

**User Request:** "Start Jekyll in the background so I can browse it with Playwright"

**Actions:**
1. Start Jekyll in background:
   ```bash
   ./jekyll_serve_dev.sh
   ```
   (Use run_in_background parameter in Bash tool)

2. Wait for server to start (check output or wait a few seconds)

3. Navigate with Playwright:
   ```
   mcp__playwright__browser_navigate(url="http://127.0.0.1:4000/")
   ```

4. Take snapshot and report status

## Security Notes

- Jekyll binds to `0.0.0.0:4000` for nginx reverse proxy access
- Port 4000 is accessible on all network interfaces but is non-standard and typically blocked by firewalls
- External access via VPN requires WireGuard connection (10.200.200.0/24 network)
- Nginx listens only on VPN interface (`10.200.200.1:80`), not `0.0.0.0:80`
- Playwright MCP uses `--network host` for direct localhost access
- Development server - not for production use
