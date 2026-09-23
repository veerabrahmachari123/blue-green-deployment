#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: deployment-verification.sh <version> <commit> <color>}"
COMMIT="${2:?Usage: deployment-verification.sh <version> <commit> <color>}"
EXPECTED_COLOR="${3:?Usage: deployment-verification.sh <version> <commit> <color>}"

ROUTER_URL="${ROUTER_URL:-http://localhost:8080}"

log() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

fail() {
    log "FAIL - $*"
    exit 1
}

pass() {
    log "PASS - $*"
}

log "========================================="
log "DEPLOYMENT VERIFICATION"
log "========================================="

log "Expected version : ${VERSION}"
log "Expected commit  : ${COMMIT}"
log "Expected color   : ${EXPECTED_COLOR}"
log "Router           : ${ROUTER_URL}"

# --------------------------------------------------
# 1. Verify router active color
# --------------------------------------------------

log "Checking router active color..."

ROUTER_STATUS="$(curl -fsS "${ROUTER_URL}/router-status")" \
    || fail "Unable to query router status"

echo "${ROUTER_STATUS}"

ACTIVE_COLOR="$(
    printf '%s\n' "${ROUTER_STATUS}" |
    sed -n 's/^active-color:[[:space:]]*//p' |
    tr -d '\r'
)"

if [ -z "${ACTIVE_COLOR}" ]; then
    fail "Could not determine active router color"
fi

if [ "${ACTIVE_COLOR}" != "${EXPECTED_COLOR}" ]; then
    fail "router active color '${ACTIVE_COLOR}' does not match deployed color '${EXPECTED_COLOR}'"
fi

pass "router active color is '${ACTIVE_COLOR}'"

# --------------------------------------------------
# 2. Verify production /version
# --------------------------------------------------

log "Checking production application identity..."

VERSION_RESPONSE="$(curl -fsS "${ROUTER_URL}/version")" \
    || fail "Production /version endpoint is unavailable"

echo "${VERSION_RESPONSE}"

ACTUAL_VERSION="$(
    printf '%s\n' "${VERSION_RESPONSE}" |
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
)"

ACTUAL_COMMIT="$(
    printf '%s\n' "${VERSION_RESPONSE}" |
    sed -n 's/.*"gitCommit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
)"

ACTUAL_COLOR="$(
    printf '%s\n' "${VERSION_RESPONSE}" |
    sed -n 's/.*"color"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
)"

if [ -z "${ACTUAL_VERSION}" ]; then
    fail "Could not determine production version"
fi

if [ "${ACTUAL_VERSION}" != "${VERSION}" ]; then
    fail "production version '${ACTUAL_VERSION}' does not match expected '${VERSION}'"
fi

pass "production version is '${ACTUAL_VERSION}'"

if [ -z "${ACTUAL_COMMIT}" ]; then
    fail "Could not determine production git commit"
fi

if [ "${ACTUAL_COMMIT}" != "${COMMIT}" ]; then
    fail "production commit '${ACTUAL_COMMIT}' does not match expected '${COMMIT}'"
fi

pass "production commit is '${ACTUAL_COMMIT}'"

if [ -z "${ACTUAL_COLOR}" ]; then
    fail "Could not determine production color"
fi

if [ "${ACTUAL_COLOR}" != "${EXPECTED_COLOR}" ]; then
    fail "production color '${ACTUAL_COLOR}' does not match expected '${EXPECTED_COLOR}'"
fi

pass "production color is '${ACTUAL_COLOR}'"

# --------------------------------------------------
# 3. Verify health
# --------------------------------------------------

log "Checking production health..."

HEALTH_RESPONSE="$(curl -fsS "${ROUTER_URL}/health")" \
    || fail "Production health check failed"

echo "${HEALTH_RESPONSE}"

HEALTH_STATUS="$(
    printf '%s\n' "${HEALTH_RESPONSE}" |
    sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
)"

if [ "${HEALTH_STATUS}" != "ok" ]; then
    fail "production health status is '${HEALTH_STATUS}', expected 'ok'"
fi

pass "production health is OK"

# --------------------------------------------------
# 4. Create deployment evidence
# --------------------------------------------------

log "Creating deployment evidence..."

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="${ROOT}/.evidence"
MANIFEST="${EVIDENCE_DIR}/deployment-${VERSION}.json"

mkdir -p "${EVIDENCE_DIR}"

cat > "${MANIFEST}" <<EOF
{
  "version": "${ACTUAL_VERSION}",
  "gitCommit": "${ACTUAL_COMMIT}",
  "activeColor": "${ACTIVE_COLOR}",
  "verifiedAt": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "router": "${ROUTER_URL}",
  "routerStatusResponse": ${ROUTER_STATUS},
  "versionResponse": ${VERSION_RESPONSE},
  "healthResponse": ${HEALTH_RESPONSE}
}
EOF

if [ ! -f "${MANIFEST}" ]; then
    fail "deployment evidence file was not created"
fi

pass "deployment evidence created: ${MANIFEST}"
log "========================================="
log "DEPLOYMENT VERIFICATION SUCCESSFUL"
log "========================================="
log "Active color : ${ACTIVE_COLOR}"
log "Version      : ${ACTUAL_VERSION}"
log "Commit       : ${ACTUAL_COMMIT}"
log "Router       : ${ROUTER_URL}"
log "========================================="
cat "${MANIFEST}"
