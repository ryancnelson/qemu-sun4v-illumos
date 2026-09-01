ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS qemu-build

ARG DEBIAN_FRONTEND=noninteractive
ARG QEMU_COMMIT=049affb20df67162cf58deeaf74d5ad4b83cbdc3

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates git libglib2.0-dev libpixman-1-dev \
        meson ninja-build pkg-config python3 python3-venv zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY sources/qemu-${QEMU_COMMIT}.tar.gz /tmp/qemu-source.tar.gz
RUN mkdir -p /usr/src/qemu \
    && tar -xzf /tmp/qemu-source.tar.gz -C /usr/src/qemu \
    && rm /tmp/qemu-source.tar.gz

WORKDIR /usr/src/qemu/build
RUN ../configure \
        --target-list=sparc64-softmmu \
        --disable-docs \
        --disable-gtk \
        --disable-sdl \
        --disable-vnc \
        --disable-werror \
    && ninja qemu-system-sparc64

FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG QEMU_COMMIT=049affb20df67162cf58deeaf74d5ad4b83cbdc3

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libglib2.0-0 libpixman-1-0 python3 qemu-utils socat zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=qemu-build /usr/src/qemu/build/qemu-system-sparc64 /usr/local/bin/qemu-system-sparc64
COPY scripts/container-entrypoint.sh /usr/local/sbin/illumos-appliance-entrypoint

RUN chmod 0755 /usr/local/sbin/illumos-appliance-entrypoint \
    && /usr/local/bin/qemu-system-sparc64 --version \
    && /usr/local/bin/qemu-system-sparc64 -machine help | grep -q '^niagara'

LABEL org.opencontainers.image.title="SPARC64 QEMU OpenIndiana guest" \
      org.opencontainers.image.description="Pinned Niagara-capable QEMU runtime for the login-proven OpenIndiana guest" \
      org.opencontainers.image.source="ec2trib git archive of ryancnelson/qemu-sun4v-illumos" \
      org.opencontainers.image.revision="$QEMU_COMMIT"

ENTRYPOINT ["/usr/local/sbin/illumos-appliance-entrypoint"]
