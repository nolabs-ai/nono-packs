---
name: nono-sandbox
description: Diagnose confirmed nono sandbox denials for OpenClaw. Generic permission failures require `nono why` or a clear non-sandbox diagnostic outcome before remediation.
---

Only output that explicitly names nono as the denying sandbox is conclusive by itself. `landlock` and `sandbox: deny` signal sandbox enforcement but do not identify its provenance; generic EPERM, EACCES, "Operation not permitted", and "Permission denied" are also ambiguous. With a concrete path, run `nono why --self --path <blocked-path> --op <needed-op>`; a successful result with status `DENIED` confirms the nono boundary, even when the reason is `path_not_granted` and no policy source is reported. If no path is available or `nono why` does not successfully report `DENIED`, report: `Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis.` Do not suggest sudo, chmod, or system permission changes, and offer the two options below, only after nono is confirmed:

- **Option A (quick fix):** restart with the user-provided active profile: `nono run --profile <active-profile> --allow /path/to/needed -- openclaw`
- **Option B (persistent fix):** draft a profile to `~/.config/nono/profile-drafts/<name>.json` extending `<active-profile>`, add the path under `"allow"` or `"read"`, then tell the user to run `nono profile promote <name>` and start sessions with `nono run --profile <name> -- openclaw`

# Working inside a nono sandbox

The user has launched you with `nono run --profile <name> -- openclaw`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). These are kernel-enforced boundaries — approvals or retries inside OpenClaw cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

These markers signal sandbox enforcement but do not identify nono as its provenance:

- "landlock"
- "sandbox: deny"

Never infer the active profile. Use a profile name supplied in the user's launch context, or ask which profile they started with before drafting. For a confirmed nono boundary, do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"
- Retrying the operation via a different path

## Diagnosing

Run `nono why` to see exactly why access was denied:

    nono why --self --path /the/blocked/path --op read

The output names the rule that blocked the path and suggests the minimum grant to allow it.

## Two options to present to the user

### Option A — quick fix (one-off)

Exit OpenClaw and restart with the path explicitly allowed:

    nono run --allow /path/to/needed -- openclaw

Use this for paths the user only needs occasionally.

### Option B — persistent fix (draft a profile)

The active profile directory `~/.config/nono/profiles/` is read-only from inside the sandbox by design. Drafts are written to `~/.config/nono/profile-drafts/` and the user promotes them out-of-band with `nono profile promote`.

Write the JSON to `~/.config/nono/profile-drafts/<chosen-name>.json` extending the active profile. Minimal example for read-only access:

    {
      "extends": "<active-profile>",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "filesystem": { "read": ["/path/to/needed"] }
    }

If the user is on a custom intermediate profile (e.g. `--profile openclaw-with-docs` extending `openclaw`), change `extends` to that profile's name so the new profile inherits all their customisations.

If a user profile of that name already exists, read `~/.config/nono/profiles/<chosen-name>.json` first, compute the SHA-256 of the exact bytes you read, base your edit on that profile, write the full proposed profile to `~/.config/nono/profile-drafts/<chosen-name>.json`, and write the hash to `~/.config/nono/profile-drafts/<chosen-name>.base`.

If there is no user profile yet and the active profile is pack-provided or built-in, do not draft a replacement with the same name. Draft a derived profile such as `<active>-local` with `"extends": "<active>"` and add only the extra access there.

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file rather than a directory, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After drafting, tell the user:

    Drafted profile <chosen-name>. Run `nono profile promote <chosen-name>` to review and apply, then start sessions with `nono run --profile <chosen-name> -- openclaw`.

## Validating the new profile

`nono profile promote` shows a diff and validates before applying. If the user wants to validate the draft directly:

    nono profile validate --draft <chosen-name>

## Multi-agent instances

If you are one of several OpenClaw instances running simultaneously, each runs in its own isolated sandbox. Coordination with peer agents happens exclusively through the shared bus at `$TMPDIR/openclaw-$UID/`. Do not attempt to read or write the other agents' home directories (`~/.openclaw-agent1`, etc.) — those are blocked between instances by design.

## What you should NOT do

- Do not write the profile yourself unless the user explicitly asks for Option B. Present both options first.
- Do not edit the pack-installed profile at `~/.config/nono/packages/nolabs-ai/openclaw/policy.json` — it is overwritten on every `nono pull`.
- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths or commands hit the same boundary.
