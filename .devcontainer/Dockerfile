# syntax=docker/dockerfile:1

ARG UV_VERSION=0.11.32
ARG MISE_VERSION=v2026.7.13
ARG CODEX_VERSION=0.147.0

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM debian:bookworm-slim AS core

LABEL org.opencontainers.image.source="https://github.com/projectew/devbox"
LABEL org.opencontainers.image.description="VS Code development environment with general and hardened-agent profiles"

ARG MISE_VERSION
ARG CODEX_VERSION
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    UV_LINK_MODE=copy \
    MISE_NODE_COREPACK=1 \
    MISE_DISABLE_TOOLS=python \
    PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/mise/shims:${PATH}

# Install system packages and set up user

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash-completion \
    bubblewrap \
    build-essential \
    ca-certificates \
    curl \
    file \
    git \
    git-lfs \
    gnupg \
    iproute2 \
    jq \
    less \
    make \
    openssh-client \
    pkg-config \
    procps \
    ripgrep \
    shellcheck \
    tini \
    unzip \
    xz-utils \
    zip \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && git lfs install --system

# Copy pinned uv binaries from official image

COPY --from=uv /uv /uvx /usr/local/bin/

# mise's official container install path, pinned to an immutable release

RUN curl -fsSL https://mise.run -o /tmp/mise-install.sh \
    && MISE_VERSION="${MISE_VERSION}" \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    sh /tmp/mise-install.sh \
    && rm /tmp/mise-install.sh

# Install the pinned standalone Codex CLI. Keeping CODEX_HOME outside the
# user's home makes the shared executable immutable while leaving each
# variant's credentials, configuration, and sessions in its own user home.

RUN CODEX_RELEASE="${CODEX_VERSION}" \
    CODEX_HOME=/opt/codex \
    CODEX_INSTALL_DIR=/usr/local/bin \
    CODEX_NON_INTERACTIVE=true \
    sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh | sh' \
    && codex --version

# Add mise activation to system .bashrc for interactive shells

RUN printf '\n# mise interactive activation\nif command -v mise >/dev/null 2>&1; then\n  eval "$(mise activate bash)"\nfi\n' \
    >> /etc/bash.bashrc

# Copy control/ scripts from outside workspace into container for execution

COPY --chmod=0555 control/setup.sh \
    /usr/local/libexec/devbox/setup.sh

USER ${USERNAME}

WORKDIR /workspace
CMD ["sleep", "infinity"]

FROM core AS general

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends sudo \
    && printf '%s ALL=(root) NOPASSWD:ALL\n' "${USERNAME}" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && rm -rf /var/lib/apt/lists/*
USER ${USERNAME}

FROM core AS agent

# The devcontainer configuration supplies the runtime restrictions. This stage
# intentionally has no sudo and no daemon access.
LABEL devbox.variant="agent-hardened"

USER root
RUN install -d -o root -g root -m 0755 /etc/codex
COPY --chown=root:root --chmod=0444 control/codex-agent-requirements.toml \
    /etc/codex/requirements.toml
USER ${USERNAME}
