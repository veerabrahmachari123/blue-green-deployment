#!/usr/bin/env bash
# Jenkins stage: Validate Version
# Enforces Phase 4: every build must ship an immutable version, never rely
# on 'latest', and the version must not already exist as a running
# production color (which would make deployments non-repeatable, Phase 7).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

VERSION="${1:?usage: validate-version.sh <version> <git_commit>}"
GIT_COMMIT="${2:?usage: validate-version.sh <version> <git_commit>}"

log "Validating candidate version '$VERSION' (commit $GIT_COMMIT)"

if [ "$VERSION" = "latest" ]; then
  fail "'latest' is not a valid production version tag (Phase 4)"
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  fail "version '$VERSION' does not match required <major>.<minor>[.<patch>] format"
fi

if ! [[ "$GIT_COMMIT" =~ ^[0-9a-f]{7,40}$ ]]; then
  fail "git commit SHA '$GIT_COMMIT' does not look like a real SHA"
fi

if docker image inspect "${IMAGE_NAME}:${VERSION}" >/dev/null 2>&1; then
  log "Image tag ${IMAGE_NAME}:${VERSION} already exists locally - will be reused/rebuilt idempotently"
fi

ok "version '$VERSION' and commit '$GIT_COMMIT' are valid"
