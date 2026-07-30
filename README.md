# Homebridge UXC

Homebridge packaged specifically for OpenWrt UXC.

## Features

- Alpine 3.22
- Node.js 24
- Latest Homebridge
- Latest Homebridge Config UI X
- ARM64
- Persistent configuration
- Optimised for OpenWrt
- SSD friendly
- No writable overlay required

## Build

```bash
docker build \
    -t homebridge-uxc .
```

## Output

The GitHub Action exports:

```
config.json
rootfs/
homebridge-arm64.tar.gz
```

## Persistent Storage

Mount your SSD directly to:

```
/homebridge
```

Example:

```
/mnt/SSD/Config/OpenWRT/Homebridge
```

Contents:

```
config.json
accessories/
backups/
logs/
persist/
node_modules/
```

## Create UXC

```bash
uxc create \
    --bundle ./ \
    --name homebridge \
    --mount /mnt/SSD/Config/OpenWRT/Homebridge:/homebridge
```

## Start

```bash
uxc start homebridge
```

## Web UI

```
http://router-ip:8581
```

## HomeKit

Uses host networking and Avahi for Bonjour discovery.
