#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared deployment configuration/functions.

source "$DIR/common.sh"

ROUTER_CONTAINER="${ROUTER_CONTAINER:-orders-router}"

NEW_COLOR="${1:-}"
VERSION="${2:-}"

if [[ -z "$NEW_COLOR" || -z "$VERSION" ]]; then
echo "Usage: $0 <blue|green> <version>"
exit 1
fi

case "$NEW_COLOR" in
blue)
NEW_CONTAINER="orders-blue"
CANDIDATE_PORT="8081"
;;
green)
NEW_CONTAINER="orders-green"
CANDIDATE_PORT="8082"
;;
*)
echo "FAIL - invalid color: $NEW_COLOR"
echo "Usage: $0 <blue|green> <version>"
exit 1
;;
esac

log "==== TRAFFIC SWITCH ===="
log "Routing production traffic (host port 8080) to: $NEW_COLOR ($NEW_CONTAINER:3000)"
log "Candidate port: $CANDIDATE_PORT"
log "========================="

TEMPLATE="$DIR/../router/active-backend.template.conf"
ROUTER_TMP="$(mktemp)"

cleanup() {
rm -f "$ROUTER_TMP"
}

trap cleanup EXIT

if [[ ! -f "$TEMPLATE" ]]; then
log "FAIL - router template not found: $TEMPLATE"
exit 1
fi

if ! docker inspect "$ROUTER_CONTAINER" >/dev/null 2>&1; then
log "FAIL - router container '$ROUTER_CONTAINER' does not exist"
exit 1
fi

if ! docker inspect "$NEW_CONTAINER" >/dev/null 2>&1; then
log "FAIL - target container '$NEW_CONTAINER' does not exist"
exit 1
fi

log "Generating nginx configuration..."

python - "$TEMPLATE" "$ROUTER_TMP" "$NEW_COLOR" "$NEW_CONTAINER" <<'PY'
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
color = sys.argv[3]
container = sys.argv[4]

content = template_path.read_text(encoding="utf-8")

content = content.replace("**ACTIVE_COLOR**", color)
content = content.replace("**ACTIVE_CONTAINER**", container)

output_path.write_text(content, encoding="utf-8")
PY

if [[ ! -s "$ROUTER_TMP" ]]; then
log "FAIL - generated nginx configuration is empty"
exit 1
fi

log "Copying generated configuration into router container..."

docker exec -i "$ROUTER_CONTAINER" 
sh -c 'cat > /etc/nginx/conf.d/active-backend.conf' 
< "$ROUTER_TMP"

log "Testing nginx configuration..."

docker exec "$ROUTER_CONTAINER" nginx -t

log "Reloading nginx..."

docker exec "$ROUTER_CONTAINER" nginx -s reload

sleep 2

log "Verifying router status..."

ROUTER_STATUS="$(curl -fsS http://localhost:8080/router-status)"

echo "$ROUTER_STATUS"

if [[ "$ROUTER_STATUS" != "active-color: $NEW_COLOR" ]]; then
log "FAIL - router active color is not '$NEW_COLOR'"
log "Actual response: $ROUTER_STATUS"
exit 1
fi

log "Verifying production version..."

VERSION_RESPONSE="$(curl -fsS http://localhost:8080/version)"

echo "$VERSION_RESPONSE"

if ! echo "$VERSION_RESPONSE" | grep -q ""version": "$VERSION""; then
log "FAIL - router is serving an unexpected version"
exit 1
fi

if ! echo "$VERSION_RESPONSE" | grep -q ""color": "$NEW_COLOR""; then
log "FAIL - router is serving an unexpected color"
exit 1
fi

log "PASS - production traffic switched successfully"
log "Active color: $NEW_COLOR"
log "Version: $VERSION"
log "Router: http://localhost:8080"
log "========================="
