# Security model

Devbox separates trusted container control files from a writable project and
provides two different convenience/security profiles. It does not make a Linux
container equivalent to a virtual machine.

## Intended deployment boundary

The recommended stack is:

```text
personal workstation
└── disposable Linux VM or dedicated development host
    └── Dev Container
        └── writable project workspace
```

The VM or dedicated host is the primary boundary protecting personal files,
credentials, and the workstation kernel. The Dev Container provides
reproducibility, limits accidental damage, and reduces what a compromised agent
can reach inside that isolated host.

Do not place personal SSH keys, cloud credentials, password-manager state,
browser profiles, Windows-drive mounts, or unrelated repositories in the VM used
for hostile or high-risk agent work.

## Trusted wrapper boundary

The wrapper's `.devcontainer/` and `control/` directories stay outside the
container. Only the sibling `workspace/` directory is bind-mounted at
`/workspace`.

This prevents a process inside the container from directly rewriting its next
Dev Container definition or the trusted setup script. The project workspace is
intentionally writable and must be treated as agent-controlled after untrusted
work.

The downstream example preserves this layout. Mounting the wrapper root instead
would expose the trusted configuration and invalidate this boundary.

## General profile

The general profile is a development convenience, not a sandbox for untrusted
code. It:

- runs as the non-root `vscode` user by default;
- grants that user passwordless `sudo`;
- keeps the container home and caches persistent;
- mounts only `workspace/` from the wrapper;
- does not declare a Docker-socket or SSH-agent mount.

Code running in this profile can become root inside the container and should be
treated as trusted.

## Hardened Agent profile

The hardened profile adds the following runtime controls through
`.devcontainer/agent/devcontainer.json`:

- non-root execution with no `sudo` package;
- read-only container root filesystem;
- all Linux capabilities dropped;
- `no-new-privileges` enabled;
- process limit of 1024, four-CPU limit, and a 6 GiB memory/swap limit;
- tmpfs-backed home, `/tmp`, and `/run` directories;
- no Docker socket or SSH-agent forwarding;
- non-interactive Git credential behavior and no usable global credential
  helper;
- `MISE_SAFE=1` for more restrictive handling of project mise configuration;
- immutable, root-owned Codex requirements;
- boundary checks before and after project setup on every container start.

The startup check verifies the non-root user, read-only root, zero effective
capabilities, missing Docker and SSH-agent sockets, managed Codex requirements,
Git credential helpers, and a short list of common leaked credential variables.
The environment-variable list is only a tripwire; it cannot prove that no
secret is present.

## Codex sandbox layering

Codex CLI uses `bubblewrap` as an inner Linux sandbox. The managed requirements
allow only read-only and workspace-scoped permission profiles, keep approvals
user-reviewed, disable unmanaged hooks and login shells, and reject
`:danger-full-access`.

To permit the nested sandbox, the hardened Dev Container sets
`seccomp=unconfined`. This disables Docker's default syscall filter for that
container. The read-only root, dropped capabilities, `no-new-privileges`,
resource limits, tmpfs mounts, and Codex policy remain active, but the change is
a deliberate reduction in defense in depth. The disposable VM remains the
backstop if the container or its nested sandbox is escaped.

## Project-controlled execution

The setup script reads declarations from the writable project and can execute
package-manager behavior controlled by that project. Current behavior is:

- lockfiles are enforced when present;
- missing Python, mise, or npm lockfiles are allowed and may be generated;
- project `mise.toml` is read in hardened mode under `MISE_SAFE=1`;
- npm and Python dependency installation may execute package-controlled code;
- `pre-commit` hooks may be installed in both profiles when configured.

Consequently, reconstruction is more reproducible when every ecosystem commits
its lockfile, but the hardened profile does not currently require lockfiles.

## Credentials and external authority

The Dev Container definitions do not explicitly inject API keys, Codex
credentials, a Docker socket, or an SSH agent. Supporting clients may still
offer credential-sharing conveniences in the general profile. The hardened
profile disables interactive Git credentials and verifies that no SSH-agent or
Docker socket is reachable. The image does not currently install the Docker CLI.

Keep credentials outside the wrapper and workspace. When external access is
necessary, prefer short-lived, least-privilege credentials delivered for one
reviewed operation. Never put live secrets in:

- repository files or example environment files;
- Dockerfile `ENV` instructions or build arguments;
- Dev Container `containerEnv` or `remoteEnv` values;
- mise configuration;
- image layers or committed shell scripts.

The container has unrestricted network egress for model APIs and package
registries. It cannot reliably distinguish legitimate traffic from
exfiltration. Network approval and credential brokering must be enforced outside
the container when required.

## Published image limitations

The current GitHub Actions workflow publishes only the Linux amd64 **general**
image. The GHCR image contains filesystem contents but not every runtime option
from a Dev Container definition.

In particular, the hardened profile's read-only root, capability drops,
resource limits, tmpfs mounts, and trusted `workspace/` selection depend on the
external Dev Container configuration. Starting the `agent` Docker target without
those options does not produce the documented hardened environment.

## Residual risks

- Containers share the host kernel and remain exposed to kernel and container
  runtime vulnerabilities.
- The writable workspace can contain malicious source, dependencies, hooks, or
  generated files.
- VS Code extensions and connected tooling can read files available inside the
  container.
- Network egress is unrestricted.
- The general profile has passwordless root inside the container.
- The agent home is ephemeral, but the workspace persists until reviewed or
  discarded.
- A user with control of the host Docker daemon can bypass container runtime
  restrictions.

For high-risk work, use a disposable VM containing no valuable data, review the
workspace diff outside the agent's authority, and destroy the VM after the task.
