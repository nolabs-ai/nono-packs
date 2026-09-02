---
name: nono-sandbox
description: Diagnose nono sandbox denials and choose safe remediation when the DeepSeek Harness (dsh) CLI agent is running inside nono.
---

# nono Sandbox

Use this skill when a `dsh` tool call (bash, fs read/write, subprocess, sandbox tool) fails with a permission, sandbox, filesystem, keychain, process, launch-service, or network denial.

## Core Rule

`dsh` runs its own internal permission layer (`dsh-sandbox-policy`, `dsh-bash-sandbox`, `dsh-user-approval`), but this pack boots it with `DSH_PERMISSION_MODE=danger-full-access` so that layer gets out of the way and defers entirely to nono. nono is the real enforcement boundary: it applies OS-level Landlock (Linux) / Seatbelt (macOS) restrictions before the process starts. If the OS sandbox denies access, nothing `dsh` does internally can grant it back.

## First Response

1. Identify the denied path, executable, URL, or capability from the tool output.
2. Check whether the action is inside the current project, `$HOME/.dsh` (profiles, credentials, sessions, attachments), or `$HOME/.agents` — the paths this profile grants.
3. If the action is outside those paths, explain the exact boundary and ask for a nono profile change only when the access is genuinely needed.
4. Prefer a narrower alternative before asking for a broader profile grant.

## Common Fixes

- Keep dsh state under `$HOME/.dsh` (profiles, `.credentials.yaml`, `.env`, `sessions/`, `attachments/`) — this profile already grants that path.
- Keep cross-agent skills/plugins under `$HOME/.agents`.
- Avoid writing API keys into project files; `dsh` reads credentials from `$HOME/.dsh/.credentials.yaml` or `$HOME/.dsh/.env`.
- When a task needs another project directory, treat that as a genuine profile-expansion request, not a workaround.

## dsh-Specific Notes

- Both `dsh --profile headless "<task>"` (one-shot, non-interactive) and `dsh web` (local browser UI) run cleanly under this pack's profile. For `web`, the whole server process is sandboxed, so a task prompted through the browser is still bound by nono — but the workspace directory picked in the UI must be inside what `nono run` was granted, unlike `headless` which implicitly uses `cwd`.
- Telemetry is disabled (`DSH_TELEMETRY_MODE=DISABLED`) by this pack, so no requests go to `harness-telemetry.deepseeksvc.com`. Don't suggest re-enabling it to work around a sandbox denial — it's unrelated.
- `dsh` is expected to already be installed by the user (e.g. via `npx @deepseek-ai/dsh`); this pack does not install or pin it. It was last verified against `dsh` `0.1.1-rc.2` — if a newer `dsh` release changes its home directory layout, permission-mode env var, or profile flags, sandbox denials may look different than described here.

## When to Ask the User

Ask the user before suggesting a profile expansion that grants access to:

- home-directory-wide writes
- credential stores
- browser profiles
- cloud-sync directories
- SSH/GPG material
- other repositories outside the current working directory
