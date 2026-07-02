FROM alpine:3.19

# Install Node.js, npm, and build tools for native plugin compilation
RUN apk add --no-cache \
    nodejs \
    npm \
    bash \
    tzdata \
    git \
    python3 \
    make \
    g++

WORKDIR /homebridge

# Install Homebridge and the Config UI globally
RUN npm install -g --unsafe-perm homebridge homebridge-config-ui-x

# Expose UI port
EXPOSE 8581

# Fallback command (overridden by config.json)
CMD ["homebridge", "-I", "-C"]
