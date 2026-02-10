#!/bin/sh
set -e

TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"
TS_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
TS_HOSTNAME="${TS_HOSTNAME:-openclaw-gateway}"

# Start tailscaled in userspace networking mode (no root/tun required)
tailscaled \
  --state="${TS_STATE_DIR}/tailscaled.state" \
  --socket="${TS_SOCKET}" \
  --tun=userspace-networking \
  --port=0 &

# Wait for tailscaled to become ready
echo "[entrypoint] Waiting for tailscaled..."
for i in $(seq 1 30); do
  if tailscale --socket="${TS_SOCKET}" status >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Authenticate with Tailscale
if [ -n "${TS_AUTHKEY:-}" ]; then
  echo "[entrypoint] Authenticating with Tailscale..."
  tailscale --socket="${TS_SOCKET}" up \
    --authkey="${TS_AUTHKEY}" \
    --hostname="${TS_HOSTNAME}" \
    --reset
fi

# Configure Tailscale Serve: HTTPS -> local HTTP gateway
echo "[entrypoint] Configuring Tailscale Serve on port ${TS_PORT}..."
tailscale --socket="${TS_SOCKET}" serve --bg "http://127.0.0.1:${TS_PORT}"

echo "[entrypoint] Tailscale ready"
tailscale --socket="${TS_SOCKET}" serve status 2>/dev/null || true

# Run the main command (gateway)
exec "$@"
