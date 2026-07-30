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
    tini \
    procps \
    python3 \
    make \
    g++ \
    libstdc++ \
    avahi \
    avahi-tools \
    dbus


# ==========================================================
# Environment
# ==========================================================

ENV NODE_OPTIONS="--max-old-space-size=256" \
    UV_THREADPOOL_SIZE=4 \
    HOMEBRIDGE_CONFIG_UI=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    PATH="/usr/local/bin:$PATH"


# ==========================================================
# Install Homebridge + Config UI X
# ==========================================================

RUN npm install -g \
        homebridge@${HOMEBRIDGE_VERSION} \
        homebridge-config-ui-x@${CONFIG_UI_VERSION} \
    && npm cache clean --force


# ==========================================================
# Persistent UXC filesystem layout
# ==========================================================

RUN mkdir -p \
    /var/lib/homebridge \
    /var/lib/homebridge/accessories \
    /var/lib/homebridge/backups \
    /var/lib/homebridge/logs \
    /var/lib/homebridge/persist \
    /var/run/dbus \
    /etc/homebridge


# ==========================================================
# Homebridge defaults
# ==========================================================

ENV HOMEBRIDGE_CONFIG_PATH="/var/lib/homebridge/config.json"


WORKDIR /var/lib/homebridge


# ==========================================================
# Init script
# ==========================================================

COPY --chmod=755 init /init


# ==========================================================
# Runtime volumes
# ==========================================================

VOLUME ["/var/lib/homebridge"]


# ==========================================================
# Network
# ==========================================================

EXPOSE 8581/tcp
EXPOSE 5353/udp


# ==========================================================
# Healthcheck
# ==========================================================

HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=60s \
            --retries=3 \
    CMD pgrep -f homebridge >/dev/null || exit 1


# ==========================================================
# Entrypoint
# ==========================================================

ENTRYPOINT ["/sbin/tini","--","/init"]
