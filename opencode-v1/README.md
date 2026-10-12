# OpenCode v1 nono pack

`opencode-v1` is the `nono` pack for OpenCode 1.x. It is based on the last known-working v1 configuration from `opencode-v0.2.0` and intentionally does not append the OpenCode v2-only `--standalone` flag.

Use the separate `opencode` pack for OpenCode v2.

## What It Does

The pack provides:

- a sandbox profile (`policy.json`) granting OpenCode's state directories and common runtime dependencies
- credential injection routes for OpenAI, Anthropic, Gemini, GitHub, and GitLab, disabled by default
- a host-side first-run hook (`bin/ensure-dirs.sh`) that creates OpenCode state directories before the sandbox is applied
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that injects sandbox context, reports denial diagnostics, and registers the `nono_status` tool
- a `nono-sandbox` skill with filesystem and network denial guidance

The default OpenCode v1 TUI keeps its client, tool execution, and plugin runtime in the sandboxed process, so this profile launches plain `opencode`. Do not add `--standalone`; that flag belongs to OpenCode v2.

## Install and Run

```bash
nono pull nolabs-ai/opencode-v1
nono run --profile nolabs-ai/opencode-v1 -- opencode
```

For a detached session:

```bash
nono run --profile nolabs-ai/opencode-v1 --detach -- opencode
nono attach <session-id>
```

The `nono_status` tool shows the active session ID, filesystem capabilities, network policy, and credential routes.

## Compatibility

This pack targets OpenCode 1.x, including the 1.18.31 configuration reported working with the original `opencode` pack at version `0.2.0`. OpenCode 2.x is not supported by this pack.

The v1 and v2 packs wire the same OpenCode plugin and skill locations. Install the pack matching the OpenCode major version on the machine; remove the other pack before switching:

```bash
nono remove nolabs-ai/opencode
nono pull nolabs-ai/opencode-v1
```

To switch back to v2:

```bash
nono remove nolabs-ai/opencode-v1
nono pull nolabs-ai/opencode
```

## First-Run Directory Bootstrap

Landlock and Seatbelt can grant a filesystem rule only for a path that already exists. The profile runs `bin/ensure-dirs.sh` on the host before applying the sandbox so OpenCode's state, cache, config, and data directories exist on first launch.

## Credential Injection

nono can intercept outbound HTTPS and inject provider credentials without exposing the raw secret to OpenCode. Routes are defined but disabled by default.

To enable one, create an extending profile:

```json
{
  "extends": "nolabs-ai/opencode-v1",
  "meta": { "name": "opencode-v1-with-anthropic", "version": "1.0.0" },
  "network": { "credentials": ["anthropic"] }
}
```

Built-in route names are `openai`, `anthropic`, `gemini`, `github`, and `gitlab`.

## Activation

After installation, OpenCode reads:

- `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts`
- `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/SKILL.md`

Both are symlinked from the pack store and update on `nono pull`. If `XDG_CONFIG_HOME` is unset, `~/.config` is used.

## Remove

```bash
nono remove nolabs-ai/opencode-v1
```

## Package Metadata

- Name: `opencode-v1`
- Version: `0.1.0`
- OpenCode major version: `1.x`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
