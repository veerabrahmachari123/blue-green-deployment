#!/usr/bin/env bash
# Shared helpers sourced by every script in scripts/. Keeping this in one
# place is what lets the Jenkinsfile fail fast (set -e) and print consistent,
# secret-free diagnostics from every stage.

set -euo pipefail

NETWORK_NAME="${NETWORK_NAME:-orders-network}"
ROUTER_CONTAINER="${ROUTER_CONTAINER:-orders-router}"
ROUTER_CONF="${ROUTER_CONF:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/router/active-backend.conf}"
DB_CONTAINER="${DB_CONTAINER:-orders-db}"
IMAGE_NAME="${IMAGE_NAME:-orders-api}"

log()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
ok()   { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] OK   - $*"; }
fail() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FAIL - $*" >&2; exit 1; }

# Never print raw env output of a container without filtering secrets -
# used by container-validation.sh so pipeline logs stay clean (Phase 7).
redact_env() {
  # Reads docker inspect env output on stdin, masks anything that looks
  # like a secret/password/token/key.
  sed -E 's/^(([A-Z0-9_]*)(SECRET|PASSWORD|TOKEN|KEY)([A-Z0-9_]*)=).*/\1***REDACTED***/'
}

other_color() {
  case "$1" in
    blue) echo "green" ;;
    green) echo "blue" ;;
    *) fail "unknown color '$1'" ;;
  esac
}

color_port() {
  case "$1" in
    blue) echo "8081" ;;
    green) echo "8082" ;;
    *) fail "unknown color '$1'" ;;
  esac
}

# Reads the '# ACTIVE_COLOR=<blue|green>' marker line written into
# router/active-backend.conf by switch-traffic.sh. This is the single
# source of truth for "what is currently serving production traffic".
current_active_color() {
  local status
  status=$(curl -fsS "http://localhost:8080/router-status") ||
    fail "could not query router status"

  status=$(printf '%s\n' "$status" |
    sed -n 's/^active-color: //p')

  if [ -z "$status" ]; then
    fail "could not determine active color from router status"
  fi

  echo "$status"
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = "true" ]
}

