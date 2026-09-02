# omp

`omp` is a nono package for [Oh My Pi](https://github.com/can1357/oh-my-pi) (OMP), the pi-coding-agent fork. It provides a secure sandbox for running OMP and any tools it invokes, with built-in protections for your API keys, system credentials, and filesystem. Use it to safely run OMP on your machine and sleep a little easier knowing that even if OMP or a tool it runs goes rogue, your secrets and system are protected by nono's multi-layered security model.

## What this pack provides

- **Sandbox profile** (`omp`) — filesystem, network, and runtime toolchain grants so OMP can operate inside nono
- **Sandbox awareness extension** — hooks into OMP's event system to detect permission denials and inject diagnostic guidance
- **Sandbox skill** — detailed diagnosis and remediation documentation reachable via `skill://nono-sandbox`

## Install

Pull the package first, then create a custom profile before running. This avoids the interactive grants prompt that appears when nono encounters paths the base profile doesn't cover:

**Step 1 — pull the package:**

```bash
nono pull nolabs-ai/omp
```

**Step 2 — create a custom profile:**

```bash
nono profile init omp --extends nolabs-ai/omp --full
```

A custom profile is also where you add credential routes, API keys, tokens, extra filesystem grants, and any other customizations — see the sections below. It's worth running this step, even if you don't think you'll need any custom grants or credentials, just to avoid the grants prompt later.

```bash
nono run --profile omp --allow-cwd -- omp
```

### First-run grants prompt

If you run nono before creating a custom profile, nono may detect paths that OMP needs but that the base profile doesn't cover — your shell config, a tool on a non-standard path, etc. When this happens you'll see a prompt like:

```
Sandbox denial: 3 paths blocked.
  ~/.config/gh (read)
  ~/dev/dotfiles/zsh (read)
  /usr/local/sbin (read)

[nono] Choose suppress to keep denying all listed paths and stop future save suggestions.
Save suggestions to a user profile? [g] grant / [s] suppress / [Enter] skip:
```

- **`g` (grant)** — saves the extra path grants to a user profile. Use the same name you plan to use for your custom profile (e.g. `omp`) so both sets of grants live in one place.
- **`s` (suppress)** — stops nono from suggesting these paths in future. The paths remain denied.
- **Enter (skip)** — skips saving for now. You'll be prompted again next time.

The cleanest approach is to skip (`Enter`) and add any extra paths manually to your child profile's `filesystem.read` or `filesystem.allow` block.

## What the profile grants

| Resource | Access | Reason |
|----------|--------|--------|
| `~/.omp/` | read/write | OMP config, sessions, plugins, logs, extensions, skills |
| `$NONO_CONFIG/profile-drafts/` | read/write | User-authored profile extensions |
| `$NONO_PACKAGES`, `$NONO_CONFIG/profiles` | read | Registry-managed pack files |
| `~/.agents/skills`, `~/.codex/skills`, `~/.config/opencode/skills`, `~/.claude/plugins/cache` | read | OMP's cross-agent skill discovery |
| `~/.codex/config.toml`, `~/.claude/settings.json`, `~/.claude/plugins/installed_plugins.json`, `~/.claude.json` | read | OMP's session-import features (`--from-claude`, `--from-codex`) probe these on startup |
| `~/Library/Spelling` (macOS) | read | macOS's native spellchecker, used by OMP's TUI text input |
| Network | all outbound | Provider APIs, MCP servers, package registries |

The profile is intentionally minimal beyond that — no credential routes are enabled by default. Extend with `"extends": "nolabs-ai/omp"` in a profile draft for tighter controls.

## Custom profiles

To create your own custom profile that extends the base `nolabs-ai/omp` profile, use the `nono profile init` command with the `--extends` flag. This allows you to inherit from the base profile while customizing specific aspects such as credential routes and network filtering.

Hopefully you already have a `~/.config/nono/profile/omp.json` file from the earlier step (if not go back and run `nono profile init`); you can now edit that file to add credential routes, API keys, tokens, extra filesystem grants, and any other customizations — see the sections below. When you're happy with the profile, create a repo, push the code and add it to this registry — you can then pull your custom profile from any machine (`nono pull johndoe/<your-profile>`) and run OMP just how you like with the same profile and settings everywhere.

## Sandbox awareness

When OMP starts inside nono (`NONO_CAP_FILE` is set), the extension:

1. Injects sandbox context into the system prompt so the agent knows it's sandboxed
2. Detects permission denials in tool results and appends diagnostic guidance
3. Registers a `/nono-status` command to inspect the current sandbox

When a tool fails with `Operation not permitted`, `Permission denied`, `EACCES`, `EPERM`, `landlock`, or `sandbox denied`, the extension attaches remediation steps directly to the tool output.

## Status indicator

When running inside nono, the extension shows a "nono sandbox" entry above the status panel so the agent and user are always aware of the sandbox boundary. This is on by default (`OMP_NONO_STATUS_INDICATOR=true`, injected by the profile via `environment.set_vars`).

To disable it, edit the installed profile (`~/.config/nono/profiles/omp.json`, or `omp-dev.json` for local dev installs) and set the variable to `"false"`:

```json
"environment": {
  "set_vars": { "OMP_NONO_STATUS_INDICATOR": "false" }
}
```

Denial detection and system-prompt context injection remain active either way; only the status entry is suppressed.

## Credential Protection

nono protects API keys using a **phantom credential** model. Rather than passing your real key into the sandbox, nono generates a short-lived random token and injects that into OMP instead. When OMP makes an outbound API call carrying the phantom token, nono's proxy intercepts the request, validates the token, fetches the real key from your system keystore (macOS Keychain, Linux Secret Service, 1Password, etc.), and swaps it in before the request leaves the machine. The real key is never visible to the sandboxed process, so even if OMP or a tool it runs were compromised, an attacker would obtain only the useless phantom — not the credential itself.

> **Do not store API keys in `~/.omp`.** OMP's own credential store (`~/.omp/agent/agent.db`) is inside the sandbox because OMP must read it; a real key there is visible to the sandboxed process and bypasses nono's phantom credential protection. Keep keys in nono's keychain (or a URI ref source) and let nono inject them.

### Built-in providers

The base `omp` profile does not enable provider credentials by default. This avoids warnings for unused providers from becoming part of the session boundary.

The following providers are built in and ready to use. How you store the key depends on the route — some read from the system keychain, others read from an environment variable in nono's own process:

| Route Name  | Provider   | Storage method | Key name / account  |
|-------------|------------|-----------------|----------------------|
| `openai`    | OpenAI     | nono keychain   | `OPENAI_API_KEY`    |
| `anthropic` | Anthropic  | nono keychain   | `ANTHROPIC_API_KEY` |
| `gemini`    | Gemini     | nono keychain   | `GOOGLE_API_KEY`    |
| `opencode`  | opencode   | nono keychain   | `OPENCODE_API_KEY`  |
| `github`    | GitHub     | nono keychain   | `GITHUB_TOKEN`      |
| `gitlab`    | GitLab     | nono keychain   | `GITLAB_TOKEN`      |

Store each key in the nono keychain service using the exact account name shown in the table above. Then add the route name to the `credentials` array in your child profile's `network` block to activate it:

```json
  "network": {
    "block": false,
    "allow_domain": [],
    "credentials": ["opencode"],
    "open_port": [],
    "listen_port": [],
    "custom_credentials": {}
  },
```

The proxy will handle the rest — when OMP makes a request to an API endpoint matching the route, nono swaps in the real key from the keychain before forwarding the request upstream.

You can enable multiple providers at once:

```json
"credentials": ["anthropic", "opencode"]
```

If you want to use a provider that isn't in the built-in list, add it with `custom_credentials` — see the [Custom providers](#custom-providers) section below for field details and examples.

#### Step 1 — store the key

**For keychain-backed routes** (`openai`, `anthropic`, `gemini`, `opencode`, `github`, `gitlab`):

##### macOS Keychain:

You can add the key with `security` or the Keychain UI. The `-a` flag sets the account name, which is how nono looks up the key at runtime. The `-s` flag sets the service, which nono uses to group related credentials together in the UI.

```bash
security add-generic-password -U -s "nono" -a "OPENAI_API_KEY" -w
security add-generic-password -U -s "nono" -a "ANTHROPIC_API_KEY" -w
security add-generic-password -U -s "nono" -a "GOOGLE_API_KEY" -w
security add-generic-password -U -s "nono" -a "OPENCODE_API_KEY" -w
security add-generic-password -U -s "nono" -a "GITHUB_TOKEN" -w
security add-generic-password -U -s "nono" -a "GITLAB_TOKEN" -w
```

Keep `-w` last so macOS prompts for the value instead of recording it in shell history.

##### Linux Secret Service:

```bash
secret-tool store --label="nono: OPENCODE_API_KEY" \
  service nono username OPENCODE_API_KEY target default
```

On Linux this requires a running Secret Service provider such as GNOME Keyring or KWallet. In SSH-only or headless environments, check the nono credential docs before choosing a storage backend.

###### Alternative storage methods

If your keys live in 1Password, a file, or an environment variable, you can override any built-in route using `custom_credentials` — see the [Custom providers](#custom-providers) section below for field details and examples.

For the full credential URI ref model (`op://`, `apple-password://`, `file://`, `env://`), see:

- https://nono.sh/docs/cli/features/credential-injection

#### Step 2 — run OMP with the child profile

```bash
nono run --profile omp -- omp
```

### Custom providers

If the provider you need isn't in the built-in list, you can add it with `custom_credentials`. The same phantom-token swap mechanism applies — you define the upstream URL, the keychain account to use, and optionally which API endpoints are permitted.

This example adds [OpenRouter](https://openrouter.ai) — an OpenAI-compatible model-routing API that authenticates with `Authorization: Bearer <key>`.

Store the key in your system keyring under the account name you'll reference in the profile (`OPENROUTER_API_KEY` here):

```bash
security add-generic-password -U -s "nono" -a "OPENROUTER_API_KEY" -w
```

Then open your child profile and update the `network` block:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["openrouter"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {
    "openrouter": {
      "upstream": "https://openrouter.ai/api/v1",
      "credential_key": "OPENROUTER_API_KEY",
      "env_var": "OPENROUTER_API_KEY"
    }
  }
}
```

The map key (`"openrouter"`) is the route name. **It must also appear in the `credentials` array** — nono only activates routes explicitly listed there. `inject_header` and `credential_format` are omitted because the defaults (`"Authorization"` and `"Bearer {}"`) already match what OpenRouter expects.

For tighter control you can add `endpoint_rules` — a list of `{"method", "path"}` pairs that act as an L7 allow-list. When non-empty, the proxy rejects any request that doesn't match, even with a valid phantom token. Omit it, as above, to allow all paths under the route.

Run OMP with your child profile:

```bash
nono run --profile omp -- omp
```

## Audit Logging

Every nono session produces an append-only audit log recording what OMP did: the command and arguments (with secrets redacted), start/end timestamps, exit code, capability decisions, network events, and the filesystem paths it touched. Logs are written to `~/.nono/audit/` as `session.json` and `audit-events.ndjson`, and are tamper-evident by default.

```bash
nono audit list                          # all sessions
nono audit list --today                  # today only
nono audit list --command omp            # filter by command
nono audit show <session-id>             # inspect a session
nono audit show <session-id> --json      # machine-readable
nono audit verify <session-id>           # verify log integrity
nono audit cleanup                       # remove old sessions
```

To disable audit logging for a session, pass `--no-audit`:

```bash
nono run --profile omp --no-audit -- omp
```

If you want the session log but don't need tamper-evident protection:

```bash
nono run --profile omp --no-audit-integrity -- omp
```

## Rollbacks

nono can snapshot the filesystem before OMP runs and let you selectively restore any files it changed or deleted:

```bash
nono run --rollback --profile omp -- omp
```

With `--rollback` active, nono takes a baseline snapshot before execution and a final snapshot after. When OMP exits, if any files were modified or deleted you get an interactive review showing a per-file diff and a prompt to restore whichever files you want back. Snapshots are stored in `~/.nono/rollbacks/<session-id>/` using SHA-256 content-addressable storage with Merkle tree verification.

```bash
nono rollback list                        # past sessions grouped by project
nono rollback show <id> --diff            # inspect what changed
nono rollback restore <id>                # interactive restore
nono rollback restore <id> --dry-run      # preview without writing
nono rollback verify <id>                 # check Merkle integrity
nono rollback cleanup --older-than 7      # remove sessions older than 7 days
```

To suppress the interactive review prompt (for scripting):

```bash
nono run --rollback --no-rollback-prompt --profile omp -- omp
```

Exclude noisy paths from snapshot tracking in your child profile:

```json
"undo": {
  "exclude_patterns": ["node_modules", ".next", "__pycache__", ".omp"],
  "exclude_globs": ["*.tmp.[0-9]*.[0-9]*"]
}
```

`.gitignore` entries in the working directory are also respected automatically.

## Run detached

By default, nono runs OMP as a child process. This means if you quit OMP, any subprocesses it spawned will also be terminated. If you want OMP to keep running after you exit nono, use `--detached`:

```bash
nono run --profile omp --detached -- omp
```

You can now attach to the running session later to review logs, check status, or run `nono why` queries:

```bash
nono attach <session-id>
```

To view details of all running sessions:

```bash
nono ps
```

## Extending the profile

Create a profile draft to add grants:

```json
{
  "extends": "nolabs-ai/omp",
  "meta": { "name": "omp-extra", "version": "1.0.0" },
  "filesystem": {
    "read": ["/path/to/data"]
  },
  "network": {
    "credentials": ["openai", "anthropic"]
  }
}
```

Then promote it outside the sandbox:

```bash
nono profile validate --draft omp-extra
nono profile promote omp-extra
nono run --profile omp-extra -- omp
```

## nono inbuilt helper commands

The plugin exposes `/nono-status` inside OMP's TUI once the extension loads.

Inside a running OMP sandbox, use `nono why --self` so the query uses the sandbox context for any particular file or network access check:

```bash
nono why --self --path /path/to/some/file --op read
```

### Agent Profile Expansion and Promotion

When a sandbox denial occurs, the agent can draft profile changes, but it cannot directly edit active profiles under `~/.config/nono/profiles`. This keeps policy changes behind an explicit user promotion step. When the agent drafts a profile change, it writes the proposed profile to `~/.config/nono/profile-drafts/<name>.json`. Review the draft, then promote it to make it active:

```bash
nono profile validate --draft omp-agent
nono profile promote omp-agent
```

## Uninstalling

```bash
nono remove nolabs-ai/omp
```

## License

Apache-2.0
