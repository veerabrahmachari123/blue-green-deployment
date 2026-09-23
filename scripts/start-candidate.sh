#!/usr/bin/env bash
# Jenkins stage: Start Candidate
# Starts the CANDIDATE color container while the CURRENT color keeps serving
# production traffic unmodified (Phase 3: "current version remains available
# while the candidate version is started").
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

IMAGE_TAG="${1:?usage: start-candidate.sh <image_tag> <version> <git_commit>}"
VERSION="${2:?}"
GIT_COMMIT="${3:?}"

ACTIVE_COLOR=$(current_active_color)
CANDIDATE_COLOR=$(other_color "$ACTIVE_COLOR")
CANDIDATE_PORT=$(color_port "$CANDIDATE_COLOR")
CANDIDATE_NAME="orders-${CANDIDATE_COLOR}"

log "==== BLUE/GREEN STATE ===="
log "CURRENT (live):   $ACTIVE_COLOR"
log "CANDIDATE (new):  $CANDIDATE_COLOR  (image=$IMAGE_TAG, port=$CANDIDATE_PORT)"
log "==========================="

# Idempotency (Phase 7): if a leftover candidate container exists from a
# previous failed/aborted run, remove it before starting a fresh one so a
# re-run never leaves uncontrolled duplicate containers.
if container_exists "$CANDIDATE_NAME"; then
  log "Found leftover container '$CANDIDATE_NAME' from a previous run - removing it first"
  docker rm -f "$CANDIDATE_NAME" >/dev/null
fi

# Phase 5 scenario #33 guard: refuse to start if the candidate's own host
# port is already bound by something unexpected (rather than fail obscurely
# inside `docker run`).
if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":${CANDIDATE_PORT} "; then
  fail "host port $CANDIDATE_PORT is already in use by another process - resolve before deploying (Phase 5 #33)"
fi

SECRET_ENV_FILE="${SECRET_ENV_FILE:-$DIR/secrets/orders-api.env}"
if [ ! -f "$SECRET_ENV_FILE" ]; then
  fail "secret env file not found at $SECRET_ENV_FILE (contains ORDERS_API_SECRET, never logged - Phase 5 #31 / Phase 7 no secrets in logs)"
fi

log "Starting candidate container '$CANDIDATE_NAME' on host port $CANDIDATE_PORT"
docker run -d \
  --name "$CANDIDATE_NAME" \
  --network "$NETWORK_NAME" \
  --network-alias "$CANDIDATE_NAME" \
  -p "${CANDIDATE_PORT}:3000" \
  --env-file "$SECRET_ENV_FILE" \
  -e "VERSION=${VERSION}" \
  -e "GIT_COMMIT=${GIT_COMMIT}" \
  -e "COLOR=${CANDIDATE_COLOR}" \
  -e "DB_HOST=orders-db" \
  -e "DB_PORT=5432" \
  -e "DB_NAME=orders" \
  --restart unless-stopped \
  "$IMAGE_TAG" >/dev/null

ok "candidate '$CANDIDATE_NAME' started"
# Emit machine-readable facts for later stages (Jenkins captures these via stdout).
echo "CANDIDATE_COLOR=$CANDIDATE_COLOR"
echo "CANDIDATE_PORT=$CANDIDATE_PORT"
echo "CANDIDATE_NAME=$CANDIDATE_NAME"
echo "CURRENT_COLOR=$ACTIVE_COLOR"
