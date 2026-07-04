FROM node:24-alpine

# ==========================================================
# Build + runtime tools (OPTION A: keep everything installed)
# ==========================================================
RUN apk add --no-cache \
    tzdata \
    ca-certificates \
    dbus \
    avahi \
    avahi-compat-libdns_sd \
    ffmpeg \
    python3 \
    make \
    g++ \
    linux-headers \
    git

# ==========================================================
# Homebridge + UI install
# ==========================================================
ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

RUN npm install -g --unsafe-perm \
    homebridge@${HOMEBRIDGE_VERSION} \
    homebridge-config-ui-x@${CONFIG_UI_VERSION} \
 && npm cache clean --force \
 && rm -rf /root/.npm /tmp/*

# ==========================================================
# Small cleanup (SAFE only, no functionality impact)
# ==========================================================
RUN rm -rf \
    /tmp/* \
    /var/cache/apk/*

# ==========================================================
# Ports
# ==========================================================
EXPOSE 8581 51826

# ==========================================================
# Run Homebridge
# ==========================================================
CMD ["homebridge", "-I"]