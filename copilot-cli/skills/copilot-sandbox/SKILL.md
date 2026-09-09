---
name: copilot-sandbox
description: Understands nono security sandbox constraints for GitHub Copilot CLI. Use when running inside a nono sandbox, when operations fail with permission errors, or when a tool use is denied.
---

# Working inside a nono sandbox

The user has launched you with `nono run --profile <profile> -- copilot`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). Approval flows inside Copilot cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

Only output that explicitly names nono as the denying sandbox is conclusive by itself. These markers signal sandbox enforcement but do not identify its provenance:

- "landlock"
- "sandbox: deny"

Generic "Operation not permitted", "Permission denied", EACCES, and EPERM are also ambiguous. If a concrete path is available, run `nono why --self --path <path> --op <needed-op>`; a successful result with status `DENIED` confirms the nono boundary, even when the reason is `path_not_granted` and no policy source is reported. Otherwise report: `Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis.`

For a confirmed nono denial, do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"

## What the sandbox allows

Allowed paths vary by profile. For the exact capability list of the active session, read `NONO_CAP_FILE`:

```bash
cat "$NONO_CAP_FILE" | jq .
```

Invariants across all profiles:

- **Working directory**: full read+write from the directory `copilot` was launched in
- **Network**: allowed — unrestricted outbound

Everything else is blocked at the kernel level. There is no escalation path from inside the sandbox.

## Diagnosing

Run `nono why` to see exactly why access was denied:

```bash
nono why --self --path /the/blocked/path --op read
```

The output names the rule that blocked the path and suggests the minimum grant to allow it.

Always run `nono why` before telling the user what to do.

Never infer the active profile. Use a profile name supplied in the user's launch context, or ask which profile they started with before drafting.

## Two options to present to the user

### Option A — quick fix (one-off)

Exit Copilot and restart with the path explicitly allowed:

```
nono run --allow /path/to/needed -- copilot
```

### Option B — persistent fix (write a profile)

Save a JSON file at `~/.config/nono/profiles/<chosen-name>.json` extending the active profile and adding the path. Minimal example for read-only access:

```json
{
  "extends": "<active-profile>",
  "meta": { "name": "<chosen-name>", "version": "1.0.0" },
  "filesystem": { "read": ["/path/to/needed"] }
}
```

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After saving, the user starts sessions with:

```
nono run --profile <chosen-name> -- copilot
```

## Checking current capabilities

`NONO_CAP_FILE` fields:
- `fs`: array of filesystem capabilities (`path`, `resolved`, `access`)
- `net_blocked`: `true` if network is blocked

## Working directory redirects

If a tool fails because a process tried to write outside the working directory for a **non-critical, recoverable reason** (caching, temp files), and the tool supports redirecting that path via a flag or environment variable, retry with the output redirected into the working directory. Inform the user and suggest adding the folder to `.gitignore` if it would otherwise be committed.

For load-bearing writes (config that must live at a specific path, credentials, lock files), follow the denial handling flow above instead.

## What you should NOT do

- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths hit the same boundary.
- Do not edit the pack-installed profiles at `~/.config/nono/packages/nolabs-ai/copilot-cli/profiles/` — they are overwritten on every `nono pull`.
