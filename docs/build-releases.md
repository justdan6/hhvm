# Publish HHVM Docker images and GitHub binary releases

This workflow is prepared for `justdan6/hhvm`. It has not been run on GitHub or published by the local build investigation. It builds and releases Linux x86-64 and ARM64. Native macOS passes interpreter/JIT smoke tests, but its 861-test quick suite was attempted and aborted before completion; a clean-machine build has not been validated, and the binary depends on Homebrew dylibs. It is not part of automated publishing.

## One-time setup

1. Push the reviewed build fixes, README, `build/release/`, and `.github/workflows/oss-release.yml` to the fork's `master` branch. The old GCC/compiler-matrix workflow is retained as manual-only; the tested Clang release workflow replaces its automatic trigger.
2. Register two [self-hosted Linux runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners): one x86-64 with labels `Linux,X64,hhvm`, and one ARM64 with labels `Linux,ARM64,hhvm`. Each needs Docker with BuildKit/Buildx, Git, zstd, at least 16 GiB RAM (32 GiB preferred), and at least 80 GiB available for builds and packaging. Keep the Docker cache between runs. These runners build trusted branch commits; the workflow has no pull-request trigger.
3. Enable Actions on the fork and allow the pinned actions used by the workflow. The publishing job requests `contents: write` and `packages: write` for its built-in `GITHUB_TOKEN`; build jobs only request read access. No Docker Hub account or personal token is needed in CI.
4. Run a build without publishing:

   ```sh
   gh workflow enable oss-release.yml --repo justdan6/hhvm
   gh workflow run oss-release.yml --repo justdan6/hhvm --ref master -f publish=false
   gh run list --repo justdan6/hhvm --workflow oss-release.yml
   gh run watch RUN_ID --repo justdan6/hhvm
   ```

