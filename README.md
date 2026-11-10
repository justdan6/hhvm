# HHVM for Hack: Linux x86-64, ARM64, and macOS build work

Community build work for [HHVM](https://hhvm.com), the just-in-time virtual machine for the [Hack programming language](https://hacklang.org). This fork documents current Linux builds, Docker images, standalone binary releases, and an experimental native Apple Silicon macOS port.

## Build status

Validated source: [`e88b44c9d2a6`](https://github.com/justdan6/hhvm/commit/e88b44c9d2a6c653993568fbaadabec31d497ef0), reporting **HHVM 6.79.0-dev**, on November 4, 2026.

| Platform | Status | Validation |
| --- | --- | --- |
| Linux x86-64 / AMD64 | Working | Interpreter, JIT, and all 861 quick tests; built under Docker Desktop x86 translation |
| Linux ARM64 / AArch64 | Working | Interpreter, JIT, and all 861 quick tests |
| Native macOS ARM64 / Apple Silicon | Experimental, smoke-tested | Interpreter and JIT smoke tests pass; the quick suite aborts before completion; Homebrew libraries are required |

Linux ELF executables run on Linux. Docker Desktop can run the Linux images on a Mac. The native macOS Mach-O build is experimental and is not included in automated releases.

Release automation is included. The image and download examples below become available after the first publishing run; see [release setup](docs/build-releases.md).

## Run HHVM with Docker

The published image supports Linux AMD64 and ARM64:

```sh
docker run --rm ghcr.io/justdan6/hhvm:edge --version
docker run --rm -v "$PWD:/app:ro" ghcr.io/justdan6/hhvm:edge /app/example.hack
```

`edge` follows the latest successful publishing run. Use a release's `build-<run-id>-<attempt>` tag to pin a particular build. Under Docker Desktop's x86 translation, add `-e EVENT_NOEPOLL=1` if libevent's epoll backend fails.

## Run a standalone Linux binary

Download the matching `hhvm-linux-x86_64-runtime.tar.gz` or `hhvm-linux-arm64-runtime.tar.gz` from [Releases](https://github.com/justdan6/hhvm/releases), then verify and extract it:

```sh
sha256sum --ignore-missing -c SHA256SUMS
case "$(uname -m)" in
  x86_64|amd64) arch=x86_64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
tar -xzf "hhvm-linux-${arch}-runtime.tar.gz"
./runtime/hhvm-run --version
./runtime/hhvm-run example.hack
```

The runtime archive includes its loader, shared libraries, ImageMagick configuration, license notices, and a source/hash manifest. Its launcher creates a private relocated binary on first use, so extract it to a writable directory with space for another copy of the executable. Moving the directory regenerates that copy. Docker is not needed to run the Linux bundle.

Raw executable assets are also provided for users supplying their own compatible libraries.

## Build HHVM from source

Clone this fork, then build for your machine's Linux architecture:

```sh
git clone --recursive https://github.com/justdan6/hhvm.git
cd hhvm
docker build -f build/release/Dockerfile \
  --build-arg VCS_REF="$(git rev-parse HEAD)" -t hhvm:local .
docker run --rm hhvm:local --version
```

The Docker build compiles HHVM, runs interpreter/JIT smoke tests and the quick suite, and creates an unprivileged runtime image. Keep at least 80 GiB available for source, dependencies, build cache, and packaging; builds can take hours. Dependencies are cached separately for AMD64 and ARM64.

For AMD64 on Apple Silicon, add `--platform linux/amd64 --build-arg EMULATED=1`. For ARM64, use `--platform linux/arm64`. Native hardware is preferred for release builds.

For native Linux instructions, binary export, and the macOS investigation, read [building HHVM](docs/building-hhvm.md).

The native Apple Silicon port is available as an experimental patch at [`build/macos/experimental-port.patch`](build/macos/experimental-port.patch). It needs Homebrew dylibs at runtime and has not passed the full quick suite; see the [macOS build notes](docs/building-hhvm.md#native-apple-silicon-macos-investigation) before using or distributing it.

## What needed fixing

- Scope mcrouter-only CMake options to mcrouter, so shared dependencies retain consistent getdeps hashes.
- Pin Rust nightly **2026-08-15** and the opam package index; preserve locked Cargo versions while restoring missing source/checksum metadata.
- Seed the generated Rust FFI workspace's Cargo lockfile.
- Keep the public dependency release train, producer libdwarf, PCRE 8, ImageMagick 6, and compatible c-ares version aligned.
- Under Docker Desktop x86 translation, use libarchive tar and libevent's poll backend where GNU tar and epoll operations fail.
- Native Apple Silicon additionally needs Mach-O, Darwin API, memory layout, code-pointer, and JIT write-protection work. It is not yet listed as a working release platform.

These builds use Ubuntu 26.04, Clang/LLD 21, glibc 2.43, and pinned public dependencies. The bundle carries glibc, but the host's kernel, system CA trust store, and timezone data still matter. Validation on other Linux distributions and physical x86 hardware is pending.

The upstream [2023 project update](https://hhvm.com/blog/2023/10/27/oss-update.html) explains the release/build-system changes. Native Homebrew support was [deprecated in 2022](https://hhvm.com/blog/2022/06/17/deprecating-homebrew.html). This fork's builds are community work.

## Automated builds and releases

The [release workflow](.github/workflows/oss-release.yml) builds on pushes to `master`, weekly, or on manual dispatch. Publishing requires both Linux architectures to pass. It produces multi-architecture GHCR images plus GitHub prereleases containing raw binaries, runtime archives, checksums, manifests, and test logs.

[Configure runners, enable publishing, and keep up with upstream commits](docs/build-releases.md). No container package or GitHub release is published until you enable that step.

## Documentation and license

[HHVM documentation](https://docs.hhvm.com/hhvm-overview) · [Hack documentation](https://docs.hhvm.com/hack/) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

HHVM uses the PHP and Zend licenses except where noted. The [Hack typechecker](hphp/hack/LICENSE) and [Hack Standard Library](hphp/hsl/LICENSE) use the MIT license except where noted. Runtime bundles include collected third-party notices.
