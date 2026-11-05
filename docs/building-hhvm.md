# Build HHVM on Linux x86-64, Linux ARM64, and macOS

Current tested source is `e88b44c9d2a6c653993568fbaadabec31d497ef0`, HHVM 6.79.0-dev. Linux ARM64 and x86-64 each passed all 861 quick tests plus interpreter and JIT smoke tests. The x86-64 build was executed under Docker Desktop's x86 translation on Apple Silicon. The exported x86-64 runtime additionally passed version, interpreter, JIT, and ImageMagick PNG tests in a clean Ubuntu container without the original build cache, including after moving it to a path with spaces.

## Native Linux source build

Use Ubuntu 26.04 on matching x86-64 or ARM64 hardware, with at least 16 GiB RAM and 80 GiB available disk space. Install the selected compiler and basic download tools:

```sh
sudo apt-get update
sudo apt-get install -y clang-21 lld-21 curl git ca-certificates
sudo update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-21 1000
git clone --recursive https://github.com/justdan6/hhvm.git
cd hhvm
export HHVM_OSS_WORK_ROOT="$PWD/.hhvm-build"
export HHVM_OSS_BUILD_JOBS=4
export HHVM_OSS_C_COMPILER=clang-21
export HHVM_OSS_CXX_COMPILER=clang++-21
./build/oss_build.sh
export HHVM_BIN="$HHVM_OSS_WORK_ROOT/hhvm/hphp/hhvm/hhvm"
"$HHVM_BIN" --version
./hphp/test/run quick --threads 4
```

Run the test suite as a regular user; tests concerning permissions can behave differently as root. The build script installs remaining system prerequisites and downloads public source dependencies. Re-running it reuses completed phases; `--make` rebuilds the configured target, while `--rebuild` reconfigures HHVM and keeps its dependencies.

## Docker build and binary export

From the repository root:

```sh
docker build -f build/release/Dockerfile \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_JOBS=4 -t hhvm:local .
docker run --rm hhvm:local --version
```

The build runs the quick suite without root privileges before producing the runtime image. For AMD64 on Apple Silicon add `--platform linux/amd64 --build-arg EMULATED=1`. The Docker Desktop virtual machine needs enough assigned CPU, memory, and disk space. Native Linux hardware is used by the release workflow.

Extract the raw binary from the image:

```sh
container=$(docker create hhvm:local)
docker cp "$container:/opt/hhvm/hhvm" ./hhvm-linux
docker cp "$container:/opt/hhvm" ./hhvm-runtime
docker rm "$container"
./hhvm-runtime/hhvm-run --version
```

The raw binary requires compatible libraries. The runtime directory includes them, along with the glibc loader and ImageMagick configuration. Its launcher preserves the original binary and makes a private copy with a relocated ELF interpreter and `$ORIGIN/lib` search path. This matters because invoking ld-linux directly breaks HHVM's `/proc/self/exe` metadata lookup and low-address program-break assumptions. First launch needs write access and another binary-sized allocation of disk space.

The image initializes its private copy on first launch as an unprivileged user. Exported runtime directories initialize their own copy at the new location. Release archives omit that temporary copy. Bundled glibc reduces host userspace requirements; kernel interfaces, system trust roots, and timezone data remain host dependencies. Validation beyond the recorded Ubuntu environment is pending.

## Dependency and build fixes

| Area | Finding and change |
| --- | --- |
| getdeps | Global mcrouter-only CMake options changed dependency hashes and selected inconsistent builds. Apply those options only in the mcrouter manifest. |
| Rust | Use nightly `2026-08-15`, matching the pinned ocamlrep dependency. Restore Git source pins/checksums for the existing locked versions and fetch with `--locked`. |
| Rust FFI | Copy the checked-in Cargo.lock into the generated bridge workspace to prevent a separate dependency resolution. |
| OCaml/opam | Pin opam repository `50e5bad7b3a9f9400cd3629a6dde7338da3ee14c` and verify its source archive. |
| C++ dependency train | Keep Folly, Fizz, Wangle, mvfst, fbthrift, Proxygen, and mcrouter on the compatible `v2026.08.24.00` public release train. |
| Older dependency APIs | Retain producer libdwarf `20210528`, PCRE `8.45`, ImageMagick `6.9.13-33`, and c-ares `1.34.6` for the APIs expected by this tree. |
| x86 translation: extraction | GNU tar nested-path extraction returned an unimplemented-operation error. libarchive's bsdtar extracted the same verified archives. |
| x86 translation: libevent | epoll event dispatch returned `ENOSYS`, aborting systemlib bootstrap. `EVENT_NOEPOLL=1` selects the working poll backend. This is an emulation workaround. |
| Export | A raw HHVM executable has a substantial shared-library closure. Export the actual libraries and loader, check their ELF architecture, and record hashes/package versions/notices. |

