#!/usr/bin/env bash
# Documented cleanup policy (Phase 7: "Clean up unused candidate
# containers/images according to a documented policy"). Run at the end of
# every pipeline execution, success or failure.
#
# POLICY:
#   1. Any dangling/failed candidate container is removed immediately by
#      rollback-candidate.sh / cleanup-old.sh - this script never has to
#      touch containers, only images.
#   2. Keep the images for the current production version and the
#      KEEP_LAST_N most recent previous versions (for fast rollback).
#   3. Remove all older orders-api image tags.
#   4. Never remove an image tag that a currently-running container
#      references.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

KEEP_LAST_N="${KEEP_LAST_N:-3}"

log "Cleanup policy: keep current production image + last $KEEP_LAST_N previous versions"

IN_USE_IMAGES=$(docker ps -a --filter "name=orders-" --format '{{.Image}}' | sort -u)

ALL_TAGS=$(docker images "${IMAGE_NAME}" --format '{{.Tag}}' | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9a-f]{7}$' | sort -Vr || true)

if [ -z "$ALL_TAGS" ]; then
  log "no immutable version-tagged images found - nothing to clean up"
  exit 0
fi

KEEP_TAGS=$(echo "$ALL_TAGS" | head -n "$KEEP_LAST_N")
REMOVE_TAGS=$(echo "$ALL_TAGS" | tail -n +"$((KEEP_LAST_N + 1))")

if [ -z "$REMOVE_TAGS" ]; then
  log "nothing beyond the retention window - nothing to remove"
  exit 0
fi

for tag in $REMOVE_TAGS; do
  FULL="${IMAGE_NAME}:${tag}"
  if echo "$IN_USE_IMAGES" | grep -qx "$FULL"; then
    log "skipping $FULL - currently in use by a running container"
    continue
  fi
  log "removing old image $FULL"
  docker rmi "$FULL" >/dev/null 2>&1 || log "could not remove $FULL (may be referenced elsewhere) - leaving it"
done

ok "cleanup complete. kept: $(echo "$KEEP_TAGS" | tr '\n' ' ')"
