# OpenCode v2.1+ nono pack

`opencode` is the `nono` pack for OpenCode v2.1.0 and later. It does not support OpenCode v1; use the separate `nolabs-ai/opencode-v1` pack for that major version. OpenCode v2.0.x is also not supported because it can fail during startup or instruction initialization when sandboxed discovery paths are inaccessible.

It installs a sandbox profile, a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox — including credential injection, detach/attach session support, and denial diagnostics.

## What It Does

The pack provides:

- a sandbox profile (`policy.json`) granting the correct filesystem and network access, with credential injection routes for OpenAI, Anthropic, Gemini, GitHub, and GitLab
- installation markers and a `session_hooks.before` hook (`bin/ensure-dirs.sh`) that create opencode's state directories on the host, so the paths exist when nono resolves their sandbox grants on first run
- a private temporary directory at `~/.cache/opencode/tmp`, exposed as both `TMPDIR` and `BUN_TMPDIR`, so OpenCode and Bun can create temporary files without granting access to the system-wide temporary directory
- a connect-only unix-socket subtree grant plus `OPENCODE_PTY_SOCKET_DIR` under that directory, so OpenCode's persistent PTY helper is reachable instead of falling back to spawn-per-command
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that injects nono sandbox context at session start, detects denial signatures in tool results, appends capability context and Option A/B remediation guidance, surfaces the network egress allowlist, and registers a `nono_status` tool
- a `nono-sandbox` skill that teaches the correct diagnostic flow for filesystem and network-egress denials, credential route setup, and detach/attach usage

The plugin targets the OpenCode v2 plugin API. Its `setup()` entrypoint registers the session `context` hook, a `nono_status` tool, and the `tool.execute.after` hook.

## OpenCode v2 Sandbox Isolation

OpenCode v2 normally connects clients to a shared background server. That server owns tool execution, plugins, permissions, and network requests, so sandboxing only the client can allow work to escape the active nono session.

For a fully contained interactive session, launch OpenCode with `--standalone`:

```bash
nono run --profile nolabs-ai/opencode -- opencode --standalone
```

This starts a private OpenCode server inside the same nono sandbox as the client. The pack deliberately does not append `--standalone` automatically because the flag is incompatible with workflows and administrative subcommands such as `serve`, `auth`, and `acp`.

If you omit `--standalone`, OpenCode may connect to an already-running server outside the sandbox. In that configuration, the profile constrains the client process but cannot guarantee that model tools, plugins, or network requests executed by the external server are contained.

OpenCode may probe inaccessible parent or system directories during project and instruction discovery. OpenCode v2.1.0 and later tolerate those denials, so project `opencode.json`/`opencode.jsonc`, `AGENTS.md`, plugins, and other components inside the granted workdir remain available. A successful session can still end with denied-path notices for paths such as `$HOME`, `$HOME/.config`, `$NONO_CONFIG`, or `/System`. Do not grant those broad paths merely to silence harmless discovery probes; add a narrower grant only when a required operation actually fails.

The OpenCode installation under `~/.opencode` is read-only because its `bin/` directory is on `PATH`; run OpenCode upgrades outside the sandbox. Runtime config, cache, data, and state remain writable under their XDG paths.

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

Landlock and Seatbelt can only grant a filesystem rule for a path that already exists. On a first run, a few state/cache/etc. directories may not exist yet, so the sandboxed opencode process would otherwise fail immediately.

The pack installs zero-byte marker files to create these directories before the profile is first resolved. `policy.json` also wires `bin/ensure-dirs.sh` as a `session_hooks.before` hook, which nono runs on the host before applying the sandbox. The hook resolves through `$PACK_DIR` to the installed pack directory.

## Persistent PTY Sockets

OpenCode's `shell` tool talks to its `opencode-pty` helper over a pathname `AF_UNIX` socket. On macOS a filesystem grant covers `bind(2)` but not `connect(2)` — unix-socket access is a separate capability layer — so without a grant the helper is unreachable and the shell tool silently falls back to spawning each command directly, after a ~5 s handshake timeout per call.

The pack points `OPENCODE_PTY_SOCKET_DIR` at `~/.cache/opencode/tmp/pty-sockets` and grants `filesystem.unix_socket_subtree` on that directory. The socket name is a fresh UUID per daemon, so the grant has to be a subtree rather than a single path. It is connect-only: the daemon binds the socket itself, and `bin/ensure-dirs.sh` creates the directory before the sandbox goes up.

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
nono run --profile nolabs-ai/opencode --detach -- opencode --standalone
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
nono run --profile nolabs-ai/opencode -- opencode --standalone
```

## Activation

After pulling, opencode reads the plugin from `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts` and the skill from `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/SKILL.md`. Both are symlinked from the pack store and update automatically on `nono pull`. If `XDG_CONFIG_HOME` is unset, the default `~/.config` applies.

OpenCode 2.x scans the `plugins/` directory (it also accepts the `plugin/` name). The plugin is a self-contained TypeScript file with no external package dependencies, so it loads as a raw file.

## Compatibility

This pack supports OpenCode v2 only and requires v2.1.0 or later. Use `--standalone` for interactive agent sessions that require the OpenCode server and client to remain inside the same nono sandbox. The pack documents but does not enforce this flag.

For OpenCode 1.x, use `nolabs-ai/opencode-v1`. Both packs install into OpenCode's standard plugin and skill locations, so remove the currently installed pack before switching between them.

## Removing

```bash
nono remove nolabs-ai/opencode
```

## Package Metadata

- Name: `opencode`
- Version: `0.4.1`
- OpenCode: `v2.1.0+` (v2 only)
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`