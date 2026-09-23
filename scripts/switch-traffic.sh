#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROUTER_CONTAINER="orders-router"
ROUTER_PORT="8080"

NEW_COLOR="${1:-}"
VERSION="${2:-}"

log() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

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
        log "FAIL - invalid color: $NEW_COLOR"
        exit 1
        ;;
esac

TEMPLATE="$DIR/../router/active-backend.template.conf"
ROUTER_TMP="$(mktemp)"

cleanup() {
    rm -f "$ROUTER_TMP"
}

trap cleanup EXIT

log "==== TRAFFIC SWITCH ===="
log "Target color    : $NEW_COLOR"
log "Target container: $NEW_CONTAINER"
log "Target version  : $VERSION"
log "Router          : $ROUTER_CONTAINER"
log "Production port : $ROUTER_PORT"
log "Candidate port  : $CANDIDATE_PORT"
log "========================="

# --------------------------------------------------
# Validate template
# --------------------------------------------------

if [[ ! -f "$TEMPLATE" ]]; then
    log "FAIL - router template not found: $TEMPLATE"
    exit 1
fi

log "PASS - router template found"

# --------------------------------------------------
# Validate router
# --------------------------------------------------

if ! docker inspect "$ROUTER_CONTAINER" >/dev/null 2>&1; then
    log "FAIL - router container '$ROUTER_CONTAINER' does not exist"
    exit 1
fi

log "PASS - router container exists"

# --------------------------------------------------
# Validate target container
# --------------------------------------------------

if ! docker inspect "$NEW_CONTAINER" >/dev/null 2>&1; then
    log "FAIL - target container '$NEW_CONTAINER' does not exist"
    exit 1
fi

log "PASS - target container '$NEW_CONTAINER' exists"

# --------------------------------------------------
# Generate nginx configuration
# --------------------------------------------------

log "Generating nginx configuration..."

sed \
    -e "s/__ACTIVE_COLOR__/${NEW_COLOR}/g" \
    -e "s/__ACTIVE_CONTAINER__/${NEW_CONTAINER}/g" \
    "$TEMPLATE" > "$ROUTER_TMP"

if [[ ! -s "$ROUTER_TMP" ]]; then
    log "FAIL - generated nginx configuration is empty"
    exit 1
fi

log "Generated nginx configuration:"
cat "$ROUTER_TMP"

# --------------------------------------------------
# Copy configuration into router container
# --------------------------------------------------

log "Updating configuration inside '$ROUTER_CONTAINER'..."

MSYS_NO_PATHCONV=1 docker exec -i \
    "$ROUTER_CONTAINER" \
    sh -c 'cat > /etc/nginx/conf.d/active-backend.conf' \
    < "$ROUTER_TMP"

log "PASS - router configuration updated"

# --------------------------------------------------
# Validate nginx configuration
# --------------------------------------------------

log "Testing nginx configuration..."

MSYS_NO_PATHCONV=1 docker exec \
    "$ROUTER_CONTAINER" \
    nginx -t

log "PASS - nginx configuration valid"

# --------------------------------------------------
# Reload nginx
# --------------------------------------------------

log "Reloading nginx..."

MSYS_NO_PATHCONV=1 docker exec \
    "$ROUTER_CONTAINER" \
    nginx -s reload

sleep 2

# --------------------------------------------------
# Verify router status
# --------------------------------------------------

log "Verifying router status..."

ROUTER_STATUS="$(
    curl -fsS \
        "http://localhost:${ROUTER_PORT}/router-status"
)"

echo "$ROUTER_STATUS"

EXPECTED_STATUS="active-color: ${NEW_COLOR}"

if [[ "$ROUTER_STATUS" != "$EXPECTED_STATUS" ]]; then
    log "FAIL - router active color is '$ROUTER_STATUS'"
    log "Expected: '$EXPECTED_STATUS'"
    exit 1
fi

log "PASS - router reports active color '$NEW_COLOR'"

# --------------------------------------------------
# Verify production version
# --------------------------------------------------

log "Verifying production application identity..."

VERSION_RESPONSE="$(
    curl -fsS \
        "http://localhost:${ROUTER_PORT}/version"
)"

echo "$VERSION_RESPONSE"

if ! echo "$VERSION_RESPONSE" |
    grep -q "\"version\": \"$VERSION\""; then

    log "FAIL - router is serving unexpected version"
    log "Expected version: $VERSION"
    exit 1
fi

if ! echo "$VERSION_RESPONSE" |
    grep -q "\"color\": \"$NEW_COLOR\""; then

    log "FAIL - router is serving unexpected color"
    log "Expected color: $NEW_COLOR"
    exit 1
fi

log "PASS - production version is '$VERSION'"
log "PASS - production color is '$NEW_COLOR'"

log "========================================="
log "TRAFFIC SWITCH SUCCESSFUL"
log "========================================="
log "Active color: $NEW_COLOR"
log "Version     : $VERSION"
log "Router      : http://localhost:${ROUTER_PORT}"
log "========================================="