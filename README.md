# General development Dev Containers

This project provides two custom-Dockerfile-based VS Code Dev Container
variants for WSL-hosted work in `/home/jordan/projects/devbox`.

| Variant | Intended use | Privilege and host access |
| --- | --- | --- |
| **Devbox - General** | Python, Node/web, Go, Rust, and container-client work | Non-root by default, passwordless sudo available; exact project mounted; Docker socket not mounted |
| **Devbox - Hardened Agent** | AI agents and less-trusted generated code | No sudo; read-only root; capabilities dropped; ephemeral home; Git/SSH credential paths disabled; Docker socket absent |

Both variants use uv-managed Python and mise-managed Node, Go, and Rust. Codex
CLI and its Linux `bubblewrap` sandbox dependency are installed in the shared
image. The Docker CLI and Compose/Buildx plugins are installed, but the host
daemon is deliberately not exposed.

## Open a variant

1. Open this WSL folder in VS Code.
2. Run **Dev Containers: Reopen in Container**.
3. Select **Devbox - General** or **Devbox - Hardened Agent** when prompted.
4. After creation, run `bash scripts/check-environment.sh` at any time to inspect
   the installed toolchain. The hardened variant runs its stricter preflight
   automatically.

The first build downloads language runtimes and VS Code extensions. Rebuild the
container after changing Docker build arguments or either Dev Container file.

## Use the published Dev Container in a new project

The general image is published for Linux amd64 at
`ghcr.io/projectew/devbox:general`. Copy
[`examples/general/.devcontainer/devcontainer.json`](examples/general/.devcontainer/devcontainer.json)
to `.devcontainer/devcontainer.json` in a new project's root, then run **Dev
Containers: Reopen in Container**.

The complete configuration pulls the image, mounts the new project at
`/workspace`, and runs the trusted setup script built into the image. That script
installs only the language versions and dependencies declared by the new
project. No registry credential is required while the GHCR package is public.

The mutable `general` tag follows the latest successful build from `main`. For a
reproducible project, replace it with the immutable commit tag emitted by the
workflow, such as `general-<full-git-sha>`.

## Toolchain policy

- Python is installed and managed by uv. Start a project with `uv init`, add
  dependencies with `uv add`, and run commands with `uv run`.
- Node, Go, and Rust are installed through mise and declared in `mise.toml`.
  Use `mise use node@<version>` (and the corresponding command for Go or Rust)
  to change a project toolchain. Corepack support is enabled for Node package
  managers.
- Python is deliberately absent from `mise.toml`; uv remains the sole Python
  implementation and environment manager.
- Docker is client-only by default. Point `DOCKER_HOST` at a deliberately
  provisioned rootless/remote engine when container execution is required.

The image pins `uv` to 0.11.32 and the mise CLI to 2026.7.13. The project config
tracks Node v24 LTS, Go 1.26, and stable Rust. Codex CLI is pinned to 0.147.0
through the official standalone installer. For stronger reproducibility, use
fully qualified patch versions, enable a mise lockfile, and pin base images and
the uv stage by digest.

## Codex CLI

Run `codex` from `/workspace`. The general variant keeps Codex state under the
normal user home for the life of the container. The hardened variant keeps its
home and `~/.codex` state in tmpfs, so login tokens and sessions disappear when
the container is removed; use `codex login --device-auth` for a headless login.
Neither variant receives host Codex credentials or API keys automatically.

The hardened image also installs immutable requirements at
`/etc/codex/requirements.toml`. They allow only read-only or workspace-scoped
permission profiles, keep approvals human-reviewed, disable unmanaged hooks and
login shells, and prevent `:danger-full-access`. Rebuild the image after changing
this policy. Its Docker seccomp profile is deliberately unconfined so
`bubblewrap` can create Codex's nested sandbox; the read-only root, dropped
capabilities, `no-new-privileges`, tmpfs mounts, and managed Codex requirements
remain enforced.

## AI authorization pattern

Use the hardened container as the outer boundary and configure the agent or
harness as the inner policy boundary:

1. default file writes to `/workspace` only;
2. require approval for network, credentials, elevated actions, and destructive
   commands;
3. issue scoped, short-lived credentials only after approval;
4. log tool requests and approval decisions outside the agent-controlled
   workspace when auditability matters;
5. review the workspace diff before any trusted build, deploy, or publish step.

See [SECURITY.md](SECURITY.md) for the threat model and limitations.

## Local tool overrides

`mise.local.toml` is ignored by Git and is the right place for personal tool
overrides. Do not put secrets in it: mise configuration is executable/trusted
input, and an agent that can read the workspace can read that file too.

The hardened variant ignores all mise configuration under `/workspace` and uses
the immutable `/etc/mise/config.toml` copy baked into the image. Rebuild that
variant after changing tool versions; this prevents an agent from turning a
workspace config hook into code execution outside its normal command flow.
