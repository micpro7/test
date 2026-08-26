# syntax=docker/dockerfile:1

FROM python:3.14-slim-bookworm

LABEL org.opencontainers.image.title="Home Assistant Core UXC" \
      org.opencontainers.image.description="Lightweight Home Assistant Core UXC container for OpenWrt ARM64" \
      org.opencontainers.image.source="https://github.com/micpro7/homeassistant-uxc"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOMEASSISTANT_DOCKER=1 \
    TZ=Europe/London \
    PATH=/usr/local/bin:/usr/bin:/bin

WORKDIR /config

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Always install the latest Home Assistant available for this
# Python environment at build time.
RUN python3 -m pip install \
        --no-cache-dir \
        --disable-pip-version-check \
        homeassistant

COPY entrypoint.sh /entrypoint.sh

RUN chmod 0755 /entrypoint.sh && \
    mkdir -p /config

EXPOSE 8123

ENTRYPOINT ["/entrypoint.sh"]