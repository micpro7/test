```dockerfile
# syntax=docker/dockerfile:1

###############################################################################
# Homebridge UXC Builder
#
# Based on the official Homebridge Docker image but adapted for OpenWrt UXC.
#
# Target:
#   - ARM64
#   - Alpine 3.22
#   - Node.js 24
#   - Homebridge latest
#   - Homebridge Config UI X latest
###############################################################################

FROM node:24-alpine3.22

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="Homebridge UXC"
LABEL org.opencontainers.image.description="Homebridge container for OpenWrt UXC"
LABEL org.opencontainers.image.source="https://github.com/homebridge/docker-homebridge"

###############################################################################
# Environment
###############################################################################

ENV HOMEBRIDGE_DIR=/homebridge \
    HOMEBRIDGE_CONFIG_UI=1 \
    HOMEBRIDGE_INSECURE=1 \
    UIX_CONFIG_PATH=/homebridge \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_CACHE=/tmp/.npm

###############################################################################
# Packages
###############################################################################

RUN apk add --no-cache \
    bash \
    tini \
    su-exec \
    curl \
    jq \
    git \
    tzdata \
    ca-certificates \
    avahi \
    avahi-tools

###############################################################################
# Homebridge User
###############################################################################

RUN addgroup -S homebridge && \
    adduser -S \
        -h /homebridge \
        -G homebridge \
        homebridge

###############################################################################
# Install Homebridge
###############################################################################

RUN npm install -g \
        homebridge@${HOMEBRIDGE_VERSION} \
        homebridge-config-ui-x@${CONFIG_UI_VERSION} \
    && npm cache clean --force

###############################################################################
# Directories
###############################################################################

RUN mkdir -p \
    /homebridge \
    /homebridge/accessories \
    /homebridge/backups \
    /homebridge/logs \
    /homebridge/node_modules \
    /homebridge/persist \
    /usr/local/etc

COPY init /init

RUN chmod +x /init && \
    chown -R homebridge:homebridge /homebridge

ENTRYPOINT ["/sbin/tini","--","/init"]
```
