FROM node:22-bookworm

# Create directories for openclaw config and workspace
RUN mkdir -p /home/node/.openclaw \
  && chown -R node:node /home/node/.openclaw \
  && mkdir -p /home/node/.openclaw/workspace \
  && chown -R node:node /home/node/.openclaw/workspace

# Install Bun (required for build scripts)
ENV BUN_INSTALL=/home/node/.bun
RUN curl -fsSL https://bun.sh/install | bash \
  && chown -R node:node /home/node/.bun
ENV PATH="/home/node/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    file \
    git \
    procps \
    xz-utils \
    zstd \
  && if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
       DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES; \
     fi \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
  && chown -R node:node /app

# Install Tailscale (for serve, whois, and tailnet connectivity)
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
    > /usr/share/keyrings/tailscale-archive-keyring.gpg \
  && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
    > /etc/apt/sources.list.d/tailscale.list \
  && apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tailscale \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Tailscale state + socket directories (writable by node user for userspace mode)
RUN mkdir -p /var/lib/tailscale && chown node:node /var/lib/tailscale \
  && mkdir -p /var/run/tailscale && chown node:node /var/run/tailscale

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node
ENV HOME=/home/node

# Install homebrew
RUN git clone https://github.com/Homebrew/brew /home/node/.linuxbrew/Homebrew \
  && mkdir -p /home/node/.linuxbrew/bin /home/node/.linuxbrew/sbin /home/node/.linuxbrew/Cellar \
  && ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew

ENV PATH="/home/node/.linuxbrew/bin:/home/node/.linuxbrew/sbin:${PATH}"
RUN brew update

COPY --chown=node:node package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY --chown=node:node ui/package.json ./ui/package.json
COPY --chown=node:node patches ./patches
COPY --chown=node:node scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY --chown=node:node . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production
ENV HOMEBREW_PREFIX=/home/node/.linuxbrew

# Start gateway server with default config.
# Binds to loopback (127.0.0.1) by default for security.
#
# For container platforms requiring external health checks:
#   1. Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD env var
#   2. Override CMD: ["node","openclaw.mjs","gateway","--allow-unconfigured","--bind","lan"]
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
