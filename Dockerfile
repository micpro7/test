# syntax=docker/dockerfile:1

# Official Node.js 24 LTS Alpine image
FROM node:24-alpine

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="openwrt-uxc-homebridge" \
      org.opencontainers.image.description="Homebridge deployment for OpenWrt using native UXC containers" \
      org.opencontainers.image.source="https://github.com/micpro7/openwrt-uxc-homebridge"

# ==========================================================
# System dependencies & Tini PID 1 Engine
# All build tools (make, g++, python3, git, headers) are preserved 
# to support runtime native plugin compilation.
# ==========================================================
RUN apk add --no-cache \
    curl \
    xz \
    tzdata \
    ca-certificates \
    avahi \
    avahi-compat-libdns_sd \
    dbus \
    libstdc++ \
    ffmpeg \
    python3 \
    make \
    g++ \
    git \
    linux-headers \
    sudo \
    bash \
    openssh-client \
    tini

# ==========================================================
# Install latest Node.js 24.x (musl build for Alpine)
# 1. Index-based version lookup prevents 404 alias failures.
# 2. SHA256 checksum verification protects against corrupted downloads.
# ==========================================================
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
        aarch64) NODE_ARCH="arm64" ;; \
        x86_64) NODE_ARCH="x64" ;; \
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac; \
    \
    # Resolve latest v24.x release version for musl \
    NODE_VERSION="$( \
        curl -fsSL https://unofficial-builds.nodejs.org/download/release/index.tab \
        | awk -v arch="linux-${NODE_ARCH}-musl" '$1 ~ /^v24\./ && $0 ~ arch { print $1; exit }' \
    )"; \
    echo "Resolved Node.js Version: ${NODE_VERSION}"; \
    \
    TARBALL="node-${NODE_VERSION}-linux-${NODE_ARCH}-musl.tar.xz"; \
    BASE_URL="https://unofficial-builds.nodejs.org/download/release/${NODE_VERSION}"; \
    \
    # Download binary archive & SHASUMS256.txt \
    curl -fsSL "${BASE_URL}/${TARBALL}" -o "/tmp/${TARBALL}"; \
    curl -fsSL "${BASE_URL}/SHASUMS256.txt" -o "/tmp/SHASUMS256.txt"; \
    \
    # SHA256 Checksum Verification \
    cd /tmp; \
    grep " ${TARBALL}\$" SHASUMS256.txt | sha256sum -c -; \
    \
    # Extract to /usr/local & clean up \
    tar -xJ -f "/tmp/${TARBALL}" --strip-components=1 -C /usr/local; \
    rm -f "/tmp/${TARBALL}" /tmp/SHASUMS256.txt; \
    \
    node --version; \
    npm --version

# ==========================================================
# Avahi & DBus run directory setup
# ==========================================================
RUN mkdir -p /var/run/dbus /var/run/avahi-daemon \
 && chown -R root:root /var/run/dbus /var/run/avahi-daemon

# ==========================================================
# UXC FIX: Replace sudo binary with robust option-stripping wrapper
# ==========================================================
RUN rm -f /usr/bin/sudo \
 && cat > /usr/bin/sudo <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
        -n|-E|-H|-S|-k|-K|-b|-v)
            shift
            ;;
        -u|-g|-C)
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "sudo: no command specified" >&2
    exit 1
fi

exec "$@"
EOF
RUN chmod 0755 /usr/bin/sudo

# ==========================================================
# READ-ONLY / OVERLAY ROOTFS FIX: Redirect npm cache/config/build to /tmp
# ==========================================================
RUN mkdir -p /tmp/.npm /tmp/.config /tmp/.node-gyp \
 && rm -rf /root/.npm /root/.config \
 && ln -s /tmp/.npm /root/.npm \
 && ln -s /tmp/.config /root/.config

# ==========================================================
# CRITICAL FIX: Deterministic npm global install location and module paths
# ==========================================================
ENV NPM_CONFIG_PREFIX=/usr/local \
    NODE_PATH=/var/lib/homebridge/node_modules:/usr/local/lib/node_modules \
    npm_config_unsafe_perm=true \
    PYTHON=/usr/bin/python3 \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin

RUN npm config set prefix /usr/local \
 && npm config set update-notifier false \
 && npm config set audit false \
 && npm config set fund false \
 && npm cache verify

# ==========================================================
# Install Homebridge stack globally
# ==========================================================
RUN npm install -g --unsafe-perm \
    homebridge@${HOMEBRIDGE_VERSION} \
    homebridge-config-ui-x@${CONFIG_UI_VERSION} \
 && npm cache clean --force

# ==========================================================
# Persistent mount points for host flash media
# ==========================================================
RUN mkdir -p \
    /var/lib/homebridge \
    /var/lib/homebridge/node_modules \
    /var/lib/homebridge/persist \
    /var/lib/homebridge/accessories

# ==========================================================
# HARD VALIDATION (fail fast if build breaks)
# ==========================================================
RUN set -eux; \
    test -f /usr/local/lib/node_modules/homebridge/package.json; \
    test -f /usr/local/lib/node_modules/homebridge-config-ui-x/package.json; \
    command -v homebridge; \
    command -v hb-service; \
    node -e "console.log('Node.js Version:', process.version)"; \
    node -e "console.log('Homebridge OK:', require('/usr/local/lib/node_modules/homebridge/package.json').version)"; \
    node -e "console.log('UI OK:', require('/usr/local/lib/node_modules/homebridge-config-ui-x/package.json').version)"

# ==========================================================
# Runtime Environment & Container Launch
# ==========================================================
ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production \
    NPM_CONFIG_CACHE=/tmp/.npm \
    NPM_CONFIG_DEVDIR=/tmp/.node-gyp \
    XDG_CONFIG_HOME=/tmp/.config

WORKDIR /var/lib/homebridge

EXPOSE 8581

ENTRYPOINT ["/sbin/tini", "-g", "--"]

CMD ["/bin/sh", "-c", "while true; do /usr/local/bin/hb-service run --allow-root -U /var/lib/homebridge -P /var/lib/homebridge/node_modules; echo \"$(date) Homebridge crashed - restarting in 3s\"; sleep 3; done"]
