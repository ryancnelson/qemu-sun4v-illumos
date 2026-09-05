ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS qemu-build

ARG DEBIAN_FRONTEND=noninteractive
ARG QEMU_COMMIT=049affb20df67162cf58deeaf74d5ad4b83cbdc3
ARG QEMU_BUILD_JOBS=2
ARG QEMU_SOURCE_SHA256=4990dafc5ca24bb73837d5d5652aa8bf16bd6df5e9db54b873cfcc59d0fa9c95
ARG QEMU_CONTRACT_ID=sparc-tlb-range-flush-v1

RUN apt-get update && apt-get install -y --no-install-recommends \
        binutils build-essential ca-certificates git libglib2.0-dev libpixman-1-dev \
        meson ninja-build pkg-config python3 python3-venv zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY sources/qemu-${QEMU_COMMIT}.tar.gz /tmp/qemu-source.tar.gz
COPY qemu-patches /tmp/qemu-patches
COPY scripts/verify-qemu-contract.py /tmp/verify-qemu-contract.py
COPY qemu-contract.env /tmp/qemu-contract.env
RUN mkdir -p /usr/src/qemu \
    && test "$(sha256sum /tmp/qemu-source.tar.gz | cut -d ' ' -f 1)" = "$QEMU_SOURCE_SHA256" \
    && tar -xzf /tmp/qemu-source.tar.gz -C /usr/src/qemu \
    && rm /tmp/qemu-source.tar.gz \
    && cd /tmp/qemu-patches \
    && sha256sum -c SHA256SUMS \
    && cd /usr/src/qemu \
    && git apply \
        /tmp/qemu-patches/0004-niagara-smp-strand-id.patch \
        /tmp/qemu-patches/0005-niagara-smp-interrupt-state-dump.patch \
        /tmp/qemu-patches/0006-niagara-defer-guest-mondo-in-hypervisor.patch \
    && python3 /tmp/verify-qemu-contract.py \
        --source /usr/src/qemu/target/sparc/ldst_helper.c \
    && rm -rf /tmp/qemu-patches

WORKDIR /usr/src/qemu/build
RUN ../configure \
        --target-list=sparc64-softmmu \
        --disable-docs \
        --disable-gtk \
        --disable-sdl \
        --disable-vnc \
        --disable-werror \
    && ninja -j ${QEMU_BUILD_JOBS} qemu-system-sparc64 \
    && python3 /tmp/verify-qemu-contract.py \
        --qemu qemu-system-sparc64

FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG QEMU_COMMIT=049affb20df67162cf58deeaf74d5ad4b83cbdc3
ARG QEMU_CONTRACT_ID=sparc-tlb-range-flush-v1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libglib2.0-0 libpixman-1-0 python3 qemu-utils socat zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=qemu-build /usr/src/qemu/build/qemu-system-sparc64 /usr/local/bin/qemu-system-sparc64
COPY scripts/container-entrypoint.sh /usr/local/sbin/illumos-appliance-entrypoint
COPY qemu-contract.env /usr/local/share/niagara-qemu-contract.env

RUN chmod 0755 /usr/local/sbin/illumos-appliance-entrypoint \
    && /usr/local/bin/qemu-system-sparc64 --version \
    && /usr/local/bin/qemu-system-sparc64 -machine help | grep -q '^niagara'

LABEL org.opencontainers.image.title="SPARC64 QEMU OpenIndiana guest" \
      org.opencontainers.image.description="Pinned Niagara-capable QEMU runtime for the login-proven OpenIndiana guest" \
      org.opencontainers.image.source="ec2trib git archive of ryancnelson/qemu-sun4v-illumos" \
      org.opencontainers.image.revision="$QEMU_COMMIT" \
      io.niagara.qemu.contract="$QEMU_CONTRACT_ID" \
      io.niagara.qemu.patchset="source-tlb-range-flush,0004-strand-id,0005-interrupt-dump,0006-mondo-deferral"

ENTRYPOINT ["/usr/local/sbin/illumos-appliance-entrypoint"]
