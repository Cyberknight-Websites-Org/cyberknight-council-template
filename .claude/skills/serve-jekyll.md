---
name: serve-jekyll
description: Serve Jekyll site accessible via VPN tunnel
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
The Jekyll server binds to `0.0.0.0:4000` (jekyll_serve_dev.sh:7) to allow nginx to proxy requests:
- **Host**: `0.0.0.0` - Accepts connections from all network interfaces
- **Port**: `4000` - Default development port

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
- Proxies to local Jekyll server: `127.0.0.1:4000`
- DNS resolves `council-test.cyberknight-websites.com` → `10.200.200.1`

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
curl -H "Host: council-test.cyberknight-websites.com" http://10.200.200.1/
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

## Background Task Management

To run in background:
```bash
# Claude Code command
task_id=$(./jekyll_serve_dev.sh &)

# Stop later
/tasks stop <task-id>
```

## Security Notes

- Server only accessible via WireGuard VPN (10.200.200.0/24 network)
- Not exposed to public internet
- Nginx listens only on VPN interface, not 0.0.0.0:80
- Development server - not for production use
