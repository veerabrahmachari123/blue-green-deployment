#!/usr/bin/env bash
# Jenkins stage: Docker Image Validation
# Confirms the image (not yet a running container) actually carries the
# version/commit identity it claims to (Phase 4 traceability), catching
# Phase 5 scenario #36 (tag exists, but wasn't really rebuilt for this SHA).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

IMAGE_TAG="${1:?usage: validate-image.sh <image_tag> <expected_version> <expected_commit>}"
EXPECTED_VERSION="${2:?}"
EXPECTED_COMMIT="${3:?}"

log "Validating image $IMAGE_TAG"

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  fail "image $IMAGE_TAG does not exist (Phase 5 scenario #36: requested version tag was never built)"
fi

LABEL_VERSION=$(docker image inspect -f '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$IMAGE_TAG")
LABEL_COMMIT=$(docker image inspect -f '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$IMAGE_TAG")

[ "$LABEL_VERSION" = "$EXPECTED_VERSION" ] || fail "image label version '$LABEL_VERSION' != expected '$EXPECTED_VERSION'"
[ "$LABEL_COMMIT" = "$EXPECTED_COMMIT" ] || fail "image label commit '$LABEL_COMMIT' != expected '$EXPECTED_COMMIT'"

ok "image $IMAGE_TAG carries version=$LABEL_VERSION commit=$LABEL_COMMIT"
