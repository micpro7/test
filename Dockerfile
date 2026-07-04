# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="homebridge-uxc" \
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
        ffmpeg

# =====================================================
# CRITICAL FIX: force deterministic npm global install path
# =====================================================
ENV NPM_CONFIG_PREFIX=/usr/local \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

RUN npm config set prefix /usr/local \
    && npm config set update-notifier false \
    && npm config set audit false \
    && npm config set fund false

# Install Homebridge + UI
RUN npm install -g --unsafe-perm \
        homebridge@${HOMEBRIDGE_VERSION} \
        homebridge-config-ui-x@${CONFIG_UI_VERSION}

# Validate installation (fail build early if wrong)
RUN test -f /usr/local/lib/node_modules/homebridge/package.json \
 && test -f /usr/local/lib/node_modules/homebridge-config-ui-x/package.json

# Show versions (for CI logs)
RUN node -e "console.log('homebridge:', require('/usr/local/lib/node_modules/homebridge/package.json').version)" \
 && node -e "console.log('ui:', require('/usr/local/lib/node_modules/homebridge-config-ui-x/package.json').version)"

ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production

WORKDIR /var/lib/homebridge