#!/usr/bin/env bash
# Jenkins stage: Deployment Verification
# The last stage before the build is allowed to go green. Writes a
# deployment manifest that ties the running version back to the exact Git
# commit (Phase 4 traceability / Final Deliverables: "successful deployment
# evidence").
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
ROOT="$(cd "$DIR/.." && pwd)"

VERSION="${1:?usage: deployment-verification.sh <version> <git_commit> <color>}"
GIT_COMMIT="${2:?}"
COLOR="${3:?}"

ACTIVE_COLOR=$(current_active_color)
[ "$ACTIVE_COLOR" = "$COLOR" ] || fail "router active color '$ACTIVE_COLOR' does not match deployed color '$COLOR'"

OLD_COLOR=$(other_color "$COLOR")
OLD_CONTAINER="orders-${OLD_COLOR}"
if container_exists "$OLD_CONTAINER"; then
  fail "old color container '$OLD_CONTAINER' still exists - Old Version Cleanup did not complete"
fi

ROUTER_VERSION_JSON=$(curl -sf "http://localhost:8080/version") || fail "router not responding on port 8080"
ROUTER_HEALTH_JSON=$(curl -sf "http://localhost:8080/health") || fail "router /health not responding on port 8080"

mkdir -p "$ROOT/.evidence"
MANIFEST="$ROOT/.evidence/deployment-${VERSION}.json"
cat > "$MANIFEST" <<EOF
{
  "version": "${VERSION}",
  "gitCommit": "${GIT_COMMIT}",
  "activeColor": "${COLOR}",
  "verifiedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "routerVersionResponse": ${ROUTER_VERSION_JSON},
  "routerHealthResponse": ${ROUTER_HEALTH_JSON}
}
EOF

ok "deployment verified: version=$VERSION commit=$GIT_COMMIT color=$COLOR"
log "manifest written to $MANIFEST"
cat "$MANIFEST"
