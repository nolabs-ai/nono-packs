# nono goose

Sandbox profile and Goose Open Plugin for running [Goose](https://goose-docs.ai/) inside a [nono](https://nono.sh) security sandbox.

Install:

```bash
nono run --profile nolabs-ai/goose -- goose
```

If the pack is not already installed, nono will prompt to pull it.

## What's in the pack

- **`policy.json`** - sandbox profile loaded as `--profile nolabs-ai/goose`. Grants Goose config/cache/state, `~/.agents` for plugins and skills, standard Node/Rust/Python/Nix runtime groups, common provider auth origins, and read access to nono packages/profiles.
- **`plugin.json`** - Goose Open Plugin manifest. Goose discovers this pack from `~/.agents/plugins/nono`.
- **`hooks/hooks.json`** - Goose hook wiring for shell and tool-failure diagnostics.
- **`bin/nono-hook.sh`** - hook command that detects likely sandbox-denial output and prints nono-specific remediation guidance.
- **`skills/nono-sandbox/SKILL.md`** - Goose skill, symlinked to `~/.agents/skills/nono-sandbox` so Goose's Skills extension discovers it.

## Sandbox awareness

The profile sets `GOOSE_MOIM_MESSAGE_TEXT` in the sandboxed environment. Goose's built-in "Top Of Mind" extension (on by default) adds that text to every turn, so the model knows it is running under nono. It then treats `Operation not permitted` as a sandbox boundary and doesn't misread it as a restriction it made up. The variable is only set inside `nono run`, so a Goose session started without nono doesn't get the notice.

The notice replaces any `GOOSE_MOIM_MESSAGE_TEXT` you set on the host. `GOOSE_MOIM_MESSAGE_FILE` isn't touched, so put your own top-of-mind content there.
