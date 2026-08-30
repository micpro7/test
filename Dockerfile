# syntax=docker/dockerfile:1

# ==========================================================
# Home Assistant UXC - ARM64
#
# Target:
#   1GB RAM Routers 
#   OpenWrt UXC
#   ARM64 / aarch64
#
# RAM optimisation is prioritised over image size.
# ==========================================================

# ==========================================================
# Official go2rtc binary source
#
# Home Assistant's own Dockerfile uses the go2rtc image and
# copies the binary to /bin/go2rtc.
# ==========================================================
FROM ghcr.io/alexxit/go2rtc:latest AS go2rtc

FROM debian:trixie-slim

ARG HOMEASSISTANT_VERSION=stable

LABEL org.opencontainers.image.title="openwrt-uxc-homeassistant" \
      org.opencontainers.image.description="Home Assistant deployment for OpenWrt using native UXC containers" \
      org.opencontainers.image.source="https://github.com/micpro7/openwrt-uxc-homeassistant"

# ==========================================================
# System dependencies
#
# RAM is more important than image size.
#
# Native compilation is intentionally supported because
# Home Assistant can install integration dependencies at
# runtime.
#
# Packages specifically required by errors observed:
#
#   netifaces
#   pymicro-vad
#   pyspeex-noise
#
# These require:
#
#   gcc
#   g++
#   Python development headers
#   libc development headers
#   make/build tooling
# ==========================================================

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    tzdata \
    \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    python3-wheel \
    \
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    \
    git \
    \
    libffi-dev \
    libssl-dev \
    zlib1g-dev \
    libjpeg-dev \
    libopenjp2-7-dev \
    libtiff-dev \
    libxml2-dev \
    libxslt1-dev \
    libudev-dev \
    libdbus-1-dev \
    libavahi-client-dev \
    libavahi-compat-libdnssd-dev \
    \
    avahi-utils \
    dbus \
    ffmpeg \
    \
    iproute2 \
    iputils-ping \
    \
    sudo \
    bash \
 && rm -rf /var/lib/apt/lists/*

# ==========================================================
# ARM64 compiler compatibility
#
# HA's uv build environment may invoke:
#
#   aarch64-linux-gnu-gcc
#   aarch64-linux-gnu-g++
#
# This container is already ARM64, so these simply point to
# the native compilers.
# ==========================================================

RUN ln -sf /usr/bin/gcc /usr/local/bin/aarch64-linux-gnu-gcc \
 && ln -sf /usr/bin/g++ /usr/local/bin/aarch64-linux-gnu-g++ \
 && command -v gcc \
 && command -v g++ \
 && command -v aarch64-linux-gnu-gcc \
 && command -v aarch64-linux-gnu-g++

# ==========================================================
# IPv4 preference
#
# Prefer IPv4 when both IPv4 and IPv6 addresses exist.
#
# IPv6 remains enabled.
# ==========================================================

RUN sed -i \
    's/^#\?precedence ::ffff:0:0\/96 .*/precedence ::ffff:0:0\/96  100/' \
    /etc/gai.conf \
 && grep -q \
    '^precedence ::ffff:0:0/96  100' \
    /etc/gai.conf

# ==========================================================
# UXC sudo compatibility
#
# Normal sudo can require setresuid/setresgid behaviour
# which is restricted by UXC.
#
# Keep sudo available while avoiding those syscalls.
# ==========================================================

RUN rm -f /usr/bin/sudo \
 && cat > /usr/bin/sudo <<'EOF'
#!/bin/sh

while [ $# -gt 0 ]; do
    case "$1" in
        -n|-E|-H|-S|-k|-K|-b|-v)
            shift
            ;;
        -u|-g|-C)
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "sudo: no command specified" >&2
    exit 1
fi

exec "$@"
EOF

RUN chmod 0755 /usr/bin/sudo

# ==========================================================
# Python virtual environment
# ==========================================================

RUN python3 -m venv /opt/homeassistant \
 && /opt/homeassistant/bin/python -m pip install --upgrade \
      pip \
      setuptools \
      wheel

# ==========================================================
# Runtime environment
#
# RAM optimisation
# ==========================================================
#
# PYTHONMALLOC=malloc
#   Uses glibc malloc instead of Python pymalloc.
#
# MALLOC_ARENA_MAX=1
#   Aggressively limits glibc malloc arenas.
#
# PYTHONDONTWRITEBYTECODE=1
#   Prevents .pyc generation.
#
# PYTHONASYNCIODEBUG=0
#   Ensures asyncio debug mode remains disabled.
#
# UV_NO_CACHE=1
#   Prevents uv package cache retention.
#
# PIP_NO_CACHE_DIR=1
#   Prevents pip cache retention.
#
# PYTHONUNBUFFERED=1
#   Normal HA logging behaviour.
# ==========================================================

ENV PATH=/opt/homeassistant/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin \
    VIRTUAL_ENV=/opt/homeassistant \
    HOME=/root \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONMALLOC=malloc \
    MALLOC_ARENA_MAX=1 \
    PYTHONASYNCIODEBUG=0 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    UV_NO_CACHE=1 \
    UV_SYSTEM_PYTHON=false \
    TZ=Europe/London

# ==========================================================
# Compression acceleration
#
# Prevents:
#
#   zlib_ng and isal are not available, falling back to zlib
#
# These are runtime Python modules and can improve compressed
# HTTP handling without requiring the system zlib package
# to be replaced.
# ==========================================================

RUN /opt/homeassistant/bin/pip install \
      --no-cache-dir \
      zlib-ng \
      isal

# ==========================================================
# Home Assistant
# ==========================================================

