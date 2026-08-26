#!/bin/sh
set -eu

echo "=============================================="
echo " Home Assistant Core - UXC"
echo " ARM64 / MX5300"
echo "=============================================="

mkdir -p /config

export TZ="${TZ:-Europe/London}"

exec python3 -m homeassistant --config /config