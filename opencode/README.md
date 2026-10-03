# opencode nono

`opencode` is a `nono` package for [opencode](https://github.com/opencode-ai/opencode).

It installs sandbox profiles (one per OpenCode major version), a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox — including credential injection, detach/attach session support, and denial diagnostics.

## What It Does

The pack provides:

- a shared base profile (`profiles/opencode-base.json`) granting the correct filesystem and network access, with credential injection routes for OpenAI, Anthropic, Gemini, GitHub, and GitLab, extended by the `opencode` (v2, `profiles/opencode-v2.json`) and `opencode-v1` (`profiles/opencode-v1.json`) profiles
- a `session_hooks.before` hook (`bin/ensure-dirs.sh`) that creates opencode's state directories on the host before the sandbox is applied, so first-run doesn't fail when a directory the profile grants access to doesn't exist yet
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that injects nono sandbox context at session start, detects denial signatures in tool results, appends capability context and Option A/B remediation guidance, surfaces the network egress allowlist, and registers a `nono_status` tool
- a `nono-sandbox` skill that teaches the correct diagnostic flow for filesystem and network-egress denials, credential route setup, and detach/attach usage

The plugin supports both the OpenCode v1 and v2 plugin APIs from a single file: OpenCode 1.18.29+ calls its `server()` entrypoint, and OpenCode 2.x calls its `setup()` entrypoint. The v2 path registers the session `context` hook, a `nono_status` tool, and the `tool.execute.after` hook; the v1 path provides the equivalent legacy hooks. Removing the v1 support later is a single deletion of the `server()` binding and its helpers (see the v2 support section below).

## Profiles

The pack ships three profiles: a shared base, and one launch profile per OpenCode major version:

| Profile | OpenCode version | Launch command |
|---|---|---|
| `opencode` (pack default) | v2 | `nono run --profile nolabs-ai/opencode -- opencode --standalone` |
| `opencode-v1` | v1 | `nono run --profile nolabs-ai/opencode-v1 -- opencode` |
| `opencode-base` | — | shared foundation, extended by both; not a launch target (no `--standalone`) |

Profiles are referenced by qualified name: `--profile nolabs-ai/opencode` (v2, the pack default) or `--profile nolabs-ai/opencode-v1` (v1). `opencode` is the pack's default profile, so `--profile nolabs-ai/opencode` resolves to it directly.

`opencode-base` (`profiles/opencode-base.json`) carries the filesystem grants, network and credential routes, first-run directory hook, and rollback settings. `opencode` (`profiles/opencode-v2.json`) extends it and adds the v2 isolation settings (below). `opencode-v1` (`profiles/opencode-v1.json`) extends it with no additions, because the OpenCode v1 client, server, and tools run in one process for the default TUI launch — there is no external service to isolate.

Match the profile to the installed OpenCode major version: `opencode` for 2.x, `opencode-v1` for 1.x.

The first profile artifact in `package.json` determines the pack default, so the v2 profile stays listed first; do not reorder artifacts without re-checking `--profile nolabs-ai/opencode` resolution.

## OpenCode v2 Sandbox Isolation

OpenCode v2 normally connects clients to a shared background server. That server owns tool execution, plugins, permissions, and network requests, so sandboxing only the client would allow work to escape the active nono session.

The `opencode` profile contains that risk by:

- appending `--standalone` to the OpenCode command, which starts a private server inside the same nono sandbox as the client
- setting `OPENCODE_DISABLE_PROJECT_CONFIG=1`, which asks supported OpenCode discovery paths to skip project configuration and instructions
- setting `OPENCODE_TEST_HOME=$WORKDIR`, which reduces home and instruction discovery outside the active workspace without changing the real `HOME` inherited by shell tools

These environment variables are compatibility and defense-in-depth settings, not the security boundary. OpenCode v2 releases have not consistently honored `OPENCODE_DISABLE_PROJECT_CONFIG` across every configuration and component loader. nono remains the enforcement boundary: unexpected discovery attempts can reach only paths explicitly granted by the profile.

Supplying `--standalone` yourself is safe; OpenCode treats the duplicate boolean flag as idempotent. Supplying `--server` fails closed because OpenCode refuses to combine `--server` and `--standalone`.

This isolation mode has deliberate compatibility tradeoffs:

- global OpenCode configuration and the installed nono plugin remain available
- supported discovery paths skip project `opencode.json`/`opencode.jsonc` and project `AGENTS.md`, but affected OpenCode v2 releases may still discover some project configuration or components; treat workspace content as untrusted and rely on the sandbox for containment
- `OPENCODE_TEST_HOME` is an undocumented OpenCode compatibility mechanism, so pack releases must verify it against their supported OpenCode versions
- administrative subcommands that do not accept `--standalone`, such as `serve`, `auth`, or `acp`, may fail when launched through this profile; they are not supported agent launch paths

OpenCode and its runtime may probe parent or system directories during startup. A successful session can therefore end with denied-path notices for paths such as `$HOME`, `$HOME/.config`, `$NONO_CONFIG`, or `/System`. Do not grant those broad paths merely to silence the notices; add a narrower grant only when a required operation actually fails.

## OpenCode v1

`opencode-v1` is for OpenCode 1.x. For the default TUI launch the v1 client, server, and tools run in one process inside the sandbox, so no `--standalone` isolation is needed. That does not apply to v1 subcommands that connect out to an external server (for example `attach <url>`): there, tool execution happens on the external server, outside the sandbox, so they are not supported agent launch paths under this profile — the same rule as v2's `--server`.

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

`profiles/opencode-base.json` wires `bin/ensure-dirs.sh` as a `session_hooks.before` hook, which nono runs on the host before applying the sandbox to `mkdir -p` them first. The hook resolves through `$PACK_DIR` to the installed pack directory.

## Credential Injection

nono intercepts outbound HTTPS and injects API keys from its keychain — opencode never sees the raw secret. Routes are defined in the profile but **disabled by default**.

To enable a route, create an extending profile (extend `opencode-v1` when using the v1 profile):

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
nono run --profile nolabs-ai/opencode --detach -- opencode --standalone    # OpenCode v2
nono run --profile nolabs-ai/opencode-v1 --detach -- opencode              # OpenCode v1
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

All three profiles are installed automatically. Use `--profile nolabs-ai/opencode` (v2, the pack default) or `--profile nolabs-ai/opencode-v1` (v1) to select one at runtime.

Or let nono prompt you on first use:

```bash
nono run --profile nolabs-ai/opencode -- opencode --standalone       # OpenCode v2
nono run --profile nolabs-ai/opencode-v1 -- opencode                 # OpenCode v1
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
- Version: `0.3.0`
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
