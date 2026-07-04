# syntax=docker/dockerfile:1.7

# ==========================================================
# HomeBridge UXC Docker Build
# ==========================================================
#
# This image is built ONLY to generate an OCI rootfs bundle.
#
# Runtime:
#   OpenWrt UXC
#
# Design goals:
#
# ✔ Stable
# ✔ Reproducible
# ✔ Small runtime
# ✔ Latest Homebridge
# ✔ Latest Homebridge UI
# ✔ Clean OCI filesystem
#
# ==========================================================

ARG ALPINE_VERSION=3.22

# ==========================================================
# Builder Stage
# ==========================================================

FROM alpine:${ALPINE_VERSION} AS builder

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="homebridge-uxc"
LABEL org.opencontainers.image.source="https://github.com/micpro7/HomeBridge-UXC"

# ==========================================================
# Build dependencies
#
# These are required ONLY while npm installs native modules.
# None of these packages will exist in the final runtime.
# ==========================================================

RUN apk add --no-cache \
    nodejs \
    npm \
    python3 \
    make \
    g++ \
    git \
    linux-headers \
    curl

# ==========================================================
# Deterministic npm global location
# ==========================================================

ENV NPM_CONFIG_PREFIX=/usr/local

ENV PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

RUN npm config set prefix /usr/local \
 && npm config set update-notifier false \
 && npm config set audit false \
 && npm config set fund false

# ==========================================================
# Install Homebridge
# ==========================================================

RUN --mount=type=cache,target=/root/.npm \
    npm install -g --unsafe-perm \
    homebridge@${HOMEBRIDGE_VERSION} \
    homebridge-config-ui-x@${CONFIG_UI_VERSION}

# ==========================================================
# Validation
# Fail immediately if anything is wrong.
# ==========================================================

RUN set -eux; \
    test -x /usr/bin/node; \
    test -x /usr/local/bin/hb-service; \
    test -f /usr/local/lib/node_modules/homebridge/package.json; \
    test -f /usr/local/lib/node_modules/homebridge-config-ui-x/package.json

RUN node --version
RUN npm --version

RUN node -e "console.log('Homebridge:',require('/usr/local/lib/node_modules/homebridge/package.json').version)"
RUN node -e "console.log('Homebridge UI:',require('/usr/local/lib/node_modules/homebridge-config-ui-x/package.json').version)"

# ==========================================================
# Runtime Stage
#
# Only packages required for execution remain.
# ==========================================================

FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="homebridge-uxc"
LABEL org.opencontainers.image.source="https://github.com/micpro7/HomeBridge-UXC"

# ==========================================================
# Runtime packages only
# ==========================================================

RUN apk add --no-cache \
    nodejs \
    npm \
    tzdata \
    ca-certificates \
    avahi-compat-libdns_sd \
    ffmpeg \
    libstdc++

# ==========================================================
# Copy installed Homebridge
# ==========================================================

COPY --from=builder /usr/local /usr/local

# ==========================================================
# Runtime validation
# ==========================================================

RUN set -eux; \
    test -x /usr/bin/node; \
    test -x /usr/local/bin/hb-service; \
    test -f /usr/local/lib/node_modules/homebridge/package.json; \
    test -f /usr/local/lib/node_modules/homebridge-config-ui-x/package.json

# ==========================================================
# Record build information
# (Workflow can read this later.)
# ==========================================================

RUN printf "Node=%s\nnpm=%s\nHomebridge=%s\nUI=%s\nAlpine=%s\n" \
    "$(node --version)" \
    "$(npm --version)" \
    "$(node -p "require('/usr/local/lib/node_modules/homebridge/package.json').version")" \
    "$(node -p "require('/usr/local/lib/node_modules/homebridge-config-ui-x/package.json').version")" \
    "$(cat /etc/alpine-release)" \
    > /etc/homebridge-build

# ==========================================================
# Cleanup
# ==========================================================

RUN npm cache clean --force \
 && rm -rf \
    /root/.npm \
    /root/.cache \
    /tmp/* \
    /var/tmp/* \
    /var/cache/apk/*

# ==========================================================
# Runtime Environment
# ==========================================================

ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

WORKDIR /var/lib/homebridge

# ==========================================================
# End of Dockerfile
# ==========================================================