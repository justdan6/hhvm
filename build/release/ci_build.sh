#!/usr/bin/env bash
set -euo pipefail
: "${RELEASE_ARCH:?}" "${RELEASE_PLATFORM:?}" "${GITHUB_SHA:?}"
: "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}"
case "$RELEASE_ARCH:$(uname -m)" in
  x86_64:x86_64|arm64:aarch64) ;;
  *) echo 'Release builds require matching native Linux hardware.' >&2; exit 1 ;;
esac
mkdir -p dist
dist="$PWD/dist"
image="hhvm-ci:${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${RELEASE_ARCH}"
docker build --platform "$RELEASE_PLATFORM" --progress=plain \
  --build-arg VCS_REF="$GITHUB_SHA" --build-arg BUILD_JOBS="${HHVM_RELEASE_JOBS:-4}" \
  -f build/release/Dockerfile -t "$image" . 2>&1 | tee "$dist/build-${RELEASE_ARCH}.log"
docker run --rm "$image" --version
docker run --rm "$image" -vEval.Jit=false /opt/hhvm/smoke.hack
docker run --rm "$image" -vEval.Jit=true /opt/hhvm/smoke.hack
docker run --rm "$image" -vEval.Jit=false /opt/hhvm/imagick-smoke.hack
# A long zstd window deduplicates the original and relocated HHVM copies.
# Transfer the tested image once; the publish job extracts release assets.
docker save "$image" | zstd -T2 --long=30 -6 -o "$dist/image-${RELEASE_ARCH}.tar.zst"
