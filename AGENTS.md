# Project guidance

Before making architectural, container-runtime, or security-sensitive changes,
read `README.md` and `SECURITY.md`. Treat the repository implementation as the
source of truth and update both documents when behavior changes.

Preserve these design constraints:

- The disposable Linux VM or dedicated development host is the primary security
  boundary; containers provide reproducibility and defense in depth.
- Keep `.devcontainer/` and `control/` outside the agent-writable mount. Only
  `workspace/` should be exposed at `/workspace`.
- Do not add Docker socket mounts, SSH-agent forwarding, personal credentials,
  broad host filesystem mounts, or Windows-drive mounts.
- Keep the general and hardened-agent profiles distinct. Do not describe the
  general profile as safe for untrusted code.
- Use uv for Python and mise for non-Python project tools.
- Keep trusted setup and policy files in the image or wrapper, not in the
  agent-writable workspace.
- Prefer explicit, reproducible, reviewable configuration and committed
  lockfiles.
