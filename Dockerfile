FROM alpine:3.19

# 1. Create the necessary mount points inside the container for UXC
RUN mkdir -p /mnt/SSD /mnt/X6

# 2. Install Node.js, npm, and build tools
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

# 3. Install Homebridge and the Config UI globally
RUN npm install -g --unsafe-perm homebridge homebridge-config-ui-x

# 4. Expose UI port
EXPOSE 8581

CMD ["homebridge", "-I", "-C"]
