# syntax=docker/dockerfile:1

FROM python:3.14-slim-trixie

LABEL org.opencontainers.image.title="Home Assistant Core UXC" \
      org.opencontainers.image.description="Lightweight Home Assistant Core UXC container for OpenWrt ARM64" \
      org.opencontainers.image.source="https://github.com/micpro7/homeassistant-uxc"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOMEASSISTANT_DOCKER=1 \
    TZ=Europe/London \
    PATH=/usr/local/bin:/usr/bin:/bin

WORKDIR /config

# Minimal runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install the latest Home Assistant release compatible
# with the Python 3.14 environment.
RUN python3 -m pip install \
        --no-cache-dir \
        --disable-pip-version-check \
        homeassistant

# Home Assistant UXC entrypoint
COPY entrypoint.sh /entrypoint.sh

RUN chmod 0755 /entrypoint.sh && \
    mkdir -p /config

EXPOSE 8123

ENTRYPOINT ["/entrypoint.sh"]