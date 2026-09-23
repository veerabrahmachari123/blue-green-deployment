#!/usr/bin/env bash

set -euo pipefail

CONTAINER_NAME="${1:?usage: container-validation.sh <container_name> <host_port>}"
HOST_PORT="${2:?usage: container-validation.sh <container_name> <host_port>}"

NETWORK_NAME="${NETWORK_NAME:-orders-network}"

log_msg() {
    if declare -F log >/dev/null 2>&1; then
        log "$1"
    else
        printf '[%s] %s\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            "$1"
    fi
}

fail_msg() {
    if declare -F fail >/dev/null 2>&1; then
        fail "$1"
    else
        printf '[%s] FAIL - %s\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            "$1" >&2
    fi
}


log_msg "Validating container '${CONTAINER_NAME}'"


# ======================================================================
# Container existence
# ======================================================================

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then

    fail_msg \
        "container '${CONTAINER_NAME}' does not exist"

    exit 1
fi


# ======================================================================
# Container running state
# ======================================================================

RUNNING="$(
    docker inspect \
        --format '{{.State.Running}}' \
        "$CONTAINER_NAME"
)"

if [ "$RUNNING" != "true" ]; then

    fail_msg \
        "container '${CONTAINER_NAME}' is not running"

    echo "Container state:"

    docker ps -a \
        --filter "name=^${CONTAINER_NAME}$" \
        --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
        || true

    echo "Recent container logs:"

    docker logs --tail 100 "$CONTAINER_NAME" \
        2>&1 ||
        true

    exit 1
fi

log_msg "OK   - container is running"


# ======================================================================
# Docker network validation
# ======================================================================

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then

    fail_msg \
        "required Docker network '${NETWORK_NAME}' does not exist"

    exit 1
fi

if ! docker network inspect "$NETWORK_NAME" \
    --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' |
    grep -Fxq "$CONTAINER_NAME"; then

    fail_msg \
        "container '${CONTAINER_NAME}' is not attached to network '${NETWORK_NAME}'"

    exit 1
fi

log_msg \
    "OK   - attached to network '${NETWORK_NAME}'"


# ======================================================================
# Host port validation
# ======================================================================

PORT_MAPPING="$(
    docker port "$CONTAINER_NAME" 3000/tcp 2>/dev/null || true
)"

if [ -z "$PORT_MAPPING" ]; then

    fail_msg \
        "container '${CONTAINER_NAME}' does not expose container port 3000"

    exit 1
fi

if ! printf '%s\n' "$PORT_MAPPING" |
    grep -Eq "[:.]${HOST_PORT}$|:${HOST_PORT}->"; then

    fail_msg \
        "expected host port ${HOST_PORT} but got: ${PORT_MAPPING}"

    exit 1
fi

log_msg \
    "OK   - port mapping confirmed: ${PORT_MAPPING}"


# ======================================================================
# Application process listening on port 3000
# ======================================================================

if ! docker exec "$CONTAINER_NAME" \
    sh -c 'wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1' \
    >/dev/null 2>&1; then

    fail_msg \
        "application is not responding on port 3000 inside '${CONTAINER_NAME}'"

    echo "Recent container logs:"

    docker logs --tail 100 "$CONTAINER_NAME" \
        2>&1 ||
        true

    exit 1
fi

log_msg \
    "OK   - process inside the container is listening on 3000"


# ======================================================================
# Inspect environment safely
#
# Secrets are redacted.
# ======================================================================

echo "Environment present on candidate (secrets redacted):"

docker inspect \
    --format '{{range .Config.Env}}{{println .}}{{end}}' \
    "$CONTAINER_NAME" |
    while IFS= read -r entry; do

        case "$entry" in

            ORDERS_API_SECRET=*)
                echo "ORDERS_API_SECRET=***REDACTED***"
                ;;

            *)
                echo "$entry"
                ;;

        esac

    done


# ======================================================================
# Required deployment environment
#
# APP_COLOR is the canonical variable used by start-candidate.sh.
# COLOR is accepted as a legacy fallback.
# ======================================================================

APP_COLOR="$(
    docker inspect \
        --format '{{range .Config.Env}}{{println .}}{{end}}' \
        "$CONTAINER_NAME" |
        sed -n 's/^APP_COLOR=//p' |
        head -n1
)"

LEGACY_COLOR="$(
    docker inspect \
        --format '{{range .Config.Env}}{{println .}}{{end}}' \
        "$CONTAINER_NAME" |
        sed -n 's/^COLOR=//p' |
        head -n1
)"

if [ -z "$APP_COLOR" ]; then
    APP_COLOR="$LEGACY_COLOR"
fi

if [ -z "$APP_COLOR" ]; then

    fail_msg \
        "required deployment color is missing; expected APP_COLOR"

    exit 1
fi

case "$APP_COLOR" in
    blue|green)
        ;;
    *)
        fail_msg \
            "invalid APP_COLOR='${APP_COLOR}'; expected blue or green"

        exit 1
        ;;
esac

log_msg \
    "OK   - candidate color is '${APP_COLOR}'"


# ======================================================================
# Required application version
# ======================================================================

APP_VERSION="$(
    docker inspect \
        --format '{{range .Config.Env}}{{println .}}{{end}}' \
        "$CONTAINER_NAME" |
        sed -n 's/^APP_VERSION=//p' |
        head -n1
)"

if [ -z "$APP_VERSION" ]; then

    fail_msg \
        "required env var 'APP_VERSION' is missing"

    exit 1
fi

log_msg \
    "OK   - candidate version is '${APP_VERSION}'"


# ======================================================================
# Required git commit
# ======================================================================

GIT_COMMIT="$(
    docker inspect \
        --format '{{range .Config.Env}}{{println .}}{{end}}' \
        "$CONTAINER_NAME" |
        sed -n 's/^GIT_COMMIT=//p' |
        head -n1
)"

if [ -z "$GIT_COMMIT" ]; then

    fail_msg \
        "required env var 'GIT_COMMIT' is missing"

    exit 1
fi

log_msg \
    "OK   - candidate git commit is '${GIT_COMMIT}'"


# ======================================================================
# Final validation
# ======================================================================

log_msg "OK   - container validation completed successfully"
