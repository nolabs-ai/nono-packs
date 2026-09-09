---
name: nono-sandbox
description: Diagnose confirmed nono sandbox denials for opencode. Generic permission failures require `nono why` or a clear non-sandbox diagnostic outcome before remediation; network diagnostics remain separate.
version: 1.2.0
platforms: [macos, linux]
---

Only output that explicitly names nono as the denying sandbox is conclusive by itself. `landlock` and `sandbox: deny` signal sandbox enforcement but do not identify its provenance; generic EPERM, EACCES, "Operation not permitted", and "Permission denied" are also ambiguous. With a concrete path, run `nono why --self --path <blocked-path> --op <needed-op>`; a successful result with status `DENIED` confirms the nono boundary, even when the reason is `path_not_granted` and no policy source is reported. If no path is available or `nono why` does not successfully report `DENIED`, report: `Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis.` Do not suggest sudo, chmod, or system permission changes, and offer the two options below, only after nono is confirmed:

- **Option A (quick fix):** restart with the user-provided active profile: `nono run --profile <active-profile> --allow /path/to/needed -- opencode`
- **Option B (persistent fix):** draft a profile to `$XDG_CONFIG_HOME/nono/profile-drafts/<name>.json` extending `<active-profile>`, add the path under `"allow"` or `"read"`, then tell the user to run `nono profile promote <name>` and start sessions with `nono run --profile <name> -- opencode`

# Working inside a nono sandbox

The user has launched you with `nono run --profile <name> -- opencode`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). These are kernel-enforced boundaries — retries or workarounds inside opencode cannot grant access that nono hasn't already permitted.

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

Exit opencode and restart with the path explicitly allowed:

    nono run --allow /path/to/needed -- opencode

Use `--read` when only read access is needed.

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

    Drafted profile <chosen-name>. Run `nono profile promote <chosen-name>` to review and apply, then start sessions with `nono run --profile <chosen-name> -- opencode`.

## Network egress denials

nono routes outbound traffic through a filtering proxy. When `network.block` is false but a host allowlist is set, only allowlisted hosts are reachable and every other connection fails — usually as a connection refused, timeout, or TLS/proxy error rather than an EPERM. `nono_status` lists the reachable hosts under "reachable hosts". Retries, alternate endpoints, proxies, or DNS changes cannot bypass the proxy; it is OS-enforced.

If a host is genuinely needed, present the same two options as for filesystem denials.

### Option A — quick fix (one-off)

    nono run --allow-domain api.example.com -- opencode

`--allow-domain` is repeatable and accepts a plain hostname for unrestricted access, or a URL with a path glob to restrict to specific endpoints (e.g. `https://github.com/org/**`).

### Option B — persistent fix (draft a profile)

Add the host to `network.allow_domain` in a profile draft extending the active profile:

    {
      "extends": "<active-profile>",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "network": { "allow_domain": ["api.example.com"] }
    }

Then tell the user to run `nono profile promote <chosen-name>` and start sessions with `nono run --profile <chosen-name> -- opencode`.

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

    nono run --profile opencode --detach -- opencode

nono prints the session ID on start. Reattach from any terminal:

    nono attach <session-id>

The session ID is also available inside the session as `NONO_SESSION_ID`. The installed plugin surfaces it in the `nono_status` tool output.

To list active nono sessions:

    nono sessions

To stop a detached session cleanly:

    nono stop <session-id>

Detached sessions inherit the same sandbox profile as interactive ones — the same filesystem grants, credential routes, and network rules apply.

## opencode-specific notes

- opencode state, sessions, config, and cache live under `~/.opencode`, `$XDG_CONFIG_HOME/opencode`, `$XDG_CACHE_HOME/opencode`, `$XDG_DATA_HOME/opencode`, and `$XDG_STATE_HOME/opencode`. The base profile grants all of these read/write.
- The plugin at `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts` is symlinked from the pack store. It updates automatically on `nono pull`.
- The skill at `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/` is similarly symlinked.
- The `nono_status` tool (registered by the plugin) shows the active capability set, the network egress allowlist (reachable hosts), enabled credential routes, and the session ID for reattach.
- Do not add provider secrets to opencode's own config files. Route them through `network.credentials` in the profile instead.

## Path conventions

Path references in this skill use `$XDG_CONFIG_HOME`. If that variable is not set, substitute `~/.config`. nono and opencode both follow the XDG Base Directory Specification.

## What you should NOT do

- Do not write the profile yourself unless the user explicitly asks for Option B. Present both options first.
- Do not edit the pack-installed profile at `$XDG_CONFIG_HOME/nono/packages/nolabs-ai/opencode/policy.json` — it is overwritten on every `nono pull`.
- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths, endpoints, or commands hit the same boundary.
- Do not edit registry-managed package files under `$XDG_CONFIG_HOME/nono/packages`; create a profile extension instead.
