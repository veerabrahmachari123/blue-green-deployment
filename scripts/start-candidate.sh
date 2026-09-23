#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$DIR/lib/common.sh" ]; then
    source "$DIR/lib/common.sh"
fi

IMAGE_TAG="${1:?usage: start-candidate.sh <image_tag> <version> <git_commit>}"
VERSION="${2:?usage: start-candidate.sh <image_tag> <version> <git_commit>}"
GIT_COMMIT="${3:?usage: start-candidate.sh <image_tag> <version> <git_commit>}"

NETWORK_NAME="${NETWORK_NAME:-orders-network}"
DB_CONTAINER="${DB_CONTAINER:-orders-db}"

SECRET_ENV_FILE="${SECRET_ENV_FILE:-${DIR}/secrets/orders-api.env}"

BLUE_CONTAINER="orders-blue"
GREEN_CONTAINER="orders-green"

BLUE_PORT="${BLUE_PORT:-8081}"
GREEN_PORT="${GREEN_PORT:-8082}"

ROUTER_CONTAINER="${ROUTER_CONTAINER:-orders-router}"

CURRENT_COLOR=""
CANDIDATE_COLOR=""
CANDIDATE_NAME=""
CANDIDATE_PORT=""

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

log_msg "Preparing blue/green candidate."


# ======================================================================
# Validate required arguments
# ======================================================================

if [ -z "$IMAGE_TAG" ]; then
    fail_msg "image tag is empty"
    exit 1
fi

if [ -z "$VERSION" ]; then
    fail_msg "application version is empty"
    exit 1
fi

if [ -z "$GIT_COMMIT" ]; then
    fail_msg "git commit is empty"
    exit 1
fi


# ======================================================================
# Validate secret file
# ======================================================================

if [ ! -f "$SECRET_ENV_FILE" ]; then

    fail_msg \
        "secret env file not found at ${SECRET_ENV_FILE} (contains ORDERS_API_SECRET, never logged)"

    exit 1
fi

if [ ! -r "$SECRET_ENV_FILE" ]; then

    fail_msg "secret env file exists but is not readable"

    exit 1
fi

if ! grep -q '^ORDERS_API_SECRET=' "$SECRET_ENV_FILE"; then

    fail_msg "secret env file does not contain ORDERS_API_SECRET"

    exit 1
fi


# ======================================================================
# Determine currently-live color
# ======================================================================

BLUE_RUNNING=false
GREEN_RUNNING=false

if docker ps \
    --filter "name=^${BLUE_CONTAINER}$" \
    --filter "status=running" \
    --format '{{.Names}}' |
    grep -q "^${BLUE_CONTAINER}$"; then

    BLUE_RUNNING=true
fi

if docker ps \
    --filter "name=^${GREEN_CONTAINER}$" \
    --filter "status=running" \
    --format '{{.Names}}' |
    grep -q "^${GREEN_CONTAINER}$"; then

    GREEN_RUNNING=true
fi


if [ "$BLUE_RUNNING" = true ] && [ "$GREEN_RUNNING" = false ]; then

    CURRENT_COLOR="blue"

elif [ "$GREEN_RUNNING" = true ] && [ "$BLUE_RUNNING" = false ]; then

    CURRENT_COLOR="green"

elif [ "$BLUE_RUNNING" = true ] && [ "$GREEN_RUNNING" = true ]; then

    router_target=""

    if docker ps \
        --filter "name=^${ROUTER_CONTAINER}$" \
        --format '{{.Names}}' |
        grep -q "^${ROUTER_CONTAINER}$"; then

        router_target="$(
            docker inspect "$ROUTER_CONTAINER" \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                2>/dev/null |
                grep '^ACTIVE_COLOR=' |
                head -n1 |
                cut -d= -f2- ||
                true
        )"
    fi

    case "$router_target" in
        blue)
            CURRENT_COLOR="blue"
            ;;
        green)
            CURRENT_COLOR="green"
            ;;
        *)
            fail_msg \
                "both blue and green containers are running, but router ACTIVE_COLOR could not be determined"

            echo "Running blue/green containers:"

            docker ps \
                --filter "name=${BLUE_CONTAINER}" \
                --filter "name=${GREEN_CONTAINER}" \
                --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
                || true

            exit 1
            ;;
    esac

else

    if docker ps \
        --filter "name=^${ROUTER_CONTAINER}$" \
        --format '{{.Names}}' |
        grep -q "^${ROUTER_CONTAINER}$"; then

        router_target="$(
            docker inspect "$ROUTER_CONTAINER" \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                2>/dev/null |
                grep '^ACTIVE_COLOR=' |
                head -n1 |
                cut -d= -f2- ||
                true
        )"

        case "$router_target" in
            blue)
                CURRENT_COLOR="blue"
                ;;
            green)
                CURRENT_COLOR="green"
                ;;
        esac
    fi
fi


# ======================================================================
# If still unknown, inspect existing stopped containers
# ======================================================================

if [ -z "$CURRENT_COLOR" ]; then

    if docker ps -a \
        --filter "name=^${BLUE_CONTAINER}$" \
        --format '{{.Names}}' |
        grep -q "^${BLUE_CONTAINER}$"; then

        CURRENT_COLOR="blue"

    elif docker ps -a \
        --filter "name=^${GREEN_CONTAINER}$" \
        --format '{{.Names}}' |
        grep -q "^${GREEN_CONTAINER}$"; then

        CURRENT_COLOR="green"

    else

        CURRENT_COLOR="blue"
    fi
