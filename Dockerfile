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

LABEL org.opencontainers.image.title="openwrt-uxc-homeassistant" 
org.opencontainers.image.description="Home Assistant deployment for OpenWrt using native UXC containers" 
org.opencontainers.image.source="https://github.com/micpro7/openwrt-uxc-homeassistant"

# ==========================================================

# System packages

#

# RAM optimisation is prioritised over image size.

#

# Keep the compiler/toolchain because Home Assistant and

# integrations can require native ARM64 Python extensions.

#

# Packages retained for:

#

# Python native modules

# audio/video

# network discovery

# DBus

# Avahi

# USB/device access

# ffmpeg

# Home Assistant integrations

# ==========================================================

RUN apt-get update 
&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends 

# ------------------------------------------------------
# Certificates / downloads / time
# ------------------------------------------------------
ca-certificates 
curl 
wget 
tzdata 

# ------------------------------------------------------
# Python runtime / build support
# ------------------------------------------------------
python3 
python3-dev 
python3-pip 
python3-venv 
python3-setuptools 
python3-wheel 

# ------------------------------------------------------
# Native compilation
# ------------------------------------------------------
build-essential 
gcc 
g++ 
make 
pkg-config 

# ------------------------------------------------------
# Source/build tooling
# ------------------------------------------------------
git 

# ------------------------------------------------------
# Python/native libraries
# ------------------------------------------------------
libffi-dev 
libssl-dev 
zlib1g-dev 
libjpeg-dev 
libopenjp2-7-dev 
libtiff-dev 
libxml2-dev 
libxslt1-dev 
libudev-dev 
libdbus-1-dev 

# ------------------------------------------------------
# Avahi / mDNS / HomeKit / discovery
# ------------------------------------------------------
libavahi-client-dev 
libavahi-compat-libdnssd-dev 
avahi-utils 

# ------------------------------------------------------
# DBus
# ------------------------------------------------------
dbus 

# ------------------------------------------------------
# Audio / video
# ------------------------------------------------------
ffmpeg 

# ------------------------------------------------------
# Networking
# ------------------------------------------------------
iproute2 
iputils-ping 

# ------------------------------------------------------
# Shell / privilege compatibility
# ------------------------------------------------------
sudo 
bash 
&& rm -rf /var/lib/apt/lists/*

# ==========================================================

# ARM64 compiler compatibility

#

# Some Home Assistant build tooling can look for:

#

# aarch64-linux-gnu-gcc

# aarch64-linux-gnu-g++

#

# We are already compiling natively for ARM64, so aliases

# to the native compiler are sufficient.

# ==========================================================

RUN ln -sf /usr/bin/gcc /usr/local/bin/aarch64-linux-gnu-gcc 
&& ln -sf /usr/bin/g++ /usr/local/bin/aarch64-linux-gnu-g++ 
&& command -v gcc 
&& command -v g++ 
&& command -v aarch64-linux-gnu-gcc 
&& command -v aarch64-linux-gnu-g++

# ==========================================================

# IPv4 preference

#

# Prefer IPv4 when both IPv4 and IPv6 addresses are

# available.

#

# IPv6 remains enabled.

# ==========================================================

RUN if grep -q '^#?precedence ::ffff:0:0/96' /etc/gai.conf; then 
sed -i 
's/^#?precedence ::ffff:0:0/96 .*/precedence ::ffff:0:0/96  100/' 
/etc/gai.conf; 
else 
printf '\nprecedence ::ffff:0:0/96  100\n' >> /etc/gai.conf; 
fi 
&& grep -q 
'^precedence ::ffff:0:0/96  100' 
/etc/gai.conf

# ==========================================================

# UXC sudo compatibility

#

# UXC may not permit the setresuid/setresgid behaviour

# expected by normal sudo.

#

# Retain the sudo command/functionality but avoid the

# privileged UID/GID transitions.

# ==========================================================

RUN rm -f /usr/bin/sudo 
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

# Home Assistant gets its own isolated Python environment.

# ==========================================================

RUN python3 -m venv /opt/homeassistant 
&& /opt/homeassistant/bin/python -m pip install --upgrade 
pip 
setuptools 
wheel

# ==========================================================

