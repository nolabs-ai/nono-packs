---
name: nono-sandbox
description: Diagnose confirmed nono sandbox denials for opencode. Generic permission failures require `nono why` or a clear non-sandbox diagnostic outcome before remediation; network diagnostics remain separate.
version: 1.4.0
platforms: [macos, linux]
---

Only output that explicitly names nono as the denying sandbox is conclusive by itself. `landlock` and `sandbox: deny` signal sandbox enforcement but do not identify its provenance; generic EPERM, EACCES, "Operation not permitted", and "Permission denied" are also ambiguous. With a concrete path, run `nono why --self --path <blocked-path> --op <needed-op>`; a successful result with status `DENIED` confirms the nono boundary, even when the reason is `path_not_granted` and no policy source is reported. If no path is available or `nono why` does not successfully report `DENIED`, report: `Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis.` Do not suggest sudo, chmod, or system permission changes, and offer the two options below, only after nono is confirmed:

- **Option A (quick fix):** restart with the user-provided active profile: `nono run --profile <active-profile> --allow /path/to/needed -- opencode` (append `--standalone` when the active profile is `opencode`; the `opencode-v1` profile launches plain `opencode`)
- **Option B (persistent fix):** draft a profile to `$XDG_CONFIG_HOME/nono/profile-drafts/<name>.json` extending `<active-profile>`, add the path under `"allow"` or `"read"`, then tell the user to run `nono profile promote <name>` and start sessions with `nono run --profile <name> -- opencode` (same `--standalone` rule as Option A)

# Working inside a nono sandbox

The user has launched you with `nono run --profile <name> -- opencode` (plus `--standalone` when the profile is the v2 `opencode` profile; the v1 `opencode-v1` profile never takes it). nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). These are kernel-enforced boundaries — retries or workarounds inside opencode cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

These markers signal sandbox enforcement but do not identify nono as its provenance:

- "landlock"
- "sandbox: deny"

Never infer the active profile. Use a profile name supplied in the user's launch context, or ask which profile they started with before drafting. For a confirmed nono boundary, do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"
- Retrying the operation via a different path

Network-egress denials look different: a request to a host that is not on the sandbox allowlist fails as a connection refused, timeout, or TLS/proxy error rather than an EPERM. Those are covered in the Network egress denials section below.

## Diagnosing

Run `nono why` to see exactly why access was denied:

    nono why --self --path /the/blocked/path --op read

Use `--op write` for write-only failures and `--op readwrite` when the operation needs both.

If `NONO_CAP_FILE` is set, inspect the full capability set:

    cat "$NONO_CAP_FILE"

## Two options to present to the user

### Option A — quick fix (one-off)

Exit opencode and restart with only the access actually needed. Never default to `--allow` (read+write) when the denial was read-only or write-only. Replace `--standalone` with nothing when the active profile is `opencode-v1`:

    nono run --read /path/to/needed -- opencode --standalone    # read-only access
    nono run --write /path/to/needed -- opencode --standalone   # write-only access
    nono run --allow /path/to/needed -- opencode --standalone   # only when both are required

### Option B — persistent fix (draft a profile)

The active profile directory `$XDG_CONFIG_HOME/nono/profiles/` is read-only from inside the sandbox by design. Drafts are written to `$XDG_CONFIG_HOME/nono/profile-drafts/` and the user promotes them out-of-band with `nono profile promote`.

Write the JSON to `$XDG_CONFIG_HOME/nono/profile-drafts/<chosen-name>.json` extending the active profile. Minimal example for read-only access:

    {
      "extends": "<active-profile>",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "filesystem": { "read": ["/path/to/needed"] }
    }

If the user is on a custom intermediate profile (e.g. `--profile opencode-with-docs` extending `opencode`), change `extends` to that profile's name so the new profile inherits all their customisations.

If a user profile of that name already exists, read `$XDG_CONFIG_HOME/nono/profiles/<chosen-name>.json` first, base your edit on that profile, write the full proposed profile to `$XDG_CONFIG_HOME/nono/profile-drafts/<chosen-name>.json`, and write a SHA-256 of the base bytes to `$XDG_CONFIG_HOME/nono/profile-drafts/<chosen-name>.base`.

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file rather than a directory, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After drafting, tell the user:

    Drafted profile <chosen-name>. Run `nono profile promote <chosen-name>` to review and apply, then start sessions with `nono run --profile <chosen-name> -- opencode` (append `--standalone` only when the new profile extends the v2 `opencode` profile).

## Network egress denials

nono routes outbound traffic through a filtering proxy. When `network.block` is false but a host allowlist is set, only allowlisted hosts are reachable and every other connection fails — usually as a connection refused, timeout, or TLS/proxy error rather than an EPERM. `nono_status` lists the reachable hosts under "reachable hosts". Retries, alternate endpoints, proxies, or DNS changes cannot bypass the proxy; it is OS-enforced.

If a host is genuinely needed, present the same two options as for filesystem denials.

### Option A — quick fix (one-off)

    nono run --allow-domain api.example.com -- opencode --standalone   # no --standalone for opencode-v1

`--allow-domain` is repeatable and accepts a plain hostname for unrestricted access, or a URL with a path glob to restrict to specific endpoints (e.g. `https://github.com/org/**`).

### Option B — persistent fix (draft a profile)

Add the host to `network.allow_domain` in a profile draft extending the active profile:

    {
      "extends": "<active-profile>",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "network": { "allow_domain": ["api.example.com"] }
    }