To use larger hosted runners instead, set `HHVM_RUNNER_X86_64` and `HHVM_RUNNER_ARM64` repository variables to JSON arrays of their runner labels. Standard hosted runners have tight disk limits; a cold HHVM build also needs to fit the [hosted six-hour job limit](https://docs.github.com/en/actions/reference/limits). The defaults therefore use self-hosted runners. Public repositories have [native ARM64 hosted runners](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/), but their disk still needs to accommodate this build.

## Publish a build

After the build-only run succeeds:

```sh
gh workflow run oss-release.yml --repo justdan6/hhvm --ref master -f publish=true
```

Both architectures must build and pass tests before the publishing job starts. It publishes:

| Destination | Contents |
| --- | --- |
| `ghcr.io/justdan6/hhvm:build-<run-id>-<attempt>` | Multi-architecture Linux runtime image for that run |
| `ghcr.io/justdan6/hhvm:sha-<full-commit>` | Most recent successful build of that source commit |
| `ghcr.io/justdan6/hhvm:edge` | Most recent successful publishing run |
| GitHub prerelease `build-<run-id>-<attempt>-<short-commit>` | Raw x86-64/ARM64 binaries, runtime archives, SHA256SUMS, manifests, and logs |

The per-run tag identifies a particular build. `edge` and the commit alias can change on rebuilds. These are community development prereleases, so the workflow does not label them stable or mark them GitHub's latest stable release.

After the first push, open the [container package](https://github.com/justdan6?tab=packages), select `hhvm`, and set its visibility to **Public** if you want anonymous pulls. GHCR packages start private even for public repositories. The workflow token and source label connect the package to this repository. See [GitHub's Container Registry documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Check the result:

```sh
docker buildx imagetools inspect ghcr.io/justdan6/hhvm:edge
docker run --rm ghcr.io/justdan6/hhvm:edge --version
gh release list --repo justdan6/hhvm
```

The release assets include an ELF executable for each Linux architecture and a runtime archive with its library closure. No build tools or Docker installation are required to use the extracted runtime on a compatible Linux host. Use `SHA256SUMS` to verify downloads.

## Continuous builds

Pushes to `master` and the Monday 09:17 UTC schedule build and test both Linux architectures. Publishing is off by default. Enable publishing for subsequent pushes and scheduled runs with:

```sh
gh variable set HHVM_PUBLISH_CONTINUOUS --repo justdan6/hhvm --body true
```

Set it to `false` to return to build-only runs. A manual run always uses its own `publish` input.

Actions artifacts retain the tested image and build log for one day; GitHub Releases are the durable download location. Long-window zstd compression avoids uploading duplicate binary data. Check your account's [artifact storage allowance](https://docs.github.com/en/actions/reference/limits) before enabling frequent builds. GitHub may disable a fork's scheduled workflows until you enable them, or disable public schedules after 60 days without repository activity; see [enabling workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows).

The schedule rebuilds this fork's current `master`; it does not silently merge Facebook's upstream branch. To incorporate new upstream commits:

```sh
# Once, if this remote is not already configured:
git remote add upstream https://github.com/facebook/hhvm.git

git switch master
git fetch upstream
git merge upstream/master
# Resolve any conflicts with this fork's build fixes, then:
git push origin master
```

The push starts the tested release pipeline. When upstream changes its Rust, OCaml, Folly, or Proxygen interfaces, review the matching pins before publishing. Keep failed builds as failed checks; the workflow publishes only after both architecture jobs succeed.

### Experimental native macOS asset

The delivered `hhvm-macos-arm64` executable was built on Apple Silicon from the `e88b44c9d2a6` source plus [`build/macos/experimental-port.patch`](../build/macos/experimental-port.patch). It passes interpreter and JIT smoke tests. The full quick suite aborts before completion; it links to Homebrew dylibs and should only be uploaded with release notes listing that dependency requirement.

To attach this local build to a matching GitHub release, run this from the delivered `outputs/` directory after reviewing the artifact and checksum:

```sh
gh release upload RELEASE_TAG \
  hhvm-macos-arm64 hhvm-macos-arm64-README.md \
  hhvm-macos-arm64-SHA256SUMS.txt \
  hhvm-macos-build/experimental-port.patch \
  --repo justdan6/hhvm
```

The current continuous workflow does not build or publish macOS assets. Automating them requires a native Apple Silicon self-hosted runner with the pinned dependency cache and a complete macOS quick-suite pass. Pushes and the weekly schedule already continuously rebuild the two supported Linux architectures.

## Upload the existing locally built artifacts

These commands are for the already validated `e88b44c9d2a6` builds. Run them from the directory containing the delivered binaries, runtime archives, image archives, checksums, and build kits. They publish externally; review the files and release notes first.

```sh
gh auth refresh --hostname github.com --scopes write:packages
gh auth token | docker login ghcr.io --username justdan6 --password-stdin
zstd --long=30 -dc hhvm-linux-x86_64-image.tar.zst | docker load
zstd --long=30 -dc hhvm-linux-arm64-image.tar.zst | docker load

docker tag hhvm-reviewed-runtime:linux-x86_64 ghcr.io/justdan6/hhvm:local-e88b44c9d2a6-x86_64
docker tag hhvm-reviewed-runtime:linux-arm64 ghcr.io/justdan6/hhvm:local-e88b44c9d2a6-arm64
docker push ghcr.io/justdan6/hhvm:local-e88b44c9d2a6-x86_64
docker push ghcr.io/justdan6/hhvm:local-e88b44c9d2a6-arm64
docker buildx imagetools create --tag ghcr.io/justdan6/hhvm:local-e88b44c9d2a6 \
  ghcr.io/justdan6/hhvm:local-e88b44c9d2a6-x86_64 \
  ghcr.io/justdan6/hhvm:local-e88b44c9d2a6-arm64
```

Create `release-notes.md` identifying the source commit, the attached build patches, compiler/dependency pins, and validation. Then publish the binary assets:

```sh
gh release create local-e88b44c9d2a6-community.1 --repo justdan6/hhvm \
  --target e88b44c9d2a6c653993568fbaadabec31d497ef0 \
  --title 'HHVM 6.79.0-dev: Linux x86-64 and ARM64' \
  --notes-file release-notes.md --prerelease --latest=false \
  hhvm-linux-x86_64 hhvm-linux-arm64 \
  hhvm-linux-x86_64-runtime.tar.gz hhvm-linux-arm64-runtime.tar.gz \
  HHVM-SHA256SUMS.txt hhvm-linux-x86_64-build-kit.zip hhvm-build-kit.zip
```

Use a new versioned tag if you publish another local build. The automated workflow is the repeatable path after the reviewed fork changes are pushed. It records the actual new fork commit and creates its own per-run tags.

## Make the fork easier to find

The main README uses HHVM, Hack, Docker, Linux AMD64/x86-64, ARM64/AArch64, macOS, and Apple Silicon in its title, platform table, and relevant instructions. Keep its build status and source commit accurate as releases change.

In the repository's **About** settings, use a concise description such as:

> Community HHVM builds for Hack: Linux x86-64 and ARM64 Docker images and standalone binaries, with experimental Apple Silicon macOS porting.

Suggested topics: `hhvm`, `hacklang`, `hack`, `virtual-machine`, `jit`, `linux`, `arm64`, `aarch64`, `amd64`, `x86-64`, `macos`, `apple-silicon`, `docker`. Add a release link to the About website field after publishing. These improve discoverability without claiming unverified platform support.
