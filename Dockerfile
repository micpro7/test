# syntax=docker/dockerfile:1

FROM debian:trixie-slim

ARG HOMEASSISTANT_VERSION=stable

LABEL org.opencontainers.image.title="openwrt-uxc-homeassistant" \
      org.opencontainers.image.description="Home Assistant deployment for OpenWrt using native UXC containers" \
      org.opencontainers.image.source="https://github.com/micpro7/openwrt-uxc-homeassistant"

# ==========================================================
# System dependencies
# ==========================================================
#
# Build dependencies are installed temporarily and removed
# after Home Assistant has been installed.
#
# Runtime dependencies are kept.
# ==========================================================
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        tzdata \
        python3 \
        python3-venv \
        python3-pip \
        ffmpeg \
        dbus \
        sudo \
        bash \
        iproute2 \
        libffi8 \
        libssl3 \
        libjpeg62-turbo \
        zlib1g \
        libopenjp2-7 \
        libtiff6 \
        libxml2 \
        libxslt1.1 \
        libudev1 \
        libdbus-1-3 \
        libavahi-client3 \
        libavahi-compat-libdnssd1 \
        avahi-utils; \
    apt-get install -y --no-install-recommends \
        python3-dev \
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
        libavahi-compat-libdnssd-dev; \
    rm -rf /var/lib/apt/lists/*

# ==========================================================
# IPv4 PREFERENCE
#
# Prefer IPv4 when both IPv4 and IPv6 addresses are available.
#
# This does NOT disable IPv6.
# ==========================================================
RUN sed -i \
    's/^#\?precedence ::ffff:0:0\/96 .*/precedence ::ffff:0:0\/96  100/' \
    /etc/gai.conf \
 && grep -q \
    '^precedence ::ffff:0:0/96  100' \
    /etc/gai.conf

# ==========================================================
# UXC FIX
#
# UXC does not necessarily provide the setresuid/setresgid
# behaviour expected by normal sudo.
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
# go2rtc
#
# Home Assistant's go2rtc integration expects a native
# executable named "go2rtc" to exist in PATH.
#
# Download the latest official Linux ARM64 binary.
# ==========================================================
RUN set -eux; \
    mkdir -p /usr/local/bin; \
    curl -fsSL \
        -o /usr/local/bin/go2rtc \
        https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_arm64; \
    chmod 0755 /usr/local/bin/go2rtc; \
    /usr/local/bin/go2rtc --version

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
# PYTHONMALLOC=malloc
#   Uses system malloc instead of Python's pymalloc.
#
# MALLOC_ARENA_MAX=2
#   Limits glibc malloc arenas.
#
# PYTHONOPTIMIZE=1
#   Enables basic Python bytecode optimisation.
#
# PYTHONASYNCIODEBUG=0
#   Explicitly keep asyncio debugging disabled.
# ==========================================================
ENV PATH=/opt/homeassistant/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin \
    VIRTUAL_ENV=/opt/homeassistant \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONMALLOC=malloc \
    MALLOC_ARENA_MAX=2 \
    PYTHONASYNCIODEBUG=0 \
    PYTHONOPTIMIZE=1 \
    PYTHONHASHSEED=random \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

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
# Remove build-only packages
#
# These are no longer required after Home Assistant has
# been installed into the virtual environment.
#
# This reduces image/rootfs size and background package
# footprint without removing the runtime libraries above.
# ==========================================================
RUN set -eux; \
    apt-get update; \
    apt-get purge -y \
        python3-dev \
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
        libavahi-compat-libdnssd-dev; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf \
        /var/lib/apt/lists/* \
        /var/cache/apt/* \
        /root/.cache \
        /tmp/*

# ==========================================================
# Remove Python caches
# ==========================================================
RUN find /opt/homeassistant \
        -type d \
        \( -name '__pycache__' -o -name '.pytest_cache' \) \
        -prune -exec rm -rf {} + \
 && find /opt/homeassistant \
        -type f \
        \( -name '*.pyc' -o -name '*.pyo' \) \
        -delete

# ==========================================================
# Persistent Home Assistant directory
# ==========================================================
RUN mkdir -p \
    /config \
    /config/.storage \
    /config/tmp \
    /config/backup

# ==========================================================
# Home Assistant runtime entrypoint
#
# UXC runs Home Assistant directly as PID 1.
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

echo "go2rtc:         $(/usr/local/bin/go2rtc --version 2>&1)"

echo "Python malloc:  ${PYTHONMALLOC:-default}"

echo "Malloc arenas:  ${MALLOC_ARENA_MAX:-default}"

echo "Python optimize:${PYTHONOPTIMIZE:-default}"

echo "IPv4 preference: enabled"

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
# ==========================================================
RUN set -eux; \
    test -x /opt/homeassistant/bin/python; \
    test -x /opt/homeassistant/bin/python3; \
    test -x /opt/homeassistant/bin/pip; \
    test -x /opt/homeassistant/bin/hass; \
    test -x /usr/bin/python3; \
    test -x /usr/bin/bash; \
    test -x /usr/bin/ffmpeg; \
    test -x /usr/bin/ip; \
    test -x /usr/bin/sudo; \
    test -x /usr/local/bin/go2rtc; \
    test -x /usr/local/bin/homeassistant-entrypoint.sh; \
    /opt/homeassistant/bin/python --version; \
    /opt/homeassistant/bin/python -c "from homeassistant.const import __version__; print('Home Assistant OK:', __version__)"; \
    /opt/homeassistant/bin/hass --version; \
    /usr/local/bin/go2rtc --version; \
    ffmpeg -version | head -n 1; \
    grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf

# ==========================================================
# Final runtime environment
# ==========================================================
ENV HOME=/root \
    TZ=Europe/London \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONMALLOC=malloc \
    MALLOC_ARENA_MAX=2 \
    PYTHONASYNCIODEBUG=0 \
    PYTHONOPTIMIZE=1 \
    PYTHONHASHSEED=random \
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
# UXC runtime entrypoint
# ==========================================================
ENTRYPOINT ["/usr/local/bin/homeassistant-entrypoint.sh"]