<p align="center">
  <img src="./assets/logo.png" alt="nono deepseek" width="500" />
</p>

# nono deepseek

Sandbox profile and dsh-native skill for running the [DeepSeek Harness](https://deepseek-harness.github.io/deepseek-harness/) CLI agent (`dsh`) inside a [nono](https://nono.sh) security sandbox.

This pack assumes `dsh` is already installed (e.g. via `npx @deepseek-ai/dsh`). It does not install or pin `dsh` itself — it was last verified against `dsh` `0.1.1-rc.2`. If a newer `dsh` release changes its home directory layout (`$DSH_HOME`, default `~/.dsh`), its permission-mode env var, or its profile/CLI flags, this pack's `policy.json` and skill may need updating.

Install:

```bash
nono run --profile nolabs-ai/deepseek -- dsh --profile headless "<task>"
```

If the pack is not already installed, nono will prompt to pull it.

## Verified working: both `headless` and `web`

Both of dsh's CLI-launched profiles run cleanly under this pack's sandbox with no extra flags:

```bash
# One-shot, non-interactive
nono run --profile nolabs-ai/deepseek -- dsh --profile headless "<task>"

# Local web UI + browser session
nono run --profile nolabs-ai/deepseek -- dsh web
```

For `web`, nono sandboxes the whole `dsh` server process (and everything it spawns — bash/fs tools included), not just the CLI entrypoint, so prompting it through the browser still runs under the same kernel-level restrictions. The one thing to watch: the web UI lets you pick *any* directory as its workspace, unlike `headless` which implicitly uses `cwd` — point it at the same directory (or a subdirectory) you approved when `nono run` prompted to share the working directory, or it'll get sandbox-denied trying to touch a folder outside that grant.

## Recommended dsh environment

`dsh` ships its own internal permission/approval layer on top of the actual OS sandbox. Since nono already enforces the real boundary at the kernel level (Landlock/Seatbelt), set these before invoking `dsh` so it doesn't double-sandbox or nag with its own approval prompts:

```bash
export DSH_PERMISSION_MODE=danger-full-access
export DSH_TELEMETRY_MODE=DISABLED
```

- `DSH_PERMISSION_MODE=danger-full-access` disables dsh's own sandbox/approval layer (`dsh-sandbox-policy`, `dsh-bash-sandbox`, `dsh-user-approval`) since nono is the actual enforcement layer.
- `DSH_TELEMETRY_MODE=DISABLED` stops dsh's default telemetry export to `harness-telemetry.deepseeksvc.com`. This pack's profile does not allowlist that origin.

## What's in the pack

- **`policy.json`** — sandbox profile loaded as `--profile nolabs-ai/deepseek`. Grants `$HOME/.dsh` (dsh's profiles, credentials, sessions, attachments), `$HOME/.agents` (cross-agent skills/plugins convention), standard Node/Rust/Python/Nix runtime groups, and read access to nono packages/profiles.
- **`skills/nono-sandbox/SKILL.md`** — dsh-native skill, installed to `$HOME/.dsh/skills/nono-sandbox/SKILL.md` (a dsh skill root), teaching the agent how to diagnose and respond to nono sandbox denials instead of retrying or working around them.

## Notes

- `--profile headless` is for CLI-driven, non-interactive use (answer one task, print the result, exit); `--profile web` boots dsh's local browser UI and server. Both are covered by this pack's profile.
- Auth: dsh reads provider credentials from `$HOME/.dsh/.credentials.yaml` (writable) or `$HOME/.dsh/.env` (read-only fallback), both covered by this profile's `$HOME/.dsh` grant.
