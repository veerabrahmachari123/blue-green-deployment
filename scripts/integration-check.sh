#!/usr/bin/env bash
# Jenkins stage: Integration Check
# Confirms the candidate can actually reach its dependencies and that what's
# running matches what was built (Phase 4 traceability). Covers Phase 5
# scenarios #29 (can't reach db), #30 (wrong db hostname).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

CANDIDATE_PORT="${1:?usage: integration-check.sh <candidate_port> <expected_version> <expected_commit>}"
EXPECTED_VERSION="${2:?}"
EXPECTED_COMMIT="${3:?}"

log "Checking /version on candidate matches build identity"
VERSION_JSON=$(curl -sf "http://localhost:${CANDIDATE_PORT}/version") || fail "candidate /version endpoint did not respond"
GOT_VERSION=$(echo "$VERSION_JSON" | grep -o '"version": *"[^"]*"' | sed -E 's/.*"([^"]+)"$/\1/')
GOT_COMMIT=$(echo "$VERSION_JSON" | grep -o '"gitCommit": *"[^"]*"' | sed -E 's/.*"([^"]+)"$/\1/')

[ "$GOT_VERSION" = "$EXPECTED_VERSION" ] || fail "/version reports '$GOT_VERSION', expected '$EXPECTED_VERSION'"
[ "$GOT_COMMIT" = "$EXPECTED_COMMIT" ] || fail "/version reports commit '$GOT_COMMIT', expected '$EXPECTED_COMMIT'"
ok "candidate identity confirmed: version=$GOT_VERSION commit=$GOT_COMMIT"

log "Checking database connectivity via /db-check"
DB_HTTP_CODE=$(curl -s -o /tmp/db-check-response.json -w '%{http_code}' "http://localhost:${CANDIDATE_PORT}/db-check")
if [ "$DB_HTTP_CODE" != "200" ]; then
  log "---- /db-check response ----"
  cat /tmp/db-check-response.json
  log "-----------------------------"
  fail "candidate cannot reach the database (Phase 5 #29/#30) - see response above"
fi
ok "database connectivity confirmed: $(cat /tmp/db-check-response.json | tr -d '\n')"
