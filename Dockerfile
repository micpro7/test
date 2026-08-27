# syntax=docker/dockerfile:1

FROM debian:trixie-slim

ARG HOMEASSISTANT_VERSION=stable

LABEL org.opencontainers.image.title="openwrt-uxc-homeassistant" \
      org.opencontainers.image.description="Home Assistant deployment for OpenWrt using native UXC containers" \
      org.opencontainers.image.source="https://github.com/micpro7/openwrt-uxc-homeassistant"

# ==========================================================
# System dependencies
# ==========================================================
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    tzdata \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    python3-wheel \
    build-essential \
    gcc \
    g++ \
    make \
    git \
    pkg-config \
    libffi-dev \
    libssl-dev \
    libjpeg-dev \
    zlib1g-dev \
    libopenjp2-7-dev \
    libtiff-dev \
    libxml2-dev \
    libxslt1-dev \
    libudev-dev \
    libdbus-1-dev \
    libavahi-client-dev \
    libavahi-compat-libdnssd-dev \
    avahi-utils \
    ffmpeg \
    dbus \
    sudo \
    bash \
 && rm -rf /var/lib/apt/lists/*

# ==========================================================
# UXC FIX
#
# Normal sudo expects setresuid/setresgid behaviour which
# UXC does not necessarily provide.
#
# Replace sudo with a lightweight direct-execution wrapper.
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
#
# Keep Home Assistant isolated from Debian system Python.
# ==========================================================
RUN python3 -m venv /opt/homeassistant \
 && /opt/homeassistant/bin/python -m pip install --upgrade \
      pip \
      setuptools \
      wheel

# ==========================================================
# Runtime environment
#
# Memory optimisation:
#
# PYTHONMALLOC=malloc
#   Uses the system malloc allocator instead of Python's
#   default small-object allocator.
#
# MALLOC_ARENA_MAX=2
#   Limits glibc malloc arenas and helps reduce retained
#   allocator memory on a low-RAM system.
# ==========================================================
ENV PATH=/opt/homeassistant/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin \
    VIRTUAL_ENV=/opt/homeassistant \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONMALLOC=malloc \
    MALLOC_ARENA_MAX=2

# ==========================================================
# Home Assistant
#
# "stable" / "latest" resolves to the current stable release.
# A specific version can be supplied through the workflow.
# ==========================================================
RUN set -eux; \
    if [ "${HOMEASSISTANT_VERSION}" = "stable" ] || [ "${HOMEASSISTANT_VERSION}" = "latest" ]; then \
        /opt/homeassistant/bin/pip install --no-cache-dir homeassistant; \
    else \
        /opt/homeassistant/bin/pip install --no-cache-dir "homeassistant==${HOMEASSISTANT_VERSION}"; \
    fi

# ==========================================================
# Persistent Home Assistant directory
#
# UXC mounts the host persistent directory over /config.
# ==========================================================
RUN mkdir -p \
    /config \
    /config/.storage \
    /config/tmp \
    /config/backup

# ==========================================================
# Home Assistant runtime entrypoint
#
# IMPORTANT:
# Do NOT use Tini here.
#
# Debian Trixie Tini was found to be incompatible with the
# OpenWrt UXC execution environment:
#
#   __isoc23_strtol: symbol not found
#   __fprintf_chk: symbol not found
#
# Home Assistant therefore runs directly as the main process.
# ==========================================================
RUN cat > /usr/local/bin/homeassistant-entrypoint.sh <<'EOF'
#!/bin/sh

set -u

# ==========================================================
# Runtime directory initialisation
# ==========================================================
mkdir -p \
    /config \
    /config/.storage \
    /config/tmp \
    /config/backup

echo "========================================================"
echo " Home Assistant UXC runtime"
echo "========================================================"

echo "Python:         $(/opt/homeassistant/bin/python --version 2>&1)"

echo "Home Assistant: $(/opt/homeassistant/bin/python -c 'from homeassistant.const import __version__; print(__version__)')"

echo "HA executable:  $(/opt/homeassistant/bin/hass --version 2>&1)"

echo "Python malloc:  ${PYTHONMALLOC:-default}"

echo "Malloc arenas:  ${MALLOC_ARENA_MAX:-default}"

echo "UID:            $(id -u)"
echo "GID:            $(id -g)"
echo "Workdir:        $(pwd)"
echo "Config:         /config"

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
# Tini intentionally NOT included.
# ==========================================================
RUN set -eux; \
    test -x /opt/homeassistant/bin/python; \
    test -x /opt/homeassistant/bin/python3; \
    test -x /opt/homeassistant/bin/pip; \
    test -x /opt/homeassistant/bin/hass; \
    test -x /usr/bin/python3; \
    test -x /usr/bin/bash; \
    test -x /usr/bin/ffmpeg; \
    test -x /usr/bin/sudo; \
    test -x /usr/local/bin/homeassistant-entrypoint.sh; \
    /opt/homeassistant/bin/python --version; \
    /opt/homeassistant/bin/python -c "from homeassistant.const import __version__; print('Home Assistant OK:', __version__)"; \
    /opt/homeassistant/bin/hass --version; \
    ffmpeg -version | head -n 1

# ==========================================================
# Final runtime environment
# ==========================================================
ENV HOME=/root \
    TZ=UTC \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONMALLOC=malloc \
    MALLOC_ARENA_MAX=2 \
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
# Docker runtime default
#
# UXC config.json uses this same entrypoint directly.
# ==========================================================
ENTRYPOINT ["/usr/local/bin/homeassistant-entrypoint.sh"]