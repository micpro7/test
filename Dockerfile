# syntax=docker/dockerfile:1

# Using node:24-alpine guarantees Node.js 24 while pulling the latest compatible Alpine Linux base
FROM node:24-alpine

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="homebridge-uxc" \
      org.opencontainers.image.source="https://github.com/micpro7/HomeBridge-UXC"

# ==========================================================
# System dependencies
# (nodejs and npm are inherently provided by the base image)
# 
# Notes on compilation tools:
# - git: Required by npm to install beta plugins or dependencies hosted directly on GitHub URLs.
# - linux-headers: Required by node-gyp to compile native C/C++ plugins that need kernel/hardware access (e.g., Bluetooth BLE, raw network sockets).
# - python3, make, g++: Standard node-gyp requirements for compiling native modules.
# ==========================================================
RUN apk update && apk upgrade \
 && apk add --no-cache \
    tzdata \
    ca-certificates \
    avahi-compat-libdns_sd \
    libstdc++ \
    curl \
    ffmpeg \
    python3 \
    make \
    g++ \
    git \
    linux-headers

# ==========================================================
# CRITICAL FIX:
# Ensure deterministic npm global install location
# (prevents “missing package.json” / wrong prefix issues)
# ==========================================================
ENV NPM_CONFIG_PREFIX=/usr/local \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

RUN npm config set prefix /usr/local \
 && npm config set update-notifier false \
 && npm config set audit false \
 && npm config set fund false

# ==========================================================
# Install Homebridge stack
# ==========================================================
RUN npm install -g --unsafe-perm \
    homebridge@${HOMEBRIDGE_VERSION} \
    homebridge-config-ui-x@${CONFIG_UI_VERSION} \
 && npm cache clean --force

# ==========================================================
# HARD VALIDATION (fail fast if install breaks)
# ==========================================================
RUN set -eux; \
    test -f /usr/local/lib/node_modules/homebridge/package.json; \
    test -f /usr/local/lib/node_modules/homebridge-config-ui-x/package.json; \
    node -e "console.log('Node.js Version:', process.version)"; \
    node -e "console.log('Homebridge OK:', require('/usr/local/lib/node_modules/homebridge/package.json').version)"; \
    node -e "console.log('UI OK:', require('/usr/local/lib/node_modules/homebridge-config-ui-x/package.json').version)"

# ==========================================================
# Runtime environment
# ==========================================================
ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production

WORKDIR /var/lib/homebridge
