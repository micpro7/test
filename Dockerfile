# syntax=docker/dockerfile:1
#
# Builds the root filesystem for the HomeBridge-UXC OCI bundle.
#
# This is intentionally NOT built to be run with `docker run`. The workflow
# in .github/workflows/build-release.yml exports the final filesystem with
# `docker buildx build --output type=tar` and repacks it as `rootfs/` inside
# an OCI runtime bundle for OpenWrt's `uxc` (procd) container runtime.
#
# Base: Alpine Linux (musl libc). Alpine's `nodejs` package tracks upstream
# Node.js LTS, which satisfies Homebridge v2's Node >=22 requirement.
#
# Key improvement in this version:
# - We FORCE npm global prefix to a known path
# - This removes ALL reliance on /usr/lib or /usr/local/lib detection
# - CI no longer needs npm-global-root hacks (optional but still written for safety)

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="homebridge-uxc" \
      org.opencontainers.image.description="Homebridge + Homebridge UI on Alpine, packaged as a UXC/OCI bundle for OpenWrt" \
      org.opencontainers.image.source="https://github.com/micpro7/HomeBridge-UXC"

RUN apk add --no-cache \
        nodejs \
        npm \
        tzdata \
        ca-certificates \
        avahi-compat-libdns_sd \
        python3 \
        make \
        g++ \
        git \
        linux-headers \
        libstdc++ \
        curl \
        ffmpeg \
    \
    # ------------------------------------------------------------------
    # FORCE deterministic npm global install location
    # ------------------------------------------------------------------
    && mkdir -p /usr/local/lib/node_modules \
    && npm config set prefix /usr/local \
    \
    && npm config set update-notifier false \
    && npm config set audit false \
    && npm config set fund false \
    \
    # Install Homebridge + UI globally into controlled prefix
    && npm install -g --unsafe-perm \
        homebridge@${HOMEBRIDGE_VERSION} \
        homebridge-config-ui-x@${CONFIG_UI_VERSION} \
    \
    # Clean npm cache
    && npm cache clean --force \
    \
    # Runtime directories expected by Homebridge
    && mkdir -p /var/lib/homebridge/plugins \
    \
    # Optional compatibility file for CI (safe fallback)
    && npm root -g > /etc/npm-global-root \
    \
    # ------------------------------------------------------------------
    # HARD VALIDATION (fail build early if layout changes)
    # ------------------------------------------------------------------
    && test -f /usr/local/lib/node_modules/homebridge/package.json \
    && test -f /usr/local/lib/node_modules/homebridge-config-ui-x/package.json \
    \
    && node -e "console.log('homebridge', require(process.argv[1]).version)" \
         /usr/local/lib/node_modules/homebridge/package.json \
    \
    && node -e "console.log('homebridge-ui', require(process.argv[1]).version)" \
         /usr/local/lib/node_modules/homebridge-config-ui-x/package.json

ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production \
    npm_config_update_notifier=false

WORKDIR /var/lib/homebridge

# There is no CMD/ENTRYPOINT here on purpose: the actual start command lives
# in oci/config.json (process.args), since this filesystem is consumed as an
# OCI runtime bundle, not run as a Docker container.