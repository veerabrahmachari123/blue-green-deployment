#!/usr/bin/env bash

# Jenkins stage: Traffic Switch

#

# The router owns its active-backend.conf.

# Jenkins must NOT rewrite a host-side file because the running

# orders-router may have been created from a different workspace.

#

# This script:

# 1. Generates the desired backend configuration.

# 2. Copies it into orders-router.

# 3. Validates nginx configuration.

# 4. Reloads nginx.

# 5. Verifies production traffic through host port 8080.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

NEW_COLOR="${1:?usage: switch-traffic.sh <new_color> <expected_version>}"
EXPECTED_VERSION="${2:?}"

NEW_PORT="$(color_port "$NEW_COLOR")"
NEW_CONTAINER="orders-${NEW_COLOR}"

log "==== TRAFFIC SWITCH ===="
log "Routing production traffic (host port 8080) to: ${NEW_COLOR} (${NEW_CONTAINER}:3000)"
log "Candidate port: ${NEW_PORT}"
log "========================="

case "$NEW_COLOR" in
blue|green)
;;
*)
fail "invalid color '${NEW_COLOR}' - expected blue or green"
;;
esac

if ! docker inspect "$NEW_CONTAINER" >/dev/null 2>&1; then
fail "candidate container '${NEW_CONTAINER}' does not exist"
fi

if ! docker inspect -f '{{.State.Running}}' "$NEW_CONTAINER" 2>/dev/null | grep -q '^true$'; then
fail "candidate container '${NEW_CONTAINER}' is not running"
fi

ROUTER_TMP="$(mktemp)"

cleanup() {
rm -f "$ROUTER_TMP"
}

trap cleanup EXIT

cat > "$ROUTER_TMP" <<EOF

# Rewritten by scripts/switch-traffic.sh and loaded by nginx.

# ACTIVE_COLOR=${NEW_COLOR}

upstream orders_active {
server ${NEW_CONTAINER}:3000;
}

server {
listen 8080;

```
location /router-status {
    return 200 "active-color: ${NEW_COLOR}\n";
    add_header Content-Type text/plain;
}

location / {
    proxy_pass http://orders_active;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_connect_timeout 2s;
    proxy_read_timeout 5s;
}
```

}
EOF

log "Copying active backend configuration into ${ROUTER_CONTAINER}"

docker cp 
"$ROUTER_TMP" 
"${ROUTER_CONTAINER}:/etc/nginx/conf.d/active-backend.conf"

docker exec "$ROUTER_CONTAINER" nginx -t

docker exec "$ROUTER_CONTAINER" nginx -s reload

ok "router reloaded, pointing at $NEW_COLOR"

sleep 1

ROUTER_STATUS="$(curl -sf "http://localhost:8080/router-status")" 
|| fail "router did not respond on /router-status after switch"

EXPECTED_STATUS="active-color: ${NEW_COLOR}"

if [ "$ROUTER_STATUS" != "$EXPECTED_STATUS" ]; then
fail "router reports '${ROUTER_STATUS}', expected '${EXPECTED_STATUS}'"
fi

ok "router active color confirmed: $NEW_COLOR"

ROUTER_VERSION_JSON="$(curl -sf "http://localhost:8080/version")" 
|| fail "router did not respond on 8080 after switch - production is degraded"

GOT_VERSION="$(
echo "$ROUTER_VERSION_JSON" |
grep -o '"version": *"[^"]*"' |
sed -E 's/.*"([^"]+)"$/\1/'
)"

if [ "$GOT_VERSION" != "$EXPECTED_VERSION" ]; then
fail "router is serving version '$GOT_VERSION' through port 8080, expected '$EXPECTED_VERSION'"
fi

ok "verified: production traffic on port 8080 is now served by $NEW_COLOR, version $GOT_VERSION"

log "==== TRAFFIC SWITCH COMPLETE ===="
