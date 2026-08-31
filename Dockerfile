# syntax=docker/dockerfile:1

# ==========================================================
# Home Assistant UXC - ARM64
#
# Target:
# 1GB RAM Routers
# OpenWrt UXC
# ARM64 / aarch64
#
# Priority:
# RAM optimisation > image size
#
# This image intentionally retains build tools and libraries
# because Home Assistant integrations can install/compile
# native Python components.
# ==========================================================

# ==========================================================
# go2rtc stage
#
# go2rtc is kept INSIDE the Home Assistant UXC container.
#
# The OpenWrt host does not need its own go2rtc instance for
# Home Assistant.
# ==========================================================
FROM ghcr.io/alexxit/go2rtc:latest AS go2rtc

# ==========================================================
# Home Assistant base
# ==========================================================
FROM debian:trixie-slim

ARG HOMEASSISTANT_VERSION=stable

LABEL org.opencontainers.image.title="openwrt-uxc-homeassistant" \
      org.opencontainers.image.description="Home Assistant deployment for OpenWrt using native UXC containers" \
      org.opencontainers.image.source="https://github.com/micpro7/openwrt-uxc-homeassistant"

# ==========================================================
# System packages
#
# RAM optimisation is prioritised over image size.
#
# Keep the compiler/toolchain because Home Assistant and
# integrations can require native ARM64 Python extensions.
#
# Important runtime libraries:
#
# libturbojpeg0
#   Native TurboJPEG runtime used by Home Assistant camera
#   snapshot processing.
#
# libpcap0.8
#   Native packet-capture library required by aiodhcpwatcher
#   for DHCP packet monitoring.
#
# libcap2-bin
#   Linux capability inspection/support.
#
# PyTurboJPEG is installed separately into the Home Assistant
# virtual environment below.
# ==========================================================
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    # Certificates / downloads / time
    ca-certificates \
    curl \
    wget \
    tzdata \
    # Python runtime / build support
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    python3-wheel \
    # Native compilation
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    # Source/build tooling
    git \
    # Python/native libraries
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
    # ======================================================
    # JPEG / camera support
    # ======================================================
    libturbojpeg0 \
    libturbojpeg0-dev \
    # ======================================================
    # Packet capture / DHCP watcher
    # ======================================================
    libpcap0.8 \
    libpcap-dev \
    # ======================================================
    # Linux capabilities
    # ======================================================
    libcap2-bin \
    # ======================================================
    # Avahi / mDNS / HomeKit / discovery
    # ======================================================
    libavahi-client-dev \
    libavahi-compat-libdnssd-dev \
    avahi-utils \
    # DBus
    dbus \
    # Audio / video
    ffmpeg \
    # Networking
    iproute2 \
    iputils-ping \
    # Shell / privilege compatibility
    sudo \
    bash \
    && rm -rf /var/lib/apt/lists/*

# ==========================================================
# ARM64 compiler compatibility
# ==========================================================
RUN ln -sf /usr/bin/gcc /usr/local/bin/aarch64-linux-gnu-gcc \
    && ln -sf /usr/bin/g++ /usr/local/bin/aarch64-linux-gnu-g++ \
    && command -v gcc \
    && command -v g++ \
    && command -v aarch64-linux-gnu-gcc \
    && command -v aarch64-linux-gnu-g++

# ==========================================================
# IPv4 preference
# ==========================================================
RUN if grep -q '^#?precedence ::ffff:0:0/96' /etc/gai.conf; then \
        sed -i 's/^#?precedence ::ffff:0:0/96 .*/precedence ::ffff:0:0/96  100/' /etc/gai.conf; \
    else \
        printf '\nprecedence ::ffff:0:0/96  100\n' >> /etc/gai.conf; \
    fi \
    && grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf

# ==========================================================
# UXC sudo compatibility
#
# UXC blocks the setresuid syscall used by the normal sudo
# binary. Replace it with a lightweight command passthrough.
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
# Runtime environment variables
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
        /opt/homeassistant/bin/pip install --no-cache-dir homeassistant; \
    else \
        /opt/homeassistant/bin/pip install --no-cache-dir "homeassistant==${HOMEASSISTANT_VERSION}"; \
    fi

# ==========================================================
# Home Assistant go2rtc Python client
# ==========================================================
RUN /opt/homeassistant/bin/pip install \
    --no-cache-dir \
    "go2rtc-client==0.4.0"

