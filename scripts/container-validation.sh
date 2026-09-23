#!/usr/bin/env bash
# Jenkins stage: Container Validation
# This is deliberately stricter than "docker ps shows Up" - that check alone
# is what let the original incident's broken build report SUCCESS. It also
# covers Phase 5 scenarios #26 (exits immediately), #28 (wrong port),
# #32 (wrong network), #31 (missing required env var).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

CANDIDATE_NAME="${1:?usage: container-validation.sh <candidate_name> <candidate_port>}"
CANDIDATE_PORT="${2:?}"

log "Validating container '$CANDIDATE_NAME'"

# Give it a moment, then check it hasn't exited (scenario #26).
sleep 2
if ! container_running "$CANDIDATE_NAME"; then
  log "---- last 50 log lines from $CANDIDATE_NAME ----"
  docker logs --tail 50 "$CANDIDATE_NAME" 2>&1 | redact_env || true
  log "-------------------------------------------------"
  fail "container '$CANDIDATE_NAME' is not running (exited immediately - Phase 5 #26)"
fi
ok "container is running"

# Confirm it is actually attached to orders-network (scenario #32).
NETWORKS=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$CANDIDATE_NAME")
echo "$NETWORKS" | grep -qw "$NETWORK_NAME" || fail "container is not attached to '$NETWORK_NAME' (Phase 5 #32) - attached to: $NETWORKS"
ok "attached to network '$NETWORK_NAME'"

# Confirm the published port mapping matches what we expect (scenario #28,
# and the original incident's root cause of a mismatched port mapping).
MAPPED=$(docker port "$CANDIDATE_NAME" 3000/tcp || true)
echo "$MAPPED" | grep -q ":${CANDIDATE_PORT}$" || fail "container port 3000 is not published on expected host port $CANDIDATE_PORT (got: '$MAPPED') - Phase 5 #28"
ok "port mapping confirmed: $MAPPED"

# Confirm the process inside the container is actually listening on 3000
# (this is the exact check the original incident skipped).
if docker exec "$CANDIDATE_NAME" sh -c "command -v netstat >/dev/null 2>&1 || command -v ss >/dev/null 2>&1"; then
  LISTENING=$(docker exec "$CANDIDATE_NAME" sh -c "netstat -ltn 2>/dev/null || ss -ltn 2>/dev/null" | grep -c ':3000 ' || true)
  [ "$LISTENING" -ge 1 ] || fail "no process inside the container is listening on port 3000 - Phase 5 #28"
  ok "process inside the container is listening on 3000"
else
  log "no netstat/ss available inside image; relying on the HTTP checks in the next stage instead"
fi

# Confirm required env vars are present WITHOUT printing their values
# (redact secrets - Phase 7).
log "Environment present on candidate (secrets redacted):"
docker exec "$CANDIDATE_NAME" env | redact_env | sort

REQUIRED_VARS="VERSION GIT_COMMIT COLOR DB_HOST DB_PORT ORDERS_API_SECRET"
for v in $REQUIRED_VARS; do
  docker exec "$CANDIDATE_NAME" sh -c "[ -n \"\$$v\" ]" || fail "required env var '$v' is missing on candidate (Phase 5 #31)"
done
ok "all required environment variables are present"