# Runtime environment

#

# RAM optimisation

# ==========================================================

#

# PYTHONMALLOC=malloc

# Use glibc malloc rather than Python pymalloc.

#

# MALLOC_ARENA_MAX=1

# Aggressively restrict glibc malloc arenas.

#

# PYTHONASYNCIODEBUG=0

# Never enable asyncio debug mode.

#

# PYTHONDONTWRITEBYTECODE

# Prevent runtime .pyc creation.

#

# PIP_NO_CACHE_DIR

# No pip package cache.

#

# UV_NO_CACHE

# No uv cache.

# ==========================================================

ENV PATH=/opt/homeassistant/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin 
VIRTUAL_ENV=/opt/homeassistant 
HOME=/root 
PYTHONUNBUFFERED=1 
PYTHONDONTWRITEBYTECODE=1 
PYTHONMALLOC=malloc 
MALLOC_ARENA_MAX=1 
PYTHONASYNCIODEBUG=0 
PIP_DISABLE_PIP_VERSION_CHECK=1 
PIP_NO_CACHE_DIR=1 
UV_NO_CACHE=1 
UV_SYSTEM_PYTHON=false 
TZ=Europe/London

# ==========================================================

# Compression acceleration

#

# Home Assistant's aiohttp stack can use these libraries.

#

# zlib-ng

# isal

#

# These are particularly useful on a relatively constrained

# ARM64 router because they reduce compression/decompression

# CPU overhead.

# ==========================================================

RUN /opt/homeassistant/bin/pip install 
--no-cache-dir 
zlib-ng 
isal

# ==========================================================

# Home Assistant

#

# stable/latest:

# Install current package selected by PyPI.

#

# Specific version:

# HOMEASSISTANT_VERSION=x.y.z

# ==========================================================

RUN set -eux; 
if [ "${HOMEASSISTANT_VERSION}" = "stable" ] || [ "${HOMEASSISTANT_VERSION}" = "latest" ]; then 
/opt/homeassistant/bin/pip install 
--no-cache-dir 
homeassistant; 
else 
/opt/homeassistant/bin/pip install 
--no-cache-dir 
"homeassistant==${HOMEASSISTANT_VERSION}"; 
fi

# ==========================================================

# Home Assistant go2rtc Python client

#

# IMPORTANT:

#

# The go2rtc executable and the Python client are separate.

#

# Executable:

# /bin/go2rtc

#

# Python module:

# go2rtc_client

#

# Home Assistant's go2rtc integration needs the Python

# client package as well as the go2rtc executable.

# ==========================================================

RUN /opt/homeassistant/bin/pip install 
--no-cache-dir 
"go2rtc-client==0.4.0"

# ==========================================================

# go2rtc ARM64 executable

#

# The official go2rtc image provides the ARM64 binary.

#

# This gives Home Assistant:

#

# /bin/go2rtc

#

# without requiring go2rtc to be installed separately on

# the OpenWrt host.

# ==========================================================

COPY --from=go2rtc /usr/local/bin/go2rtc /bin/go2rtc

RUN chmod 0755 /bin/go2rtc 
&& /bin/go2rtc --version

# ==========================================================

# Persistent Home Assistant directories

# ==========================================================

RUN mkdir -p 
/config 
/config/.storage 
/config/tmp 
/config/backup

# ==========================================================

# Home Assistant entrypoint

# ==========================================================

RUN cat > /usr/local/bin/homeassistant-entrypoint.sh <<'EOF'
#!/bin/sh

set -u

# ==========================================================

# Runtime directories

# ==========================================================

mkdir -p 
/config 
/config/.storage 
/config/tmp 
/config/backup

# ==========================================================

# Runtime information

# ==========================================================

echo "========================================================"
echo " Home Assistant UXC runtime"
echo "========================================================"

echo "Architecture:    $(uname -m)"

echo "Kernel:          $(uname -r)"

echo "Python:          $(/opt/homeassistant/bin/python --version 2>&1)"

echo "Home Assistant:  $(/opt/homeassistant/bin/python -c 'from homeassistant.const import **version**; print(**version**)')"

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

exec /opt/homeassistant/bin/hass 
--config /config
EOF

