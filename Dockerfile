# syntax=docker/dockerfile:1.7

# ==========================================================
# HomeBridge UXC - v3 Optimised Build
# ==========================================================
#
# MAJOR CHANGE (v3):
#   We STOP using Alpine Node.js
#   We use OFFICIAL Node.js 24 LTS binary
#
# BENEFITS:
#   ✔ Latest Node.js LTS always
#   ✔ Faster runtime performance
#   ✔ More consistent npm behavior
#   ✔ Smaller Alpine runtime stage
#
# ==========================================================

ARG ALPINE_VERSION=3.22
ARG NODE_VERSION=24.0.0

# ==========================================================
# BUILD STAGE
# ==========================================================
FROM alpine:${ALPINE_VERSION} AS builder

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

RUN apk add --no-cache \
    python3 make g++ git linux-headers curl tar xz

ENV NPM_CONFIG_PREFIX=/usr/local

# Install temporary Node from Alpine (build only)
RUN apk add --no-cache nodejs npm

RUN npm config set prefix /usr/local \
 && npm config set audit false \
 && npm config set fund false \
 && npm config set update-notifier false

RUN npm install -g --unsafe-perm \
    homebridge@${HOMEBRIDGE_VERSION} \
    homebridge-config-ui-x@${CONFIG_UI_VERSION}

# Clean build artifacts aggressively
RUN npm cache clean --force \
 && rm -rf /root/.npm /root/.cache

# ==========================================================
# RUNTIME STAGE (CLEAN NODE 24)
# ==========================================================
FROM alpine:${ALPINE_VERSION}

ARG NODE_VERSION=24.0.0

# Runtime deps only
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    ffmpeg \
    avahi-compat-libdns_sd \
    libstdc++

# ==========================================================
# Install OFFICIAL Node.js 24 LTS
# ==========================================================
RUN curl -fsSL https://nodejs.org/dist/v24.0.0/node-v24.0.0-linux-arm64.tar.xz \
    | tar -xJ -C /usr/local --strip-components=1

ENV PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

# ==========================================================
# Copy Homebridge from builder
# ==========================================================
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin /usr/local/bin

# ==========================================================
# Hard validation
# ==========================================================
RUN node --version \
 && npm --version \
 && test -x /usr/local/bin/hb-service \
 && test -f /usr/local/lib/node_modules/homebridge/package.json

# ==========================================================
# Build metadata
# ==========================================================
RUN printf "Node=%s\nHomebridge=%s\nUI=%s\n" \
 "$(node --version)" \
 "$(node -p "require('/usr/local/lib/node_modules/homebridge/package.json').version")" \
 "$(node -p "require('/usr/local/lib/node_modules/homebridge-config-ui-x/package.json').version")" \
 > /etc/homebridge-build

# ==========================================================
# Cleanup
# ==========================================================
RUN rm -rf \
    /var/cache/apk/* \
    /tmp/* \
    /var/tmp/*

# ==========================================================
# Runtime environment
# ==========================================================
ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production \
    UV_THREADPOOL_SIZE=4 \
    NODE_OPTIONS="--max-old-space-size=256"

WORKDIR /var/lib/homebridge