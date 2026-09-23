#!/usr/bin/env bash

# Jenkins stage:
# Docker Build
#
# Usage:
#   build-image.sh <version> <git_commit>
#
# Example:
#   build-image.sh 7.9 8a2518b82bbfdebce03f64990106690755932ccc
#
# Output:
#   Logs are written during the build.
#   The final line is ALWAYS the immutable image tag when successful.
#
# Failure:
#   The script exits immediately if docker build fails.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

ROOT="$(cd "$DIR/.." && pwd)"

VERSION="${1:?usage: build-image.sh <version> <git_commit>}"
GIT_COMMIT="${2:?usage: build-image.sh <version> <git_commit>}"

SHORT_SHA="${GIT_COMMIT:0:7}"

# Immutable image tag.
#
# Example:
#   orders-api:7.9-8a2518b
#
# This identifies exactly:
#   application version + Git commit
IMMUTABLE_TAG="${IMAGE_NAME}:${VERSION}-${SHORT_SHA}"

# Human-friendly version tag.
#
# Example:
#   orders-api:7.9
VERSION_TAG="${IMAGE_NAME}:${VERSION}"

log "Building ${IMMUTABLE_TAG} (also tagged ${VERSION_TAG})"

echo "Docker build context:"
echo "${ROOT}"

echo "Dockerfile:"
echo "${ROOT}/Dockerfile"

# Verify Dockerfile exists before invoking Docker.
if [ ! -f "${ROOT}/Dockerfile" ]; then
    echo "ERROR: Dockerfile not found:"
    echo "${ROOT}/Dockerfile"
    exit 1
fi

# IMPORTANT FOR WINDOWS JENKINS:
#
# Do NOT set MSYS_NO_PATHCONV=1 here.
#
# Git Bash needs to convert:
#
#   /c/ProgramData/Jenkins/...
#
# into:
#
#   C:/ProgramData/Jenkins/...
#
# so that Docker Desktop on Windows can access the build context.
#
# The Jenkinsfile only sets MSYS_NO_PATHCONV=1 for docker run commands
# that require Linux container paths such as /app.

docker build \
    --build-arg VERSION="${VERSION}" \
    --build-arg GIT_COMMIT="${GIT_COMMIT}" \
    -t "${IMMUTABLE_TAG}" \
    -t "${VERSION_TAG}" \
    -f "${ROOT}/Dockerfile" \
    "${ROOT}"

# Docker build succeeded.
#
# Do not print this line before the Docker command.
# Jenkins uses the final line as the image identifier.

ok "built ${IMMUTABLE_TAG}"

echo "${IMMUTABLE_TAG}"