The Docker base and direct source archives are pinned, but apt packages and compiler output are not claimed to be bit-for-bit reproducible across rebuilds. Each release includes checksums for its actual artifacts.

## Native Apple Silicon macOS investigation

The experimental native ARM64 Mach-O executable builds and runs on Apple Silicon with macOS 27.2, Apple Clang 21, and the macOS 27.2 SDK. It reports HHVM 6.79.0-dev and passes the interpreter and JIT smoke program used by the Linux release workflow. The 861-test quick suite was attempted but did not complete: the normal runner segfaulted while receiving worker messages, and a temporary sequential-runner workaround reached an HHVM JIT `CodeCache::blockFor` assertion. No complete pass/fail count is available. The current executable links to Homebrew dylibs and is not a portable, self-contained Mac release.

Apply [`build/macos/experimental-port.patch`](../build/macos/experimental-port.patch) to the current fork source before configuring. Install Apple's command-line tools, Homebrew, and LLD (`brew install lld`). Native builds must use `ld64.lld`: Apple's Xcode 27 linker reproducibly traps during the final HHVM link while laying out its embedded systemlib sections. The CMake toolchain selects LLD when it is available. Use a pinned dependency cache and a native Apple Silicon host; the full build also needs the Rust nightly and OCaml/opam versions recorded in the patch and build logs. The `build/oss_build.sh` entry point still supports Linux only, so the macOS configure and dependency bootstrap are experimental and are not yet a clean-machine build recipe.

Porting findings:

- Modern ARM64 Mach-O requires the first 4 GiB to remain reserved. HHVM's old small page-zero linker option causes the loader to kill the program. Use the native Mach-O linker and preserve the platform's page-zero requirement.
- Darwin's shared region conflicts with Linux's managed arenas. A separate high metadata window and matching packed-pointer encoding are needed; an isolated probe preserved four-byte packed fields and passed 200,000 round trips across 12 launches.
- Function pointers and JIT addresses do not fit the Linux 32-bit code-address format. Preserve full pointers in code fields, branch literals, and matching generated loads; account for the resulting structure sizes.
- Use `MAP_JIT` for executable memory on Apple Silicon. A standalone probe passes nested per-thread write/execute transitions, moved and deferred code locks, and JIT code execution from a second thread; HHVM's JIT smoke program also passes. The full quick suite currently aborts at a JIT code-cache assertion when the runner is made sequential to work around its forked-queue crash.
- Replace Linux-specific APIs for exact memory reservations, timers, stack/context access, byte order, xattrs, random state, sockets, process control, and dynamic-library sections. The restored Darwin request CPU timer currently uses wall time, as the older port did.
- Keep OpenSSL 3 headers ahead of Homebrew's aggregate include path, which currently exposes OpenSSL 4. Use a producer-capable libdwarf and Homebrew SQLite with extension-loading APIs. Restore native TBB ARM detection and repair CMake dependency/byproduct ordering.
- Folly's fallback allocator function-pointer variables conflict with HHVM's jemalloc function imports on macOS. Build Folly and its dependent libraries with a consistent weak-function allocator interface; otherwise startup can jump into the data symbol named `mallctl`. Darwin's optional weak imports also need explicit linker permission to remain unresolved.
- Mach-O embeds sections at link time. Build a bootstrap compiler first, generate systemlib declarations/units with it, then link the final executable with those sections.
- macOS places regular allocations above the reserved low address range. Keep 32-bit persistent RDS handles by using the dynamic persistent base, record the allocated range size, and avoid the upstream absolute-address assertion.
- Use `_NSGetExecutablePath` so embedded systemlib sections can be read from the Mach-O executable. Align 64-bit far JIT literal targets before patching their ADRP/LDR pair.
- The tested executable was built with a 27.0 deployment target, but its dependency archives were built for 27.2. Only macOS 27.2 has been tested; compatibility with older macOS versions is unknown.

The continuous release workflow does not build this experimental macOS binary. If publishing a local build, attach the executable, its checksum, and the port patch manually as described in [release instructions](build-releases.md#experimental-native-macos-asset). The executable depends on Homebrew ICU 78, OpenSSL 3, SQLite, libevent, jemalloc, and other dylibs shown by `otool -L`; compatible libraries must exist at those paths. No notarized or dependency-bundled macOS archive is produced. Linux ARM64 Docker remains the supported option on Apple Silicon.

Sources: [upstream OSS support update](https://hhvm.com/blog/2023/10/27/oss-update.html), [Homebrew support deprecation](https://hhvm.com/blog/2022/06/17/deprecating-homebrew.html), [Apple JIT porting guidance](https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon), [Apple ARM64 ABI](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms), and [XNU Mach-O loader source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/mach_loader.c).
