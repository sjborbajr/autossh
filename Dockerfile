FROM ubuntu:24.04

LABEL org.opencontainers.image.title="autossh" \
      org.opencontainers.image.description="Persistent ssh with reverse/local SSH tunnels via autossh; optional sshd admin access" \
      org.opencontainers.image.source="https://github.com/sjborbajr/autossh" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="1.0.0"

# universe repo is enabled by default in ubuntu:24.04; autossh lives there
# ── Extra packages (add more here at build time) ──────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    autossh \
    openssh-client \
    openssh-server \
    sudo \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/keys"]

ENTRYPOINT ["/entrypoint.sh"]
