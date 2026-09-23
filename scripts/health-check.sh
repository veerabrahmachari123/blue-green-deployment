#!/usr/bin/env bash
# Jenkins stage: Application Health Check
# Talks directly to the candidate's own published port (NOT through the
# router, which hasn't switched yet). Covers Phase 5 #27 (running but
# health endpoint fails) and #37 (HTTP 500 after deploy).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

CANDIDATE_PORT="${1:?usage: health-check.sh <candidate_port> <candidate_name> [retries] [sleep_secs]}"
CANDIDATE_NAME="${2:?usage: health-check.sh <candidate_port> <candidate_name> [retries] [sleep_secs]}"
RETRIES="${3:-10}"
SLEEP_SECS="${4:-2}"

log "Polling http://localhost:${CANDIDATE_PORT}/health ($RETRIES attempts, ${SLEEP_SECS}s apart)"

attempt=1
while [ "$attempt" -le "$RETRIES" ]; do
  HTTP_CODE=$(curl -s -o /tmp/health-response.json -w '%{http_code}' "http://localhost:${CANDIDATE_PORT}/health" || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    ok "health check passed on attempt $attempt: $(cat /tmp/health-response.json)"
    exit 0
  fi
  log "attempt $attempt/$RETRIES: health endpoint returned HTTP $HTTP_CODE"
  attempt=$((attempt + 1))
  sleep "$SLEEP_SECS"
done

log "---- diagnostic dump on health check failure ($CANDIDATE_NAME) ----"
docker logs --tail 80 "$CANDIDATE_NAME" 2>&1 | redact_env || true
log "---------------------------------------------------------------------"
fail "candidate never became healthy on port $CANDIDATE_PORT after $RETRIES attempts (Phase 5 #27/#37)"
