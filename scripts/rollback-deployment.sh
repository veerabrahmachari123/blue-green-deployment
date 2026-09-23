#!/usr/bin/env bash

set -euo pipefail

CURRENT_COLOR="${1:-}"
CANDIDATE_COLOR="${2:-}"

ROUTER_CONTAINER="orders-router"
ROUTER_PORT="8080"

if [[ -z "$CURRENT_COLOR" || -z "$CANDIDATE_COLOR" ]]; then
    echo "Usage: $0 <current_color> <candidate_color>"
    exit 1
fi

case "$CURRENT_COLOR" in
    blue|green)
        ;;
    *)
        echo "FAIL - invalid current color: $CURRENT_COLOR"
        exit 1
        ;;
esac

case "$CANDIDATE_COLOR" in
    blue|green)
        ;;
    *)
        echo "FAIL - invalid candidate color: $CANDIDATE_COLOR"
        exit 1
        ;;
esac

CURRENT_CONTAINER="orders-${CURRENT_COLOR}"
CANDIDATE_CONTAINER="orders-${CANDIDATE_COLOR}"

echo "=================================================="
echo "DEPLOYMENT ROLLBACK"
echo "=================================================="
echo "Current color   : $CURRENT_COLOR"
echo "Candidate color : $CANDIDATE_COLOR"
echo "Router          : $ROUTER_CONTAINER"
echo "Production port : $ROUTER_PORT"
echo "=================================================="

# ------------------------------------------------------------
# Verify router exists
# ------------------------------------------------------------

if ! docker inspect "$ROUTER_CONTAINER" >/dev/null 2>&1; then
    echo "FAIL - router container '$ROUTER_CONTAINER' does not exist"
    exit 1
fi

echo "PASS - router container exists"

# ------------------------------------------------------------
# Determine actual active color
# ------------------------------------------------------------

echo "Determining actual production traffic..."

ACTIVE_STATUS="$(curl -fsS "http://localhost:${ROUTER_PORT}/router-status")"

echo "Router status: $ACTIVE_STATUS"

ACTIVE_COLOR="$(echo "$ACTIVE_STATUS" | sed -n 's/^active-color: //p' | tr -d '[:space:]')"

if [[ -z "$ACTIVE_COLOR" ]]; then
    echo "FAIL - could not determine active router color"
    exit 1
fi

echo "Actual active color: $ACTIVE_COLOR"

# ------------------------------------------------------------
# Safety check
# ------------------------------------------------------------

if [[ "$ACTIVE_COLOR" != "$CURRENT_COLOR" &&
      "$ACTIVE_COLOR" != "$CANDIDATE_COLOR" ]]; then

    echo "FAIL - router is serving unexpected color '$ACTIVE_COLOR'"
    echo "Expected either '$CURRENT_COLOR' or '$CANDIDATE_COLOR'."
    echo "Manual investigation required."
    exit 1
fi

# ------------------------------------------------------------
# If traffic was switched, restore previous production
# ------------------------------------------------------------

if [[ "$ACTIVE_COLOR" == "$CANDIDATE_COLOR" ]]; then

    echo "Traffic is currently on candidate '$CANDIDATE_COLOR'."
    echo "Restoring production traffic to '$CURRENT_COLOR'."

    CURRENT_VERSION_RESPONSE="$(curl -fsS "http://localhost:${ROUTER_PORT}/version")" || true

    echo "Current production response before rollback:"
    echo "$CURRENT_VERSION_RESPONSE"

    if ! docker inspect "$CURRENT_CONTAINER" >/dev/null 2>&1; then
        echo "FAIL - previous production container '$CURRENT_CONTAINER' does not exist"
        echo "Cannot safely restore production."
        exit 1
    fi

    CURRENT_VERSION="$(
        echo "$CURRENT_VERSION_RESPONSE" |
        sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p'
    )"

    if [[ -z "$CURRENT_VERSION" ]]; then
        echo "FAIL - could not determine previous production version"
        echo "Cannot safely perform traffic rollback."
        exit 1
    fi

    echo "Previous production version: $CURRENT_VERSION"

    echo "Switching router back to '$CURRENT_COLOR'..."

    scripts/switch-traffic.sh \
        "$CURRENT_COLOR" \
        "$CURRENT_VERSION"

    echo "PASS - production traffic restored to '$CURRENT_COLOR'"

else

    echo "Production traffic is already on '$CURRENT_COLOR'."
    echo "No traffic switch rollback is required."

fi

# ------------------------------------------------------------
# Verify production after rollback
# ------------------------------------------------------------

echo "Checking final router state..."

FINAL_STATUS="$(curl -fsS "http://localhost:${ROUTER_PORT}/router-status")"

echo "$FINAL_STATUS"

EXPECTED_STATUS="active-color: ${CURRENT_COLOR}"

if [[ "$FINAL_STATUS" != "$EXPECTED_STATUS" ]]; then
    echo "FAIL - final router state is '$FINAL_STATUS'"
    echo "Expected: '$EXPECTED_STATUS'"
    echo "Manual investigation required."
    exit 1
fi

echo "PASS - router is serving '$CURRENT_COLOR'"

echo "Checking production health..."

if curl -fsS -o /dev/null "http://localhost:${ROUTER_PORT}/health"; then
    echo "PASS - production health is OK"
else
    echo "FAIL - production health check failed"
    exit 1
fi

# ------------------------------------------------------------
# Remove candidate
# ------------------------------------------------------------

echo "Removing candidate container '$CANDIDATE_CONTAINER'..."

if docker inspect "$CANDIDATE_CONTAINER" >/dev/null 2>&1; then

    echo "Candidate logs:"
    docker logs --tail 100 "$CANDIDATE_CONTAINER" 2>&1 || true

    docker rm -f "$CANDIDATE_CONTAINER" >/dev/null 2>&1 || true

    echo "PASS - removed candidate '$CANDIDATE_CONTAINER'"

else

    echo "Candidate '$CANDIDATE_CONTAINER' does not exist."
    echo "Nothing to remove."

fi

# ------------------------------------------------------------
# Final identity check
# ------------------------------------------------------------

echo "Checking final production identity..."

FINAL_VERSION_RESPONSE="$(curl -fsS "http://localhost:${ROUTER_PORT}/version")"

echo "$FINAL_VERSION_RESPONSE"

if ! echo "$FINAL_VERSION_RESPONSE" | grep -q "\"color\": \"$CURRENT_COLOR\""; then
    echo "FAIL - final production color is not '$CURRENT_COLOR'"
    exit 1
fi

echo "PASS - final production identity reports '$CURRENT_COLOR'"

echo "=================================================="
echo "DEPLOYMENT ROLLBACK COMPLETE"
echo "=================================================="
echo "Production color : $CURRENT_COLOR"
echo "Candidate removed : $CANDIDATE_CONTAINER"
echo "Production port   : $ROUTER_PORT"
echo "Production health : OK"
echo "=================================================="
