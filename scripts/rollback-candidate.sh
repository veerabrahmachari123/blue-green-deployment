#!/usr/bin/env bash

set -euo pipefail

CANDIDATE_COLOR="${1:-}"
CURRENT_COLOR="${2:-}"

ROUTER_CONTAINER="orders-router"
ROUTER_PORT="8080"

if [[ -z "$CANDIDATE_COLOR" || -z "$CURRENT_COLOR" ]]; then
    echo "Usage: $0 <candidate_color> <current_color>"
    exit 1
fi

if [[ "$CANDIDATE_COLOR" != "blue" && "$CANDIDATE_COLOR" != "green" ]]; then
    echo "FAIL - invalid candidate color: $CANDIDATE_COLOR"
    exit 1
fi

if [[ "$CURRENT_COLOR" != "blue" && "$CURRENT_COLOR" != "green" ]]; then
    echo "FAIL - invalid current color: $CURRENT_COLOR"
    exit 1
fi

CANDIDATE_NAME="orders-${CANDIDATE_COLOR}"

echo "=================================================="
echo "ROLLBACK - candidate validation failed"
echo "=================================================="
echo "Candidate : $CANDIDATE_NAME"
echo "Production: $CURRENT_COLOR"
echo "Router    : $ROUTER_CONTAINER"
echo "Port      : $ROUTER_PORT"
echo "=================================================="

# --------------------------------------------------
# Remove failed candidate
# --------------------------------------------------

if docker inspect "$CANDIDATE_NAME" > /dev/null 2>&1; then

    echo "---- capturing candidate logs before removal ----"

    docker logs --tail 100 "$CANDIDATE_NAME" \
        > /tmp/orders-candidate-rollback.log 2>&1 || true

    cat /tmp/orders-candidate-rollback.log || true

    rm -f /tmp/orders-candidate-rollback.log || true

    echo "--------------------------------------------------"

    docker rm -f "$CANDIDATE_NAME" > /dev/null 2>&1 || true

    echo "PASS - removed failed candidate '$CANDIDATE_NAME'"

else

    echo "Candidate '$CANDIDATE_NAME' does not exist."
    echo "Nothing to remove."

fi

# --------------------------------------------------
# Verify router exists
# --------------------------------------------------

if ! docker inspect "$ROUTER_CONTAINER" > /dev/null 2>&1; then
    echo "FAIL - router container '$ROUTER_CONTAINER' does not exist"
    exit 1
fi

echo "PASS - router container exists"

# --------------------------------------------------
# Read actual active configuration INSIDE router
# --------------------------------------------------

echo "Checking active router configuration..."

MSYS_NO_PATHCONV=1 docker exec \
    "$ROUTER_CONTAINER" \
    cat /etc/nginx/conf.d/active-backend.conf \
    > /tmp/orders-active-backend.conf

if [[ ! -s /tmp/orders-active-backend.conf ]]; then
    echo "FAIL - could not read active router configuration"
    rm -f /tmp/orders-active-backend.conf
    exit 1
fi

cat /tmp/orders-active-backend.conf

ACTIVE_COLOR=$(
    grep 'ACTIVE_COLOR=' /tmp/orders-active-backend.conf |
    head -n 1 |
    cut -d '=' -f 2 |
    tr -d '[:space:]#'
)

rm -f /tmp/orders-active-backend.conf

echo "Detected active color: $ACTIVE_COLOR"

if [[ "$ACTIVE_COLOR" != "$CURRENT_COLOR" ]]; then
    echo "FAIL - UNEXPECTED: router active color is '$ACTIVE_COLOR'"
    echo "Expected untouched production color: '$CURRENT_COLOR'"
    echo "Manual investigation required."
    exit 1
fi

echo "PASS - router configuration still points to '$CURRENT_COLOR'"

# --------------------------------------------------
# Verify router status endpoint
# --------------------------------------------------

echo "Checking router status endpoint..."

ROUTER_STATUS=$(curl -fsS "http://localhost:${ROUTER_PORT}/router-status")

echo "$ROUTER_STATUS"

EXPECTED_STATUS="active-color: ${CURRENT_COLOR}"

if [[ "$ROUTER_STATUS" != "$EXPECTED_STATUS" ]]; then
    echo "FAIL - router status is '$ROUTER_STATUS'"
    echo "Expected: '$EXPECTED_STATUS'"
    exit 1
fi

echo "PASS - router status reports '$CURRENT_COLOR'"

# --------------------------------------------------
# Verify production health
# --------------------------------------------------

echo "Checking production health..."

if curl -fsS -o /dev/null "http://localhost:${ROUTER_PORT}/health"; then
    echo "PASS - production is responding on port ${ROUTER_PORT}"
else
    echo "FAIL - production is NOT responding on port ${ROUTER_PORT}"
    exit 1
fi

# --------------------------------------------------
# Verify production identity
# --------------------------------------------------

echo "Checking production identity..."

VERSION_RESPONSE=$(curl -fsS "http://localhost:${ROUTER_PORT}/version")

echo "$VERSION_RESPONSE"

if ! echo "$VERSION_RESPONSE" | grep -q "\"color\": \"$CURRENT_COLOR\""; then
    echo "FAIL - production does not report color '$CURRENT_COLOR'"
    exit 1
fi

echo "PASS - production identity reports '$CURRENT_COLOR'"

# --------------------------------------------------
# Complete
# --------------------------------------------------

echo "=================================================="
echo "ROLLBACK COMPLETE"
echo "=================================================="
echo "Candidate removed : $CANDIDATE_NAME"
echo "Production color   : $CURRENT_COLOR"
echo "Production port    : $ROUTER_PORT"
echo "Production health  : OK"
echo "=================================================="

