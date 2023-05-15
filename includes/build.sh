#!/usr/bin/env bash

set -euo pipefail
ROOTDIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../")
export ROOTDIR
cd "$ROOTDIR"

source "./includes/utils.sh"

ARCH="${1:-}"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" ]]; then
    fatal 129 "Missing architecture argument"
fi

GIT_VERSION="$(cat ./git_version)"

step "Building ${ARCH} image for git ${GIT_VERSION}"
info "Executing docker build…"
docker build -t lambda-git-build:${GIT_VERSION}-${ARCH} --build-arg BUILD_ARCH=$ARCH --build-arg GIT_VERSION=2.33.1 .
rm docker-build.log
info "Docker build finished successfully"
