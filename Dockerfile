# syntax=docker/dockerfile:1

ARG NODE_VERSION=current-alpine
FROM node:${NODE_VERSION}

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="homebridge-uxc" \
      org.opencontainers.image.source="https://github.com/micpro7/HomeBridge-UXC"

# ==========================================================
# Minimal runtime deps (LOW MEMORY BUILD)
# ==========================================================
RUN apk add --no-cache \
    tzdata \
    ca-certificates \
    avahi-compat-libdns_sd \
    ffmpeg \
    libstdc++

# ==========================================================
# Reduce npm noise + memory overhead
# ==========================================================
ENV NPM_CONFIG_PREFIX=/usr/local \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NODE_ENV=production \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

# ==========================================================
# Install Homebridge stack
# ==========================================================
RUN npm install -g --unsafe-perm \
    homebridge@${HOMEBRIDGE_VERSION} \
    homebridge-config-ui-x@${CONFIG_UI_VERSION} \
 && npm cache clean --force \
 && rm -rf /root/.npm /tmp/*

# ==========================================================
# Hard validation
# ==========================================================
RUN set -eux; \
    node -v; \
    npm -v; \
    test -x /usr/local/bin/hb-service; \
    test -f /usr/local/lib/node_modules/homebridge/package.json

# ==========================================================
# Runtime
# ==========================================================
ENV HOME=/root \
    TZ=UTC

WORKDIR /var/lib/homebridge