RUN chmod 0755 /usr/local/bin/homeassistant-entrypoint.sh

# ==========================================================

# Build validation

#

# Validate every important runtime component.

#

# NOTE:

# go2rtc-client is checked both by importing the Python

# module and by checking its installed package metadata.

# ==========================================================

RUN set -eux; 

# ------------------------------------------------------
# Python / Home Assistant
# ------------------------------------------------------
test -x /opt/homeassistant/bin/python; 
test -x /opt/homeassistant/bin/python3; 
test -x /opt/homeassistant/bin/pip; 
test -x /opt/homeassistant/bin/hass; 

# ------------------------------------------------------
# System Python
# ------------------------------------------------------
test -x /usr/bin/python3; 

# ------------------------------------------------------
# Native compiler
# ------------------------------------------------------
test -x /usr/bin/gcc; 
test -x /usr/bin/g++; 
test -x /usr/local/bin/aarch64-linux-gnu-gcc; 
test -x /usr/local/bin/aarch64-linux-gnu-g++; 

# ------------------------------------------------------
# Runtime utilities
# ------------------------------------------------------
test -x /usr/bin/bash; 
test -x /usr/bin/ffmpeg; 
test -x /usr/bin/ip; 
test -x /usr/bin/ping; 
test -x /usr/bin/sudo; 
test -x /usr/local/bin/homeassistant-entrypoint.sh; 

# ------------------------------------------------------
# go2rtc
# ------------------------------------------------------
test -x /bin/go2rtc; 

# ------------------------------------------------------
# Python version
# ------------------------------------------------------
/opt/homeassistant/bin/python --version; 

# ------------------------------------------------------
# Home Assistant
# ------------------------------------------------------
/opt/homeassistant/bin/python -c 
"from homeassistant.const import **version**; print('Home Assistant OK:', **version**)"; 

# ------------------------------------------------------
# zlib-ng
# ------------------------------------------------------
/opt/homeassistant/bin/python -c 
"import zlib_ng; print('zlib-ng OK')"; 

# ------------------------------------------------------
# Intel ISA-L Python bindings
# ------------------------------------------------------
/opt/homeassistant/bin/python -c 
"import isal; print('isal OK')"; 

# ------------------------------------------------------
# aiohttp fast zlib support
# ------------------------------------------------------
/opt/homeassistant/bin/python -c 
"import aiohttp_fast_zlib; print('aiohttp-fast-zlib OK')"; 

# ------------------------------------------------------
# go2rtc Python client
#
# This is the fix for:
#
# ModuleNotFoundError: No module named 'go2rtc_client'
# ------------------------------------------------------
/opt/homeassistant/bin/python -c 
"import go2rtc_client; print('go2rtc-client import OK')"; 

/opt/homeassistant/bin/python -c 
"import importlib.metadata as m; print('go2rtc-client version:', m.version('go2rtc-client'))"; 

# ------------------------------------------------------
# Home Assistant executable
# ------------------------------------------------------
/opt/homeassistant/bin/hass --version; 

# ------------------------------------------------------
# go2rtc executable
# ------------------------------------------------------
/bin/go2rtc --version; 

# ------------------------------------------------------
# FFmpeg
# ------------------------------------------------------
ffmpeg -version | head -n 1; 

# ------------------------------------------------------
# Compiler
# ------------------------------------------------------
gcc --version | head -n 1; 
g++ --version | head -n 1; 

# ------------------------------------------------------
# IPv4 preference
# ------------------------------------------------------
grep -q 
'^precedence ::ffff:0:0/96  100' 
/etc/gai.conf

# ==========================================================

# Final runtime environment

# ==========================================================

ENV HOME=/root 
TZ=Europe/London 
PYTHONUNBUFFERED=1 
PYTHONDONTWRITEBYTECODE=1 
PYTHONMALLOC=malloc 
MALLOC_ARENA_MAX=1 
PYTHONASYNCIODEBUG=0 
PIP_DISABLE_PIP_VERSION_CHECK=1 
PIP_NO_CACHE_DIR=1 
UV_NO_CACHE=1 
TMPDIR=/config/tmp 
TEMP=/config/tmp 
TMP=/config/tmp 
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
