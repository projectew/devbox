#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE="${DEVBOX_SECURITY_PROFILE:-general}"
PROJECT_ROOT="${DEVBOX_PROJECT_ROOT:-/workspace}"

cd "$PROJECT_ROOT"

log() {
    printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2
}

die() {
    printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command not found: $1"
}


# ---------------------------------------------------------------------------
# Base environment
# ---------------------------------------------------------------------------

log "Devbox profile: ${PROFILE}"

require_command uv
require_command mise
require_command git
require_command codex

printf 'uv:   %s\n' "$(uv --version)"
printf 'mise: %s\n' "$(mise --version)"
printf 'Codex: %s\n' "$(codex --version)"


# ---------------------------------------------------------------------------
# Hardened-agent boundary checks
# ---------------------------------------------------------------------------

check_agent_boundary() {
    log "Checking hardened agent boundary"

    [[ "$(id -u)" -ne 0 ]] ||
        die "Agent container is running as root"

    root_options="$(findmnt -no OPTIONS /)"
    if ! tr ',' '\n' <<<"$root_options" | grep -qx 'ro'; then
        die "Root filesystem is not read-only"
    fi

    if [[ -S /var/run/docker.sock ]]; then
        die "Docker socket is available"
    fi

    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
        die "SSH agent socket is available"
    fi

    cap_eff="$(
        awk '/^CapEff:/ {print $2}' /proc/self/status
    )"

    [[ "$cap_eff" == "0000000000000000" ]] ||
        die "Effective Linux capabilities are not zero: ${cap_eff}"

    sensitive_vars=(
        OPENAI_API_KEY
        CODEX_ACCESS_TOKEN
        FIREWORKS_API_KEY
        OPENROUTER_API_KEY
        LITELLM_MASTER_KEY
        AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY
        GITHUB_TOKEN
    )

    for name in "${sensitive_vars[@]}"; do
        if [[ -n "${!name:-}" ]]; then
            die "Sensitive host credential is present: ${name}"
        fi
    done

    if [[ -f "$HOME/.gitconfig" ]]; then
        warn "A host/user Git configuration exists at $HOME/.gitconfig"
    fi

    codex_requirements=/etc/codex/requirements.toml
    [[ -f "$codex_requirements" ]] ||
        die "Managed Codex requirements are missing"
    [[ ! -w "$codex_requirements" ]] ||
        die "Managed Codex requirements are writable"

    credential_helpers="$(
        git config --show-origin --get-all credential.helper 2>/dev/null || true
    )"

    if [[ -n "$credential_helpers" ]]; then
        die "Git credential helper is configured in hardened mode: ${credential_helpers}"
    fi

    log "Agent boundary checks passed"
}


if [[ "$PROFILE" == "agent-hardened" ]]; then
    check_agent_boundary
fi


# ---------------------------------------------------------------------------
# Python / uv
# ---------------------------------------------------------------------------

if [[ -f ".python-version" || -f ".python-versions" ]]; then
    log "Installing project Python"

    # uv reads .python-version/.python-versions automatically.
    uv python install
fi

if [[ -f "pyproject.toml" ]]; then
    log "Synchronizing Python project"

    if [[ -f "uv.lock" ]]; then
        uv sync --locked
    # elif [[ "$PROFILE" == "agent-hardened" ]]; then
    #     die "pyproject.toml exists but uv.lock is absent in hardened mode"
    else
        warn "No uv.lock found; generating initial lockfile"
        uv sync
    fi
fi


# ---------------------------------------------------------------------------
# mise project toolchain
# ---------------------------------------------------------------------------

if [[ -f "mise.toml" || -f ".mise.toml" ]]; then
    log "Installing mise project tools"

    if [[ -f "mise.lock" ]]; then
        mise install --locked
    # elif [[ "$PROFILE" == "agent-hardened" ]]; then
    #     die "mise config exists but mise.lock is absent in hardened mode"
    else
        warn "No mise.lock found; installing and generating/updating lock data"
        mise install
    fi

    log "Configured mise tools"
    mise current || true
fi


# ---------------------------------------------------------------------------
# JavaScript dependencies
# ---------------------------------------------------------------------------

if [[ -f "package.json" ]]; then
    log "Synchronizing JavaScript dependencies"

    if [[ -f "package-lock.json" || -f "npm-shrinkwrap.json" ]]; then
        mise exec -- npm ci
    # elif [[ "$PROFILE" == "agent-hardened" ]]; then
    #     die "package.json exists but no npm lockfile exists in hardened mode"
    else
        warn "No npm lockfile found; generating one"
        mise exec -- npm install
    fi
fi


# ---------------------------------------------------------------------------
# Project hooks
# ---------------------------------------------------------------------------

if [[ -f ".pre-commit-config.yaml" ]] \
    && [[ -f "pyproject.toml" ]]; then

    if uv run --no-sync pre-commit --version >/dev/null 2>&1; then
        log "Installing pre-commit hooks"
        uv run --no-sync pre-commit install
    fi
fi


# ---------------------------------------------------------------------------
# Final checks
# ---------------------------------------------------------------------------

if [[ "$PROFILE" == "agent-hardened" ]]; then
    check_agent_boundary
fi

log "Environment ready"

if [[ -x ".venv/bin/python" ]]; then
    printf 'Python: %s\n' "$(".venv/bin/python" --version)"
fi

if command -v node >/dev/null 2>&1; then
    printf 'Node:   %s\n' "$(node --version)"
fi
