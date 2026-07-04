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
# Known trade-off: a small number of Homebridge plugins ship prebuilt
# glibc binaries and will not load on musl. Plugins that compile from
# source via node-gyp (the vast majority) work fine, which is why the
# build toolchain below is kept in the final image, not just a build stage.

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
    && npm config set update-notifier false \
    && npm config set audit false \
    && npm config set fund false \
    && npm install -g --unsafe-perm \
        homebridge@${HOMEBRIDGE_VERSION} \
        homebridge-config-ui-x@${CONFIG_UI_VERSION} \
    && npm cache clean --force \
    && mkdir -p /var/lib/homebridge/plugins \
    \
    # Record npm global root so CI can reliably locate installed modules
    && npm root -g > /etc/npm-global-root \
    \
    # Sanity checks (fail build early if install breaks)
    && NPM_ROOT="$(cat /etc/npm-global-root)" \
    && node -e "console.log('homebridge', require(process.argv[1]).version)" "${NPM_ROOT}/homebridge/package.json" \
    && node -e "console.log('homebridge-config-ui-x', require(process.argv[1]).version)" "${NPM_ROOT}/homebridge-config-ui-x/package.json"

ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production \
    npm_config_update_notifier=false

WORKDIR /var/lib/homebridge

# There is no CMD/ENTRYPOINT here on purpose: the actual start command lives
# in oci/config.json (process.args), since this filesystem is consumed as an
# OCI runtime bundle, not run as a Docker container.