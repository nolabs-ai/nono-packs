# opencode nono

`opencode` is a `nono` package for [opencode](https://github.com/opencode-ai/opencode).

It installs a sandbox profile, a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox — including credential injection, detach/attach session support, and denial diagnostics.

## What It Does

The pack provides:

- a sandbox profile (`policy.json`) granting the correct filesystem and network access, with credential injection routes for OpenAI, Anthropic, Gemini, GitHub, and GitLab
- a `session_hooks.before` hook (`bin/ensure-dirs.sh`) that creates opencode's state directories on the host before the sandbox is applied, so first-run doesn't fail when a directory the profile grants access to doesn't exist yet
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that injects nono sandbox context at session start, detects denial signatures in tool results, appends capability context and Option A/B remediation guidance, surfaces the network egress allowlist, and registers a `nono_status` tool
- a `nono-sandbox` skill that teaches the correct diagnostic flow for filesystem and network-egress denials, credential route setup, and detach/attach usage

The plugin supports both the OpenCode v1 and v2 plugin APIs from a single file: OpenCode 1.18.29+ calls its `server()` entrypoint, and OpenCode 2.x calls its `setup()` entrypoint. The v2 path registers the session `context` hook, a `nono_status` tool, and the `tool.execute.after` hook; the v1 path provides the equivalent legacy hooks. Removing the v1 support later is a single deletion of the `server()` binding and its helpers (see the v2 support section below).

## Behavior

When opencode is running inside a `nono` sandbox the installed plugin:

- no-ops if `NONO_CAP_FILE` is not set (not inside a nono session)
- injects sandbox context into the system prompt at session start so the model knows the rules before its first tool call
- surfaces the session ID (for `nono attach`) when running detached
- detects sandbox-denial signatures in tool results (`Operation not permitted`, `EACCES`, `EPERM`, `landlock`)
- appends the active capability set, credential route summary, and remediation instructions so the model always receives correct guidance
- reports the network egress allowlist (reachable hosts) with state-aware guidance for blocked, allowlisted, and unrestricted networking
- steers the model toward the two valid remediations: `--allow` restart or a persistent profile draft

This prevents common bad guidance such as retrying the same action, suggesting `chmod`, attempting network workarounds, or treating the failure as a macOS TCC issue.

## First-Run Directory Bootstrap

Landlock and Seatbelt can only grant a filesystem rule for a path that already exists. On a first run, a few state/cache/etc. directories don't exist yet, so the sandboxed opencode process fails immediately.

`policy.json` wires `bin/ensure-dirs.sh` as a `session_hooks.before` hook, which nono runs on the host before applying the sandbox to `mkdir -p` them first. The hook resolves through `$PACK_DIR` to the installed pack directory.

## Credential Injection

nono intercepts outbound HTTPS and injects API keys from its keychain — opencode never sees the raw secret. Routes are defined in the profile but **disabled by default**.

To enable a route, create an extending profile:

```json
{
  "extends": "opencode",
  "meta": { "name": "opencode-with-anthropic", "version": "1.0.0" },
  "network": { "credentials": ["anthropic"] }
}
```

Built-in route names: `openai`, `anthropic`, `gemini`, `github`, `gitlab`.

Store the corresponding secret in the nono keychain under the env-var-shaped account name (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.).

## Detach and Attach

Run opencode in a detached session that survives terminal disconnects:

```bash
nono run --profile nolabs-ai/opencode --detach -- opencode
```

Reattach from any terminal:

```bash
nono attach <session-id>
```

The `nono_status` tool (registered by the plugin) shows the active session ID and capability set.

## Install

```bash
nono pull nolabs-ai/opencode
```

Or let nono prompt you on first use:

```bash
nono run --profile nolabs-ai/opencode -- opencode
```

## Activation

After pulling, opencode reads the plugin from `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts` and the skill from `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/SKILL.md`. Both are symlinked from the pack store and update automatically on `nono pull`. If `XDG_CONFIG_HOME` is unset, the default `~/.config` applies.

The same symlink location works for both plugin generations: OpenCode 1.x discovers `$XDG_CONFIG_HOME/opencode/plugins/*.ts`, and OpenCode 2.x scans the same `plugins/` directory (it also accepts the `plugin/` name). The plugin is a self-contained TypeScript file with no external package dependencies, so it loads as a raw file in either runtime.

## OpenCode v2 support

The plugin ships one file that speaks both plugin APIs (see the v1-to-v2 migration guide at opencode.ai for the dual-export pattern):

- **OpenCode 2.x**: calls the default export's `setup(ctx)`, which registers a session `context` hook (system-context injection), a `nono_status` tool, and a `tool.execute.after` hook for denial diagnostics
- **OpenCode 1.18.29+**: calls the default export's `server()`, which returns the legacy v1 hooks (system transform, `nono_status` tool, `tool.execute.after`)

Older OpenCode 1.x releases without v1/v2 dual-export support are not covered by this single file; pin a previous pack version if you must support them. Dropping v1 support later means deleting the `server()` binding and the `v1Hooks`/`appendGuidance` helpers from `plugin/nono-sandbox.ts`.

## Removing

```bash
nono remove nolabs-ai/opencode
```

## Package Metadata

- Name: `opencode`
- Version: `0.2.0`
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
