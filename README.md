<div align="center">

# nono packs

**Sandbox profiles, plugins, and skills for your AI agents.**

Run your agent inside [nono](https://nono.sh) with the runtime configuration
and guidance it needs to work within the sandbox.

[Quick start](#quick-start) · [Available packs](#available-packs) · [Contributing](#contributing) · [nono docs](https://nono.sh/docs)

[![Latest nono release](https://img.shields.io/github/v/release/nolabs-ai/nono?label=nono&sort=date)](https://github.com/nolabs-ai/nono/releases/latest)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](./LICENSE)
[![Pack smoke tests](https://github.com/nolabs-ai/nono-packs/actions/workflows/pack-smoke-test.yml/badge.svg)](https://github.com/nolabs-ai/nono-packs/actions/workflows/pack-smoke-test.yml)

</div>

## Quick start

Install [nono](https://nono.sh/docs) and your agent CLI, then pull its pack and launch it with the matching profile. For Claude Code:

```bash
nono pull nolabs-ai/claude
nono run --profile nolabs-ai/claude -- claude
```

Choose another agent from the catalog below for its setup and launch instructions.
In particular, [Codex](./codex/README.md) needs `--no-daemon` alongside its sandbox and approval flags, and [OpenCode v2](./opencode/README.md) uses `--standalone` to keep tool execution inside the nono sandbox.

Packs configure an existing agent installation. Each pack's `package.json` declares its supported platforms and minimum nono version.

## Available packs

| Pack | Agent | Integration |
| --- | --- | --- |
| [`antigravity`](./antigravity/README.md) | Antigravity CLI (`agy`) | Profile, plugin, diagnostic hook, and skill |
| [`claude`](./claude/README.md) | Claude Code | Profile, plugin, diagnostic hooks, and skill |
| [`claude-autoresearch`](./claude-autoresearch/README.md) | Claude Code + autoresearch | GPU-enabled profile and plugin for autonomous ML workloads |
| [`codex`](./codex/README.md) | OpenAI Codex CLI | Profile, plugin, and sandbox guidance |
| [`copilot-cli`](./copilot-cli/README.md) | GitHub Copilot CLI | Authentication-specific profiles, plugin, hooks, and skill |
| [`deepseek`](./deepseek/README.md) | DeepSeek Harness (`dsh`) | Profile and skill |
| [`goose`](./goose/README.md) | Goose CLI | Profile, Open Plugin, diagnostic hook, and skill |
| [`hermes`](./hermes/README.md) | Hermes Agent | Profile, plugin, skill, and configuration defaults |
| [`kilo`](./kilo/README.md) | Kilo Code CLI | Profile and skill |
| [`kimchi`](./kimchi/README.md) | Kimchi Coding Agent | Profile, extension, and sandbox guidance |
| [`maki`](./maki/README.md) | Maki CLI | Profile and skill |
| [`mistral-vibe`](./mistral-vibe/README.md) | Mistral Vibe | Profile, diagnostic hook, and skill |
| [`omp`](./omp/README.md) | Oh My Pi | Profile and extension with diagnostic hooks |
| [`openclaw`](./openclaw/README.md) | OpenClaw | Profile, plugins, hooks, and skill for multiple instances |
| [`opencode`](./opencode/README.md) | OpenCode v2 | Profile, plugin, skill, and standalone server support |
| [`opencode-v1`](./opencode-v1/README.md) | OpenCode v1 | Profile, plugin, and skill for v1 installations |
| [`pi`](./pi/README.md) | Pi Coding Agent | Profile, extension, and skill |

All packs declare macOS and Linux support except **`copilot-cli` (macOS only)** and **`claude-autoresearch` (Linux only)**. See each pack's README for authentication, runtime requirements, and profile details.

## What a pack adds

nono enforces the sandbox at the OS level. Packs supply the agent-specific configuration and guidance:

- **Profiles** grant access to the agent's runtime paths and configure its sandbox settings.
- **Plugins and hooks** connect the agent to sandbox diagnostics where its runtime supports them.
- **Skills and instructions** teach the agent how to inspect denied access and explain the permissions it needs.
- **Install wiring** registers plugins, links skills, and applies configuration to the target runtime.

These integrations are versioned and distributed independently of the [nono runtime](https://github.com/nolabs-ai/nono).

## Contributing

Each top-level pack directory contains a `package.json` manifest and its installable files. Start with the pack you want to change, or use an existing integration for the same kind of runtime as a reference.

<details>
<summary><strong>Pack structure and manifest reference</strong></summary>

A typical pack looks like this; the files depend on the target runtime:

```text
<pack>/
├── package.json     # Metadata, artifacts, and install wiring
├── README.md        # Setup, usage, and runtime requirements
├── policy.json      # Sandbox profile (some packs ship multiple profiles)
├── skills/          # Agent guidance
├── hooks/           # Runtime hook definitions
├── bin/             # Setup and diagnostic helpers
└── wiring/          # Configuration fragments and install assets
```

Manifests declare `schema_version`, `name`, `version`, `description`, `license`, `platforms`, `min_nono_version`, and `artifacts`. Each artifact identifies its type and source path; profile artifacts also declare an `install_as` name and can provide aliases. The `wiring` array defines how the pack connects to the agent's configuration.

See [`claude/package.json`](./claude/package.json) for a plugin and hooks example, or [`deepseek/package.json`](./deepseek/package.json) for a profile and skill example.

</details>

### Validation and releases

The [pack smoke test workflow](./.github/workflows/pack-smoke-test.yml) checks changed packs on macOS and Linux, covering profile resolution, validation, and sandbox execution.

For maintainers, [`scripts/release.sh`](./scripts/release.sh) creates and pushes a `<pack>-v<version>` tag to trigger the matching publish workflow. Those workflows sign pack artifacts with Sigstore and publish them to the nono registry. Use `--dry-run` to preview a release.

## License

[Apache 2.0](./LICENSE).
