#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"
: "${GITHUB_RUN_ATTEMPT:?}" "${GH_TOKEN:?}"
registry="ghcr.io/${GITHUB_REPOSITORY,,}"
build_id="build-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
tag="${build_id}-${GITHUB_SHA:0:12}"
if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "Release $tag already exists; refusing to replace its assets." >&2
  exit 1
fi
references=()
assets=()
for arch in x86_64 arm64; do
  local_image="hhvm-ci:${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${arch}"
  zstd --long=30 -dc "dist/image-${arch}.tar.zst" | docker load
  revision=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$local_image")
  test "$revision" = "$GITHUB_SHA"
  container=$(docker create "$local_image")
  trap 'docker rm "$container" >/dev/null' EXIT
  docker cp "$container:/opt/hhvm" "dist/runtime-${arch}"
  docker rm "$container" >/dev/null
  trap - EXIT
  runtime="dist/runtime-${arch}"
  rm -f "$runtime/.hhvm-local" "$runtime/.runtime-location"
  cp "$runtime/hhvm" "dist/hhvm-linux-${arch}"
  cp "$runtime/manifest.json" "dist/manifest-${arch}.json"
  cp "$runtime/quick-tests.log" "dist/quick-tests-${arch}.log"
  # Each archive extracts to runtime/, matching the README examples.
  mv "$runtime" dist/runtime
  tar -czf "dist/hhvm-linux-${arch}-runtime.tar.gz" -C dist runtime
  rm -rf dist/runtime
  remote_image="${registry}:${build_id}-${arch}"
  docker tag "$local_image" "$remote_image"
  docker push "$remote_image"
  references+=("$remote_image")
  assets+=("hhvm-linux-${arch}" "hhvm-linux-${arch}-runtime.tar.gz"
           "manifest-${arch}.json" "quick-tests-${arch}.log" "build-${arch}.log")
done
docker buildx imagetools create --tag "${registry}:${build_id}" \
  --tag "${registry}:sha-${GITHUB_SHA}" --tag "${registry}:edge" "${references[@]}"
(
  cd dist
  sha256sum "${assets[@]}" > SHA256SUMS
)
cat > dist/release-notes.md <<EOF
Community HHVM build from https://github.com/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA} .

Linux x86-64 and ARM64 were built on matching native hardware and passed the upstream quick suite plus interpreter, JIT, and ImageMagick PNG smoke tests.

Docker image (selects your Linux architecture automatically):

\`docker run --rm ${registry}:${build_id} --version\`

For a standalone Linux runtime, extract the matching runtime archive and run \`./runtime/hhvm-run\`. The raw executable asset requires shared libraries; the runtime archive includes them. Verify downloads with SHA256SUMS. This prerelease contains no macOS binary.
EOF
paths=()
for asset in "${assets[@]}" SHA256SUMS; do paths+=("dist/$asset"); done
gh release create "$tag" "${paths[@]}" --repo "$GITHUB_REPOSITORY" \
  --target "$GITHUB_SHA" --title "HHVM ${GITHUB_SHA:0:12} (${build_id})" \
  --notes-file dist/release-notes.md --prerelease --latest=false
