# Devbox

Devbox is a trusted wrapper for running a project in one of two VS Code Dev
Container profiles:

- **General** provides a convenient, non-root development environment with
  passwordless `sudo`.
- **Hardened Agent** adds container-level restrictions for AI agents and other
  less-trusted project automation.

The containers provide reproducible tooling and defense in depth. They are
designed to run inside a disposable Linux VM or similarly isolated development
host; the VM remains the primary boundary protecting a personal workstation and
its credentials.

## Trusted wrapper layout

```text
devbox/
├── .devcontainer/   trusted container definitions
├── control/         trusted setup and managed agent policy
└── workspace/       project files exposed to the container
```

Only `workspace/` is mounted at `/workspace`. Keeping the Dev Container and
control files outside that mount prevents processes in the container from
changing the configuration used for the next rebuild or start.

## Profiles

| Profile | Intended use | Current behavior |
| --- | --- | --- |
| **General** | Normal development and trusted automation | Runs as `vscode`, permits passwordless `sudo`, persists the user home with the container, and runs project setup once after creation |
| **Hardened Agent** | AI agents and less-trusted generated code | Runs without `sudo`, uses a read-only root filesystem, drops all capabilities, applies resource limits, uses ephemeral writable storage, and checks its boundary on every start |

Neither profile declares a host Docker-socket or SSH-agent mount. The hardened
profile additionally points `SSH_AUTH_SOCK` at a nonexistent socket and verifies
that no real agent socket is available. The image does not currently install the
Docker CLI.

## Open this repository locally

1. Put or clone the project to develop under `workspace/`.
2. Open the trusted wrapper directory in VS Code on the isolated Linux host.
3. Run **Dev Containers: Reopen in Container**.
4. Select **Devbox - General** or **Devbox - Hardened Agent**.

The first build downloads the base image dependencies and VS Code extensions.
The project toolchains are installed later from declarations under `workspace/`.

## Use the published general container

The workflow in `.github/workflows/publish-general.yml` publishes the general
Linux amd64 image on successful pushes to `main`:

```text
ghcr.io/projectew/devbox:general
ghcr.io/projectew/devbox:general-<full-git-sha>
```

The moving `general` tag is convenient for evaluation. Use a commit-qualified
tag when a project needs repeatable builds.

For a new trusted wrapper, copy
[`examples/general/.devcontainer/devcontainer.json`](examples/general/.devcontainer/devcontainer.json)
to `.devcontainer/devcontainer.json`, create the sibling `workspace/` directory,
and put the actual project inside it. The example pulls the public image rather
than rebuilding the Dockerfile while preserving the trusted-wrapper mount
boundary.

Only the general profile is published today. The hardened profile still depends
on runtime restrictions in its local `devcontainer.json` and must not be treated
as hardened when started from the image alone.

## Included tools

The shared image contains common build utilities plus:

- Git and Git LFS;
- uv `0.11.32` for Python installation, virtual environments, and dependencies;
- mise `2026.7.13` for Node, Go, Rust, and other non-Python tools;
- Codex CLI `0.147.0` and `bubblewrap` for Codex's Linux sandbox.

The image does not preinstall project-selected Python, Node, Go, or Rust
versions. The declarations currently included under `workspace/` are examples:
Python 3.14 through `.python-version`, and Node 24, Go 1.26, and stable Rust
through `mise.toml`.

## Project setup behavior

The trusted `/usr/local/libexec/devbox/setup.sh` script runs from the image.
General mode invokes it after container creation; hardened mode invokes it after
every start.

- `.python-version` or `.python-versions` causes uv to install the requested
  Python version.
- `pyproject.toml` is synchronized with `uv sync --locked` when `uv.lock`
  exists; otherwise uv creates initial lock data.
- `mise.toml` or `.mise.toml` causes mise to install declared tools. A present
  `mise.lock` is enforced with `mise install --locked`; otherwise mise performs
  an unlocked install.
- `package.json` is installed with `npm ci` when an npm lockfile exists and
  `npm install` otherwise.
- A configured `pre-commit` dependency may install repository Git hooks.

The hardened profile sets `MISE_SAFE=1`, but it still reads project tool
declarations. Lockfiles are strongly recommended but are not currently required
by the setup script.

## Codex CLI

Run `codex` from `/workspace`. No host Codex state, API key, or login token is
mounted automatically.

The hardened image installs root-owned requirements at
`/etc/codex/requirements.toml`. They limit Codex to read-only or workspace
permissions, require user-reviewed approvals, disable login shells and
unmanaged hooks, and reject `:danger-full-access`. The hardened Dev Container
also disables Docker's default seccomp profile so `bubblewrap` can create its
nested sandbox; the other container restrictions remain enabled.

## Security

Read [SECURITY.md](SECURITY.md) before using the hardened profile. In particular:

- keep valuable credentials and unrelated files outside `workspace/`;
- do not mount Windows drives, a Docker socket, SSH agents, or personal config
  directories into the agent container;
- treat network access and project dependency installation as code execution;
- review project changes before using trusted credentials or deployment tools;
- discard and recreate the outer VM after high-risk work.

## Local overrides

`mise.local.toml` and `mise.*.local.toml` are ignored by Git for personal tool
overrides. They are still readable by any process with workspace access, so they
must not contain secrets.
