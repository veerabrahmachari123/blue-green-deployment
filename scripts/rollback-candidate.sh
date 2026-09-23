#!/usr/bin/env bash
# Called from the Jenkinsfile's post{failure{}} / catch block whenever any
# validation stage fails BEFORE traffic switch. Implements Phase 6:
# candidate is removed, current production color is left completely alone
# and re-verified as still serving traffic.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

CANDIDATE_COLOR="${1:?usage: rollback-candidate.sh <candidate_color> <current_color>}"
CURRENT_COLOR="${2:?}"
CANDIDATE_NAME="orders-${CANDIDATE_COLOR}"

log "==== ROLLBACK (candidate validation failed) ===="
log "Removing failed candidate: $CANDIDATE_NAME"
log "Production must remain on: $CURRENT_COLOR"
log "=================================================="

if container_exists "$CANDIDATE_NAME"; then
  log "---- capturing candidate logs before removal ----"
  docker logs --tail 100 "$CANDIDATE_NAME" 2>&1 | redact_env || true
  log "--------------------------------------------------"
  docker rm -f "$CANDIDATE_NAME" >/dev/null || true
  ok "removed failed candidate '$CANDIDATE_NAME'"
else
  log "candidate container '$CANDIDATE_NAME' does not exist (failed before start) - nothing to remove"
fi

# Prove production was never disturbed: router must still report the
# original current color and respond 200 through port 8080.
ACTUAL_ACTIVE=$(current_active_color)
if [ "$ACTUAL_ACTIVE" != "$CURRENT_COLOR" ]; then
  fail "UNEXPECTED: router active color is '$ACTUAL_ACTIVE', expected untouched '$CURRENT_COLOR' - manual investigation required"
fi

if curl -sf -o /dev/null "http://localhost:8080/health"; then
  ok "confirmed: production is still being served by '$CURRENT_COLOR' on port 8080"
else
  fail "CRITICAL: production ('$CURRENT_COLOR') is not responding on port 8080 after rollback - escalate immediately"
fi
