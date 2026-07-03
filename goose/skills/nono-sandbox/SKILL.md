---
name: nono-sandbox
description: Diagnose nono sandbox denials and choose safe remediation when Goose is running inside nono.
---

# nono Sandbox

Use this skill when a Goose command, extension, MCP server, hook, recipe, or shell action fails with a permission, sandbox, filesystem, keychain, process, launch-service, or network denial.

## Core Rule

Goose permissions and MCP approvals do not override nono. If the OS sandbox denies access, retrying with a Goose-level approval will not help unless the nono profile already permits that capability.

## First Response

1. Identify the denied path, executable, URL, or capability from the tool output.
2. Check whether the action is inside the current project, Goose's config/state/cache, or another path that the active profile allows.
3. If the action is outside the profile, explain the exact boundary and ask for a nono profile change only when the access is genuinely needed.
4. Prefer a narrower alternative before asking for a broader profile grant.

## Common Fixes

- Move temporary files into the project, `$TMPDIR`, or `/tmp/goose-$UID`.
- Keep Goose plugin files under `~/.agents/plugins`.
- Keep Goose config, extension state, and recipes under `~/.config/goose`, `~/.local/share/goose`, or `~/.local/state/goose`.
- Avoid writing credentials into project files. Use the provider's normal credential mechanism and the existing profile's keychain/config allowances.
- When an MCP server needs extra files, grant only the specific root it needs.

## When to Ask the User

Ask the user before suggesting a profile expansion that grants access to:

- home-directory-wide writes
- credential stores
- browser profiles
- cloud-sync directories
- SSH/GPG material
- other repositories outside the current working directory

## Useful Goose-Specific Checks

- Hooks receive JSON on stdin. If a hook fails, inspect the hook command, plugin root, and matched event.
- Open Plugins are discovered from `~/.agents/plugins/<plugin-name>` and project `.agents/plugins/<plugin-name>`.
- Plugin-provided skills are namespaced as `<plugin-name>:<skill-name>`.
- Goose config is YAML and extension configuration lives under the `extensions` key.
- Recipes and subrecipes can start repeatable workflows; make sure their required files and commands are covered by the active nono profile before running unattended.