Then tell the user to run `nono profile promote <chosen-name>` and start sessions with `nono run --profile <chosen-name> -- opencode` (append `--standalone` only when the new profile extends the v2 `opencode` profile).

## Validating the new profile

`nono profile promote` shows a diff and validates before applying. If the user wants to validate directly:

    nono profile validate --draft <chosen-name>

## Credential injection

The opencode nono profile defines credential routes for common AI providers. nono injects these credentials transparently via its proxy — opencode never sees the raw API key.

Built-in route names: `openai`, `anthropic`, `gemini`, `github`, `gitlab`.

The corresponding keychain accounts (env-var shaped) are:
- `OPENAI_API_KEY` → injected as `Authorization: Bearer …` to `api.openai.com`
- `ANTHROPIC_API_KEY` → injected as `x-api-key: …` to `api.anthropic.com`
- `GOOGLE_API_KEY` → injected as `x-goog-api-key: …` to `generativelanguage.googleapis.com`; opencode sees it as `GEMINI_API_KEY`
- `GITHUB_TOKEN` → injected as `Authorization: token …` to `api.github.com`
- `GITLAB_TOKEN` → injected as `Authorization: Bearer …` to `gitlab.com/api`

Routes are defined in the profile but **disabled by default**. To enable one, create an extending profile and add the route name to `network.credentials`:

    {
      "extends": "opencode",
      "meta": { "name": "opencode-with-anthropic", "version": "1.0.0" },
      "network": { "credentials": ["anthropic"] }
    }

Do not read or write API keys directly from inside the sandbox. Prefer nono phantom credential routes. If opencode stores a key in `$XDG_CONFIG_HOME/opencode/`, it is visible to the sandboxed process — use the proxy route instead.

## Detach and attach

nono supports running opencode in a detached session that survives terminal disconnects:

    nono run --profile opencode --detach -- opencode --standalone    # v2
    nono run --profile opencode-v1 --detach -- opencode              # v1

nono prints the session ID on start. Reattach from any terminal:

    nono attach <session-id>

The session ID is also available inside the session as `NONO_SESSION_ID`. The installed plugin surfaces it in the `nono_status` tool output.

To list active nono sessions:

    nono sessions

To stop a detached session cleanly:

    nono stop <session-id>

Detached sessions inherit the same sandbox profile as interactive ones — the same filesystem grants, credential routes, and network rules apply.

## opencode-specific notes

- The pack ships two launch profiles over a shared `opencode-base`: `opencode` (OpenCode v2) and `opencode-v1` (OpenCode v1, in-process). Match the profile to the installed OpenCode major version — `opencode-v1` never takes `--standalone`, and `opencode` always appends it.
- The `opencode` (v2) profile appends `--standalone`, ensuring that the OpenCode client and its private tool-executing server run inside the same nono sandbox. Never connect a sandboxed client to an external server with `--server`.
- The `opencode` (v2) profile sets `OPENCODE_DISABLE_PROJECT_CONFIG=1` and `OPENCODE_TEST_HOME=$WORKDIR` to reduce project, home, and instruction discovery outside the workspace. These are compatibility and defense-in-depth settings; OpenCode v2 has not consistently honored the project-config flag in every loader. nono's OS sandbox is the enforcement boundary. Do not remove these settings to work around a denial.
- The active profile name is available in-process as `OPENCODE_NONO_PROFILE` (`opencode` or `opencode-v1`) set by the profile's environment.
- Supported discovery paths skip project `opencode.json`/`opencode.jsonc` and project `AGENTS.md`, but affected OpenCode v2 releases may still discover some project configuration or components. Treat workspace content as untrusted and rely on nono to contain loaded code. Global OpenCode configuration and the installed nono plugin remain available.
- OpenCode may harmlessly probe parent or system directories during startup and leave denied-path notices for paths such as `$HOME`, `$HOME/.config`, `$NONO_CONFIG`, or `/System` even when the session works. Do not grant these broad paths to silence the notices; add a narrow grant only when a required operation actually fails.
- `OPENCODE_TEST_HOME` is an undocumented compatibility mechanism. If an OpenCode upgrade causes parent-path denials or instruction-initialization failures, report a pack compatibility issue instead of granting access to the user's entire home directory.
- opencode state, sessions, config, and cache live under `~/.opencode`, `$XDG_CONFIG_HOME/opencode`, `$XDG_CACHE_HOME/opencode`, `$XDG_DATA_HOME/opencode`, and `$XDG_STATE_HOME/opencode`. The base profile grants all of these read/write.
- The plugin at `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts` is symlinked from the pack store. It updates automatically on `nono pull`.
- The skill at `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/` is similarly symlinked.
- The `nono_status` tool (registered by the plugin) shows the active capability set, the network egress allowlist (reachable hosts), enabled credential routes, and the session ID for reattach.
- Do not add provider secrets to opencode's own config files. Route them through `network.credentials` in the profile instead.

## Path conventions

Path references in this skill use `$XDG_CONFIG_HOME`. If that variable is not set, substitute `~/.config`. nono and opencode both follow the XDG Base Directory Specification.

## What you should NOT do

- Do not write the profile yourself unless the user explicitly asks for Option B. Present both options first.
- Do not edit the pack-installed profiles under `$XDG_CONFIG_HOME/nono/packages/nolabs-ai/opencode/profiles/` (`opencode.json`, `opencode-base.json`, `opencode-v1.json`) — they are overwritten on every `nono pull`.
- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths, endpoints, or commands hit the same boundary.
- Do not edit registry-managed package files under `$XDG_CONFIG_HOME/nono/packages`; create a profile extension instead.