# ==========================================================
# Camera JPEG acceleration
#
# PyTurboJPEG provides the Python binding.
# libturbojpeg0 provides the native TurboJPEG library.
# ==========================================================
RUN /opt/homeassistant/bin/pip install \
    --no-cache-dir \
    PyTurboJPEG

# ==========================================================
# go2rtc ARM64 executable
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
# Home Assistant entrypoint
# ==========================================================
RUN cat > /usr/local/bin/homeassistant-entrypoint.sh <<'EOF'
#!/bin/sh

set -u

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
echo "TurboJPEG:       $(ldconfig -p 2>/dev/null | grep -m1 'libturbojpeg' || echo 'not found')"
echo "libpcap:         $(ldconfig -p 2>/dev/null | grep -m1 'libpcap.so' || echo 'not found')"
echo "Python malloc:   ${PYTHONMALLOC:-default}"
echo "Malloc arenas:   ${MALLOC_ARENA_MAX:-default}"
echo "UV cache:        disabled"
echo "IPv4 preference: enabled"
echo "UID:             $(id -u)"
echo "GID:             $(id -g)"
echo "Config:          /config"
echo "========================================================"

exec /opt/homeassistant/bin/hass \
    --config /config
EOF

RUN chmod 0755 /usr/local/bin/homeassistant-entrypoint.sh

# ==========================================================
# Build validation
#
# Validate the native libraries and Python bindings during
# the image build.
#
# This prevents missing runtime dependencies from reaching
# the UXC container.
# ==========================================================
RUN set -eux; \
    # ------------------------------------------------------
    # Basic executables
    # ------------------------------------------------------
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
    # ------------------------------------------------------
    # Native libraries
    # ------------------------------------------------------
    ldconfig -p | grep -q 'libturbojpeg.so'; \
    ldconfig -p | grep -q 'libpcap.so'; \
    ldconfig -p | grep -q 'libjpeg.so'; \
    ldconfig -p | grep -q 'libavahi-client.so'; \
    ldconfig -p | grep -q 'libdbus-1.so'; \
    # ------------------------------------------------------
    # Python
    # ------------------------------------------------------
    /opt/homeassistant/bin/python --version; \
    /opt/homeassistant/bin/python -c "from homeassistant.const import __version__; print('Home Assistant OK:', __version__)"; \
    /opt/homeassistant/bin/python -c "import zlib_ng; print('zlib-ng OK')"; \
    /opt/homeassistant/bin/python -c "import isal; print('isal OK')"; \
    /opt/homeassistant/bin/python -c "import aiohttp_fast_zlib; print('aiohttp-fast-zlib OK')"; \
    /opt/homeassistant/bin/python -c "import go2rtc_client; print('go2rtc-client import OK')"; \
    /opt/homeassistant/bin/python -c "import importlib.metadata as m; print('go2rtc-client version:', m.version('go2rtc-client'))"; \
    # ------------------------------------------------------
    # PyTurboJPEG + native TurboJPEG
    # ------------------------------------------------------
    /opt/homeassistant/bin/python -c "import turbojpeg; print('PyTurboJPEG OK:', turbojpeg.__version__ if hasattr(turbojpeg, '__version__') else 'installed')"; \
    /opt/homeassistant/bin/python -c "from turbojpeg import TurboJPEG; jpeg=TurboJPEG(); print('TurboJPEG native library OK')"; \
    # ------------------------------------------------------
    # libpcap
    # ------------------------------------------------------
    /opt/homeassistant/bin/python -c "import ctypes; ctypes.CDLL('libpcap.so.0.8'); print('libpcap OK')"; \
    # ------------------------------------------------------
    # Home Assistant / media
    # ------------------------------------------------------
    /opt/homeassistant/bin/hass --version; \
    /bin/go2rtc --version; \
    ffmpeg -version | head -n 1; \
    gcc --version | head -n 1; \
    g++ --version | head -n 1; \
    # ------------------------------------------------------
    # Network capability tools
    # ------------------------------------------------------
    command -v capsh; \
    capsh --print >/dev/null 2>&1 || true; \
    # ------------------------------------------------------
    # IPv4 preference
    # ------------------------------------------------------
    grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf

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
# Working directory & Expose
# ==========================================================
WORKDIR /config

EXPOSE 8123

# ==========================================================
# UXC runtime entrypoint
# ==========================================================
ENTRYPOINT ["/usr/local/bin/homeassistant-entrypoint.sh"]
