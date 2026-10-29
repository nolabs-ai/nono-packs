<p align="center">
  <img src="./assets/logo.png" alt="nono codex" width="500" />
</p>

# nono codex

Sandbox profile and Codex plugin for running [OpenAI Codex CLI](https://developers.openai.com/codex) inside a [nono](https://nono.sh) security sandbox.

Install:

```
nono run --profile nolabs-ai/codex -- codex
```

If the pack isn't already installed, nono will prompt to pull it.

## Background server (daemon)

Recent Codex versions auto-start a detached shared backend (`codex app-server --managed-daemon` plus a `pid-update-loop` updater) and attach every TUI to it over a Unix socket. The daemon outlives the session, so a sandboxed `codex` that attaches to a daemon started outside nono would run its tools outside the sandbox, and a daemon started inside nono keeps that first session's grants after nono exits.

- **macOS:** the profile denies `~/.codex/app-server-control` and `/private/tmp/codex-daemon-*`, so a sandboxed Codex cannot attach to a daemon and falls back to its embedded, in-sandbox server.
- **Recommended on all platforms:** launch with `nono run --profile nolabs-ai/codex -- codex --no-daemon`.
- **Linux:** Landlock cannot deny a path inside the `~/.codex` grant, so the socket deny is not applied there yet; use `--no-daemon`. Stop any existing daemon with `codex app-server daemon stop` before sandboxed sessions.

## What's in the pack

- **`policy.json`** — sandbox profile (loaded as `--profile nolabs-ai/codex`). Grants `~/.codex`, `~/.agents`, `~/.config/nono/{profiles,packages}` (read-only), the OpenAI auth origin, and runtime groups for Node, Rust, Python, Nix.
- **`.codex-plugin/plugin.json`** — Codex plugin manifest, exposes the `nono-sandbox` skill.
- **`bin/nono-hook.sh`** — compatibility no-op for older installs that still have the previous `PostToolUse` hook entry.
- **`bin/nono-hook-session.sh`** — compatibility no-op for older installs that still have the previous `SessionStart` hook entry.
- **`skills/nono-sandbox/SKILL.md`** — skill describing how to diagnose and resolve sandbox denials.

## Activating sandbox guidance

`nono pull nolabs-ai/codex` writes the marketplace registration and the cache symlink, and merges a marked `nono` block into `~/.codex/config.toml` (`developer_instructions`, plus the marketplace/plugin entries) so Codex knows how to diagnose and remediate nono sandbox denials. The merge is scoped to a marked block, so your other `config.toml` settings are left untouched.

## Hook noise

Codex currently renders hook output in the TUI, even for hook entries marked `"silent": true`. This pack avoids that channel: fresh installs do not register Codex hooks. Sandbox-denial handling is provided by the `nono-sandbox` skill instead.

## Source

`https://github.com/nolabs-ai/nono-packs/tree/main/codex`

Published via Sigstore-signed releases triggered by tags matching `codex-v*`.
