# syntax=docker/dockerfile:1
FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c AS build
ARG TARGETARCH
ARG BUILD_JOBS=4
ARG EMULATED=0
ARG VCS_REF=unknown
ENV DEBIAN_FRONTEND=noninteractive \
    HHVM_OSS_WORK_ROOT=/var/lib/hhvm-oss \
    HHVM_OSS_C_COMPILER=clang-21 \
    HHVM_OSS_CXX_COMPILER=clang++-21 \
    HHVM_OSS_CMAKE_BUILD_TYPE=Release \
    HHVM_OSS_BUILD_JOBS=${BUILD_JOBS} \
    CARGO_BUILD_JOBS=${BUILD_JOBS} OPAMJOBS=${BUILD_JOBS} \
    CARGO_HOME=/var/lib/hhvm-oss/cargo
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates clang-21 lld-21 curl git libarchive-tools patchelf \
    && ln -s /usr/bin/bsdtar /usr/local/bin/tar \
    && update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-21 1000 \
    && rm -rf /var/lib/apt/lists/*
COPY . /src
WORKDIR /src
# Retain compiled dependencies between commits, separately for each architecture.
RUN --mount=type=cache,id=hhvm-release-${TARGETARCH},target=/var/lib/hhvm-oss,sharing=locked \
    set -eu; \
    if [ "$EMULATED" = 1 ]; then export EVENT_NOEPOLL=1; fi; \
    ./build/oss_build.sh; \
    export HHVM_BIN=/var/lib/hhvm-oss/hhvm/hphp/hhvm/hhvm; \
    "$HHVM_BIN" --version; \
    "$HHVM_BIN" -vEval.Jit=false build/release/smoke.hack; \
    "$HHVM_BIN" -vEval.Jit=true build/release/smoke.hack; \
    mkdir -p /distribution; \
    chmod -R a+rX /src /var/lib/hhvm-oss; \
    runuser -u nobody -- env HHVM_BIN="$HHVM_BIN" \
      ./hphp/test/run quick --threads "$BUILD_JOBS" > /distribution/quick-tests.log 2>&1 \
      || { cat /distribution/quick-tests.log; exit 1; }; \
    python3 build/release/package_runtime.py \
      --work-root /var/lib/hhvm-oss --source /src \
      --output /distribution/runtime --commit "$VCS_REF"

FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c AS runtime
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="HHVM Hack runtime" \
      org.opencontainers.image.description="Community HHVM builds for Linux x86-64 and ARM64" \
      org.opencontainers.image.source="https://github.com/justdan6/hhvm" \
      org.opencontainers.image.revision="${VCS_REF}"
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /distribution/runtime /opt/hhvm
COPY --from=build /distribution/quick-tests.log /opt/hhvm/quick-tests.log
# The launcher initializes its private copy on first launch. Keeping it out of
# the image avoids shipping a second executable in every layer/archive.
RUN chown 65534:65534 /opt/hhvm
USER 65534:65534
WORKDIR /tmp
ENTRYPOINT ["/opt/hhvm/hhvm-run"]
CMD ["--version"]
