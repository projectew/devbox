# Devbox security model

The general container is a convenience boundary, not a sandbox for untrusted
agents. It includes passwordless sudo. It does **not** mount a Docker socket by
default because control of the host Docker daemon is effectively root-level
authority over the host.

The hardened agent variant adds a useful outer containment layer:

- non-root user with no sudo;
- read-only container root filesystem;
- all Linux capabilities dropped and `no-new-privileges` enabled;
- Docker's outer seccomp filter disabled so Codex can create its nested
  `bubblewrap` sandbox;
- only this project is bind-mounted from the host;
- ephemeral home, cache, and temporary directories;
- no Docker socket, SSH agent, global Git configuration, or credential prompt;
- project mise configuration ignored in favor of the immutable system copy;
- immutable Codex requirements that prohibit `:danger-full-access`, agent
  self-approval, unmanaged hooks, and login shells;
- a startup check for common accidental secret environment variables.

## Boundaries that remain

Containers share the host kernel. The project workspace is writable because an
agent must edit it. Network egress is enabled because hosted model APIs and
package registries require it. VS Code and an agent process can read every file
inside the workspace. The environment cannot reliably distinguish a legitimate
API request from exfiltration to the same destination.

Codex CLI includes `bubblewrap` for its inner Linux sandbox. The hardened image
constrains that sandbox to read-only or workspace-scoped permission profiles;
the outer container remains the backstop. Disabling Docker's default seccomp
filter is a deliberate nested-sandbox tradeoff: bubblewrap needs namespace
syscalls that Docker otherwise blocks, while the container still drops every
capability and sets `no-new-privileges`. Require approval for commands outside
the workspace, network access, credential access, and destructive operations.
Prefer short-lived, least-privilege credentials delivered through a broker or
explicit one-shot command—not long-lived secrets in environment variables.

For actively hostile code or a high-impact credential context, use a disposable
VM or dedicated WSL distribution as the outer boundary. A Dev Container alone
is not a strong enough isolation boundary for hostile kernel-level workloads.

## Docker access

The Docker CLI is present in both images, but no daemon is reachable by default.
For ordinary work, prefer a rootless remote daemon over SSH or TLS and set
`DOCKER_HOST` for that session. Mounting `/var/run/docker.sock` is an explicit
trust decision and must never be added to the hardened variant.

## Secret handling checklist

1. Keep secrets out of the repository, image layers, build arguments, and
   `devcontainer.json`.
2. Do not use VS Code `remoteEnv` with `${localEnv:SECRET}` in the agent variant.
3. Review extension permissions and install only extensions you trust.
4. Recreate the hardened container after untrusted work; its home is ephemeral.
5. Review the diff before committing or running generated code with credentials.
