# syntax=docker/dockerfile:1

# ==========================================================
# Home Assistant UXC - ARM64
#
# Target:
#   Linksys MX5300
#   OpenWrt UXC
#   ARM64 / aarch64
#
# RAM optimisation is prioritised over image size.
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
# Keep build tools intentionally.
#
# Home Assistant installs some integration dependencies
# dynamically at runtime and several require native ARM64
# compilation.
#
# Examples from your logs:
#   netifaces
#   pymicro-vad
#   pyspeex-noise
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
# HA/uv can invoke these names while compiling native
# Python modules:
#
#   aarch64-linux-gnu-gcc
#   aarch64-linux-gnu-g++
#
# We are compiling natively on ARM64, so aliases to the
# native compiler are sufficient.
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
# Prefer IPv4 when both IPv4 and IPv6 addresses are
# available.
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
# UXC does not necessarily permit the setresuid/setresgid
# behaviour expected by normal sudo.
#
# Keep sudo functionality but avoid those syscalls.
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
# Runtime environment - RAM optimisation
#
# PYTHONMALLOC=malloc
#   Uses glibc malloc rather than Python pymalloc.
#
# MALLOC_ARENA_MAX=1
#   Minimise glibc arena duplication.
#
# This is deliberately 1 rather than 2 because RAM is the
# primary constraint on this router.
#
# PYTHONASYNCIODEBUG=0
#   Never run asyncio debug mode.
#
# PYTHONDONTWRITEBYTECODE
#   Avoid .pyc generation.
#
# UV_NO_CACHE
#   Prevent uv from maintaining package caches.
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
# Optional compression acceleration
#
# aiohttp_fast_zlib reported:
#
#   zlib_ng and isal are not available
#
# Install both into the HA virtual environment.
#
# These can reduce CPU work for HTTP compression and avoid
# the fallback warning.
# ==========================================================

RUN /opt/homeassistant/bin/pip install \
      --no-cache-dir \
      zlib-ng \
      isal

# ==========================================================
# Home Assistant
#
# stable/latest:
#   Install current stable release.
#
# Specific version:
#   HOMEASSISTANT_VERSION=x.y.z
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
# Home Assistant's official container layout places the
# go2rtc binary at /bin/go2rtc.
#
# This fixes:
#
#   Could not find go2rtc docker binary
#
# The source image is multi-architecture and provides ARM64.
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
# Runtime entrypoint
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
        "import go2rtc_client; print('go2rtc-client OK')"; \
    \
    /opt/homeassistant/bin/hass --version; \
    \
    /bin/go2rtc --version; \
    \
    ffmpeg -version | head -n 1; \
    \
    grep -q \
        '^precedence ::ffff:0:0/96  100' \
        /etc/gai.conf

# ==========================================================
# Final runtime environment
#
# Repeated here so the final image configuration is explicit.
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