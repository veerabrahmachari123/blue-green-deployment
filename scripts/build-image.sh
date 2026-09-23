#!/usr/bin/env bash
# Jenkins stage: Docker Build
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
ROOT="$(cd "$DIR/.." && pwd)"

VERSION="${1:?usage: build-image.sh <version> <git_commit>}"
GIT_COMMIT="${2:?usage: build-image.sh <version> <git_commit>}"
SHORT_SHA="${GIT_COMMIT:0:7}"

# Two tags: an immutable one keyed to version+commit (what actually gets
# deployed and is traceable back to Git), and a human-friendly version tag.
# 'latest' is never used as the deploy identifier (Phase 4).
IMMUTABLE_TAG="${IMAGE_NAME}:${VERSION}-${SHORT_SHA}"
VERSION_TAG="${IMAGE_NAME}:${VERSION}"

log "Building $IMMUTABLE_TAG (also tagged $VERSION_TAG)"
docker build \
  --build-arg VERSION="$VERSION" \
  --build-arg GIT_COMMIT="$GIT_COMMIT" \
  -t "$IMMUTABLE_TAG" \
  -t "$VERSION_TAG" \
  -f "$ROOT/Dockerfile" \
  "$ROOT"

ok "built $IMMUTABLE_TAG"
echo "$IMMUTABLE_TAG"
