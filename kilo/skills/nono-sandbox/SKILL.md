---
name: nono-sandbox
description: Diagnose nono sandbox denials and choose safe remediation when the Kilo Code CLI agent (kilo) is running inside nono.
---

# nono Sandbox

Use this skill when a `kilo` tool call (bash, fs read/write, subprocess, or network access) fails with a permission, sandbox, filesystem, or network denial.

## Core Rule

nono enforces access at the OS level — Landlock on Linux, Seatbelt on macOS — before `kilo` or any process it spawns ever starts. This is a hard boundary: nothing `kilo` does internally can grant back an access nono denied.

## First Response

1. Identify the denied path, executable, URL, or capability from the tool output.
2. Check whether the action is inside the current project or one of `$HOME/.config/kilo`, `$HOME/.local/share/kilo`, `$HOME/.local/state/kilo`, `$HOME/.cache/kilo/bin`, or `$HOME/kilo.json` — the paths this profile grants.
3. If the action is outside those paths, explain the exact boundary and ask for a nono profile change only when the access is genuinely needed.
4. Prefer a narrower alternative before asking for a broader profile grant.

## Common Fixes

- Keep kilo state under `$HOME/.config/kilo` (config), `$HOME/.local/share/kilo` (data/repos), `$HOME/.local/state/kilo` (logs/state), and `$HOME/.cache/kilo/bin` (downloaded binaries) — this profile already grants those paths.
- `$HOME/kilo.json` is explicitly allow-listed as a single file, not a directory grant — don't ask for a broader `$HOME` grant when only that file is needed.
- When a task needs another project directory, treat that as a genuine profile-expansion request, not a workaround.

## When to Ask the User

Ask the user before suggesting a profile expansion that grants access to:

- home-directory-wide writes
- credential stores
- browser profiles
- cloud-sync directories
- SSH/GPG material
- other repositories outside the current working directory