RUN set -eux; \
    if [ "${HOMEASSISTANT_VERSION}" = "stable" ] || [ "${HOMEASSISTANT_VERSION}" = "latest" ]; then \
        /opt/homeassistant/bin/pip install \
            --no-cache-dir \
            homeassistant; \
    else \
        /opt/homeassistant/bin/pip install \
            --no-cache-dir \
            "homeassistant==${HOMEASSISTANT_VERSION}"; \
    fi

# ==========================================================
# go2rtc
#
# Home Assistant expects the go2rtc executable to exist in
# the container PATH.
#
# Official HA container layout:
#
#   /bin/go2rtc
#
# Do NOT install OpenWrt's host go2rtc package for this.
# The HA-managed go2rtc instance should live inside the same
# UXC namespace/container.
# ==========================================================

COPY --from=go2rtc /usr/local/bin/go2rtc /bin/go2rtc

RUN chmod 0755 /bin/go2rtc \
 && /bin/go2rtc --version

# ==========================================================
# Persistent Home Assistant directories
# ==========================================================

RUN mkdir -p \
    /config \
    /config/.storage \
    /config/tmp \
    /config/backup

# ==========================================================
# Home Assistant runtime entrypoint
# ==========================================================

RUN cat > /usr/local/bin/homeassistant-entrypoint.sh <<'EOF'
#!/bin/sh

set -u

# ==========================================================
# Runtime directories
# ==========================================================

mkdir -p \
    /config \
    /config/.storage \
    /config/tmp \
    /config/backup

echo "========================================================"
echo " Home Assistant UXC runtime"
echo "========================================================"

echo "Architecture:    $(uname -m)"

echo "Kernel:          $(uname -r)"

echo "Python:          $(/opt/homeassistant/bin/python --version 2>&1)"

echo "Home Assistant:  $(/opt/homeassistant/bin/python -c 'from homeassistant.const import __version__; print(__version__)')"

echo "HA executable:   $(/opt/homeassistant/bin/hass --version 2>&1)"

echo "go2rtc:          $(/bin/go2rtc --version 2>&1)"

echo "Python malloc:   ${PYTHONMALLOC:-default}"

echo "Malloc arenas:   ${MALLOC_ARENA_MAX:-default}"

echo "UV cache:        disabled"

echo "IPv4 preference: enabled"

echo "UID:             $(id -u)"

echo "GID:             $(id -g)"

echo "Config:          /config"

echo "========================================================"

# ==========================================================
# Start Home Assistant
# ==========================================================

exec /opt/homeassistant/bin/hass \
    --config /config
EOF

RUN chmod 0755 /usr/local/bin/homeassistant-entrypoint.sh

# ==========================================================
# Build validation
#
# IMPORTANT:
# Do NOT test:
#
#   import go2rtc_client
#
# here.
#
# Home Assistant itself declares go2rtc-client as an
# integration requirement. The binary requirement is the
# important part for this container.
# ==========================================================

RUN set -eux; \
    test -x /opt/homeassistant/bin/python; \
    test -x /opt/homeassistant/bin/python3; \
    test -x /opt/homeassistant/bin/pip; \
    test -x /opt/homeassistant/bin/hass; \
    test -x /usr/bin/python3; \
    test -x /usr/bin/gcc; \
    test -x /usr/bin/g++; \
    test -x /usr/local/bin/aarch64-linux-gnu-gcc; \
    test -x /usr/local/bin/aarch64-linux-gnu-g++; \
    test -x /usr/bin/bash; \
    test -x /usr/bin/ffmpeg; \
    test -x /usr/bin/ip; \
    test -x /usr/bin/ping; \
    test -x /usr/bin/sudo; \
    test -x /usr/local/bin/homeassistant-entrypoint.sh; \
    test -x /bin/go2rtc; \
    \
    /opt/homeassistant/bin/python --version; \
    \
    /opt/homeassistant/bin/python -c \
        "from homeassistant.const import __version__; print('Home Assistant OK:', __version__)"; \
    \
    /opt/homeassistant/bin/python -c \
        "import zlib_ng; print('zlib-ng OK')"; \
    \
    /opt/homeassistant/bin/python -c \
        "import isal; print('isal OK')"; \
    \
    /opt/homeassistant/bin/python -c \
        "import aiohttp_fast_zlib; print('aiohttp-fast-zlib OK')"; \
    \
    /opt/homeassistant/bin/python -c \
        "import importlib.metadata as m; print('go2rtc-client:', m.version('go2rtc-client'))"; \
    \
    /opt/homeassistant/bin/hass --version; \
    \
    /bin/go2rtc --version; \
    \
    ffmpeg -version | head -n 1; \
    \
    gcc --version | head -n 1; \
    \
    g++ --version | head -n 1; \
    \
    grep -q \
        '^precedence ::ffff:0:0/96  100' \
        /etc/gai.conf

# ==========================================================
# Final runtime environment
# ==========================================================

ENV HOME=/root \
    TZ=Europe/London \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONMALLOC=malloc \
    MALLOC_ARENA_MAX=1 \
    PYTHONASYNCIODEBUG=0 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    UV_NO_CACHE=1 \
    TMPDIR=/config/tmp \
    TEMP=/config/tmp \
    TMP=/config/tmp \
    DBUS_SYSTEM_BUS_ADDRESS=unix:path=/var/run/dbus/system_bus_socket

# ==========================================================
# Working directory
# ==========================================================

WORKDIR /config

# ==========================================================
# Home Assistant Web UI
# ==========================================================

EXPOSE 8123

# ==========================================================
# UXC runtime
# ==========================================================

ENTRYPOINT ["/usr/local/bin/homeassistant-entrypoint.sh"]