fi


# ======================================================================
# Select candidate color
# ======================================================================

case "$CURRENT_COLOR" in

    blue)

        CANDIDATE_COLOR="green"
        CANDIDATE_NAME="$GREEN_CONTAINER"
        CANDIDATE_PORT="$GREEN_PORT"

        ;;

    green)

        CANDIDATE_COLOR="blue"
        CANDIDATE_NAME="$BLUE_CONTAINER"
        CANDIDATE_PORT="$BLUE_PORT"

        ;;

    *)

        fail_msg "invalid current color: ${CURRENT_COLOR}"

        exit 1

        ;;
esac


log_msg "Current production color: ${CURRENT_COLOR}"
log_msg "Candidate color: ${CANDIDATE_COLOR}"
log_msg "Candidate container: ${CANDIDATE_NAME}"
log_msg "Candidate port: ${CANDIDATE_PORT}"


# ======================================================================
# Remove existing candidate container
# ======================================================================

if docker ps -a \
    --filter "name=^${CANDIDATE_NAME}$" \
    --format '{{.Names}}' |
    grep -q "^${CANDIDATE_NAME}$"; then

    log_msg "Removing existing ${CANDIDATE_NAME} container."

    docker rm -f "$CANDIDATE_NAME" \
        >/dev/null 2>&1 ||
        true
fi


# ======================================================================
# Make sure Docker network exists
# ======================================================================

if ! docker network inspect "$NETWORK_NAME" \
    >/dev/null 2>&1; then

    log_msg "Creating Docker network ${NETWORK_NAME}"

    docker network create "$NETWORK_NAME"
fi


# ======================================================================
# Make sure database container is connected to the network
# ======================================================================

if docker ps \
    --filter "name=^${DB_CONTAINER}$" \
    --format '{{.Names}}' |
    grep -q "^${DB_CONTAINER}$"; then

    log_msg "Ensuring ${DB_CONTAINER} is connected to ${NETWORK_NAME}."

    docker network connect "$NETWORK_NAME" "$DB_CONTAINER" \
        >/dev/null 2>&1 ||
        true

else

    log_msg \
        "Database container ${DB_CONTAINER} is not running. Candidate will still be created."
fi


# ======================================================================
# Validate image exists
# ======================================================================

if ! docker image inspect "$IMAGE_TAG" \
    >/dev/null 2>&1; then

    fail_msg "Docker image does not exist locally: ${IMAGE_TAG}"

    exit 1
fi


# ======================================================================
# Start candidate
# ======================================================================

log_msg "Starting ${CANDIDATE_COLOR} candidate."
log_msg "Container: ${CANDIDATE_NAME}"
log_msg "Image: ${IMAGE_TAG}"
log_msg "Port: ${CANDIDATE_PORT}"

docker run -d \
    --name "$CANDIDATE_NAME" \
    --restart unless-stopped \
    --network "$NETWORK_NAME" \
    --env-file "$SECRET_ENV_FILE" \
    -e "APP_VERSION=${VERSION}" \
    -e "GIT_COMMIT=${GIT_COMMIT}" \
    -e "APP_COLOR=${CANDIDATE_COLOR}" \
    -e "DB_HOST=${DB_CONTAINER}" \
    -p "${CANDIDATE_PORT}:3000" \
    "$IMAGE_TAG"


# ======================================================================
# Give Docker a moment to start the container
# ======================================================================

sleep 2


# ======================================================================
# Validate candidate container
# ======================================================================

if ! docker ps \
    --filter "name=^${CANDIDATE_NAME}$" \
    --filter "status=running" \
    --format '{{.Names}}' |
    grep -q "^${CANDIDATE_NAME}$"; then

    fail_msg \
        "candidate container ${CANDIDATE_NAME} failed to start"

    echo "Candidate container diagnostics:"

    docker ps -a \
        --filter "name=^${CANDIDATE_NAME}$" \
        --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
        || true

    echo "Recent candidate logs:"

    docker logs --tail 100 "$CANDIDATE_NAME" \
        2>&1 ||
        true

    exit 1
fi


# ======================================================================
# Validate candidate image
# ======================================================================

actual_image="$(
    docker inspect \
        --format '{{.Config.Image}}' \
        "$CANDIDATE_NAME"
)"

if [ "$actual_image" != "$IMAGE_TAG" ]; then

    fail_msg \
        "candidate container is using unexpected image: ${actual_image}"

    exit 1
fi


# ======================================================================
# Output deployment state
#
# Jenkins parses these values.
#
# NEVER output ORDERS_API_SECRET.
# ======================================================================

echo "CURRENT_COLOR=${CURRENT_COLOR}"
echo "CANDIDATE_COLOR=${CANDIDATE_COLOR}"
echo "CANDIDATE_NAME=${CANDIDATE_NAME}"
echo "CANDIDATE_PORT=${CANDIDATE_PORT}"

log_msg "Candidate container started successfully."
log_msg "Candidate image: ${IMAGE_TAG}"
log_msg "Candidate color: ${CANDIDATE_COLOR}"
log_msg "Candidate port: ${CANDIDATE_PORT}"
