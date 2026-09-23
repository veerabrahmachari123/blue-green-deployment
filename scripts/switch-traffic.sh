#!/usr/bin/env bash
# Jenkins stage: Traffic Switch
# Only ever called AFTER Container Validation, Application Health Check and
# Integration Check have all passed (Phase 3: "candidate must pass health
# and application validation before traffic is switched").
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

NEW_COLOR="${1:?usage: switch-traffic.sh <new_color> <expected_version>}"
EXPECTED_VERSION="${2:?}"
NEW_PORT=$(color_port "$NEW_COLOR")
NEW_CONTAINER="orders-${NEW_COLOR}"

log "==== TRAFFIC SWITCH ===="
log "Routing production traffic (host port 8080) to: $NEW_COLOR ($NEW_CONTAINER:3000)"
log "========================="

cat > "$ROUTER_CONF" <<EOF
# Rewritten by scripts/switch-traffic.sh and reloaded by nginx -s reload.
# ACTIVE_COLOR=${NEW_COLOR}
upstream orders_active {
    server ${NEW_CONTAINER}:3000;
}

server {
    listen 8080;

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
}
EOF

docker exec "$ROUTER_CONTAINER" nginx -t
docker exec "$ROUTER_CONTAINER" nginx -s reload
ok "router reloaded, pointing at $NEW_COLOR"

# Verify through the ROUTER (port 8080), i.e. exactly what a real user hits.
sleep 1
ROUTER_VERSION_JSON=$(curl -sf "http://localhost:8080/version") || fail "router did not respond on 8080 after switch - production is now degraded, escalate immediately"
GOT_VERSION=$(echo "$ROUTER_VERSION_JSON" | grep -o '"version": *"[^"]*"' | sed -E 's/.*"([^"]+)"$/\1/')
[ "$GOT_VERSION" = "$EXPECTED_VERSION" ] || fail "router is serving version '$GOT_VERSION' through port 8080, expected '$EXPECTED_VERSION'"

ok "verified: production traffic on port 8080 is now served by $NEW_COLOR, version $GOT_VERSION"
