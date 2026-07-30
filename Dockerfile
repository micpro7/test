# syntax=docker/dockerfile:1

FROM node:24-alpine3.22

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="OpenWrt UXC Homebridge" \
      org.opencontainers.image.description="Homebridge ARM64 filesystem bundle for OpenWrt UXC" \
      org.opencontainers.image.architecture="arm64"

# ==========================================================
# System packages
# ==========================================================
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    git \
    tzdata \
    ca-certificates \
    avahi \
    avahi-tools \
    dbus

# ==========================================================
# Environment
# ==========================================================
ENV NODE_OPTIONS="--max-old-space-size=128" \
    HOMEBRIDGE_CONFIG_UI=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    PATH="/usr/local/bin:$PATH"

# ==========================================================
# Install Homebridge + Config UI X
# ==========================================================
RUN npm install -g \
        homebridge@${HOMEBRIDGE_VERSION} \
        homebridge-config-ui-x@${CONFIG_UI_VERSION} \
    && npm cache clean --force

# ==========================================================
# Persistent UXC paths
# ==========================================================
RUN mkdir -p \
    /homebridge \
    /homebridge/accessories \
    /homebridge/backups \
    /homebridge/logs \
    /homebridge/persist \
    /usr/local/etc/homebridge

# ==========================================================
# Default Homebridge configuration location
# ==========================================================
ENV HOMEBRIDGE_CONFIG_PATH="/homebridge/config.json"

# ==========================================================
# Runtime
# ==========================================================
WORKDIR /homebridge

CMD ["homebridge", "-U", "/homebridge"]
