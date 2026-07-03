---
name: nono-sandbox
description: Understands nono security sandbox constraints. Use when running inside a nono sandbox, when tool operations fail with permission errors, or when the user asks about sandbox capabilities.
---

# nono Sandbox Awareness

You are running inside a **nono security sandbox**. nono enforces OS-level capability restrictions using Landlock (Linux) and Seatbelt (macOS). These are kernel-enforced boundaries that cannot be bypassed from within the session.

## How the sandbox works

nono applies an allow-list of filesystem paths and network rules before your process starts. Everything not explicitly allowed is blocked at the kernel level. There is no escalation path from inside the sandbox.

- **Filesystem**: Only paths granted by the active profile are accessible. The current working directory typically has read-write access.
- **Network**: May be fully allowed, filtered to specific domains, or completely blocked depending on the profile.
- **No escalation**: There is no sudo, no permission changes, no workaround that can expand capabilities from within.

## When an operation is denied

If a file read, write, edit, or shell command fails with a permission error (EPERM, EACCES, "Operation not permitted", "Permission denied"):

1. **Do NOT retry** the same operation or try alternative paths.
2. **Do NOT attempt workarounds** such as:
   - Copying files to allowed locations
   - Using sudo or chmod
   - Accessing the same data through a different path
   - Suggesting the user run commands manually from another terminal
3. **Do NOT apologize repeatedly** or suggest you will "try another approach" — there is no other approach.

This is a nono sandbox denial, **not** macOS TCC, **not** Unix file permissions, and **not** an Antigravity approval prompt.

## Diagnosing the denial

Run `nono why` to understand exactly why the operation was blocked:

```bash
nono why --path /path/that/failed --op read 2>/dev/null
```

This tells you:
- The reason (e.g., `insufficient_access`, `no_matching_capability`)
- Which group or rule covers the path
- A suggested fix (e.g., `--allow-file /path/to/file`)

Always run `nono why` before telling the user what to do. It gives you the precise diagnosis.

## Helping the user

After diagnosing with `nono why`, present the user with options:

1. **Quick fix** — restart the session with the path allowed:
   ```
   nono run --allow /path/to/needed -- agy
   ```

2. **Write a profile draft** — if the user needs this access regularly, offer to draft a nono profile for them. The active profile directory `~/.config/nono/profiles/` is read-only from inside the sandbox by design, so drafts are written to `~/.config/nono/profile-drafts/` and the user promotes them out-of-band.

   If the user agrees, run `nono profile guide` to get the full profile schema, then write the full profile JSON to `~/.config/nono/profile-drafts/<name>.json`.

   If `~/.config/nono/profile-drafts` does not exist or cannot be written, or `nono profile promote --help` is unavailable, do not try to modify profiles directly. Tell the user to upgrade nono, then rerun the draft flow.

   If a user profile of that name already exists in `~/.config/nono/profiles/<name>.json`, read it first, compute the SHA-256 of the exact bytes you read, base your edit on it, then write that hash to `~/.config/nono/profile-drafts/<name>.base`.

   If there is no user profile yet and the current profile is pack-provided or built-in, do not draft a replacement with the same name. Draft a derived profile such as `<active>-local` with `"extends": "<active>"` and add only the extra access there.

   Tell the user: `Drafted <name>. Run \`nono profile promote <name>\` to review and apply, then start sessions with \`nono run --profile <name> -- agy\`.`

## Checking what is allowed

If the environment variable `NONO_CAP_FILE` is set, it points to a JSON file listing the current capabilities. You can read it to understand what paths are accessible:

```bash
cat "$NONO_CAP_FILE" | jq .
```

The file contains:
- `fs`: array of filesystem capabilities with `path`, `resolved`, and `access` fields
- `net_blocked`: boolean indicating whether network access is blocked

## Common scenarios

**"I need to read a config file outside the project"**
Run `nono why --path /path/to/config --op read 2>/dev/null`, then offer the quick fix or a profile.

**"I need to install a global package"**
Global package managers write to system paths. Suggest project-local alternatives (e.g., `npx` instead of global install) or offer to write a profile.

**"Network request failed"**
If the profile blocks network access, the user must use a profile that allows it. Offer to write one.

**"I need to access another project directory"**
Run `nono why --path /path/to/other/project --op readwrite 2>/dev/null`, then offer the quick fix or a profile.
