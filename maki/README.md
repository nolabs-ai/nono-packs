# maki nono

`maki` is a `nono` package for the [Maki CLI agent](https://github.com/tontinton/maki).

It installs a nono profile and a packaged skill that make Maki behave correctly when it is running inside a `nono` security sandbox.

## Quick start

```bash
# Install the pack
nono pull nolabs-ai/maki

# Run Maki inside the sandbox
nono run --profile nolabs-ai/maki -- maki --yolo
```

Drop `--yolo` to keep Maki's own approval prompts layered on top of the sandbox. Since nono is the enforcement layer, `--yolo` avoids double-gating every action with Maki's prompts; the OS sandbox still constrains everything Maki does.

## What It Does

This pack is focused on one problem: when Maki hits a sandbox boundary, it should stop guessing and explain the real fix.

The pack provides:

- a nono profile (`policy.json`) granting Maki's XDG state directories, common runtimes, and network access
- a `nono-sandbox` skill installed to Maki's global skill directory (`~/.config/maki/skills/nono-sandbox/`), which teaches the correct diagnostic flow: run `nono why --self` on confirmed denials, offer a quick-fix restart or a profile draft, and never suggest workarounds
- a `bin/ensure-dirs.sh` session hook that creates Maki's directories before the sandbox goes up

## Sandbox Preparation

Landlock and Seatbelt can only attach a rule to a path that already exists, and a grant for a missing path is silently skipped. Maki creates its own directories lazily at runtime — but that happens *inside* the sandbox, after the capability set is already fixed. On a fresh machine every Maki state grant would be dropped.

`bin/ensure-dirs.sh` runs as a `session_hooks.before` script, on the host and before the sandbox boundary goes up, and creates Maki's five XDG directories first.

It deliberately does **not** create `~/.maki`: that is Maki's legacy layout, and Maki collapses its entire directory structure onto it the moment the directory exists, which would bypass the XDG paths this profile grants. `~/.maki` is only granted (read/write) so sessions still work on machines where the legacy layout predates the sandbox.

## State Layout

| Directory | Contents |
|-----------|----------|
| `~/.config/maki` | configuration, global skills |
| `~/.local/share/maki` | installed maki packs (`site/`) |
| `~/.local/state/maki` | `auth/`, `sessions/`, `projects/`, `plans/` |
| `~/.local/logs/maki` | log files |
| `~/.cache/maki` | model catalogs (`models-dev-catalog.json`) |

## Included Artifacts

The pack currently ships:

- `policy.json` (installed as the `maki` profile)
- `skills/nono-sandbox/SKILL.md`
- `bin/ensure-dirs.sh`
- `wiring/profile-drafts-dir-marker`

These artifacts are declared in [`package.json`](./package.json).

## Package Metadata

- Name: `maki`
- Maki compatibility: `v0.6.5` (other versions are not yet verified)
- Minimum nono version: `v0.75.0`
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
