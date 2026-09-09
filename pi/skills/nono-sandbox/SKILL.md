---
name: nono-sandbox
description: Diagnose confirmed nono sandbox denials for Pi Coding Agent. Generic permission failures require `nono why` or a clear non-sandbox diagnostic outcome before remediation.
version: 1.0.0
platforms: [macos, linux]
---

# Working inside a nono sandbox

The user has launched Pi with `nono run --profile <name> -- pi`. nono enforces filesystem and network limits at the OS level before Pi starts. Landlock on Linux and Seatbelt on macOS enforce those rules outside Pi's approval and extension systems.

Pi cannot expand nono access from inside the session. Retries, approval prompts, chmod, chown, sudo, or macOS privacy settings do not grant new nono capabilities.

## When to use this skill

Use this skill to investigate a suspected nono denial. Only output that explicitly names nono as the denying sandbox is conclusive by itself. These markers signal sandbox enforcement but do not identify its provenance:

- `landlock`
- `sandbox: deny` or `sandbox denied`

## Diagnosis

Generic `Operation not permitted`, `Permission denied`, `EACCES`, and `EPERM` are also ambiguous. With a concrete path, run `nono why --self`; a successful result with status `DENIED` confirms the nono boundary, even when the reason is `path_not_granted` and no policy source is reported. Otherwise report: `Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis.` Never infer the active profile; use the user's launch context or ask before drafting.

1. Identify the concrete blocked path or network action from the failed tool call, stderr, traceback, or command arguments.
2. Run:

   ```bash
   nono why --self --path /the/blocked/path --op read
   ```

3. Use `--op write` for write-only failures and `--op readwrite` when the operation needs both.
4. If `NONO_CAP_FILE` is set, inspect the current sandbox:

   ```bash
   cat "$NONO_CAP_FILE"
   ```

## Remediation options

Present exactly two options to the user.

### Option A: one-off restart

Use this for a path needed only once:

```bash
nono run --profile <active-profile> --allow /path/to/needed -- pi
```

Use `--read` instead of `--allow` when Pi only needs view access.

### Option B: profile draft

Create a profile draft under `~/.config/nono/profile-drafts/<name>.json`:

```json
{
  "extends": "<active-profile>",
  "meta": { "name": "pi-extra", "version": "1.0.0" },
  "filesystem": {
    "read": ["/path/to/needed"]
  }
}
```

Do not write directly to `~/.config/nono/profiles` from inside the sandbox. Active profiles control future sandbox policy and must stay behind a user review step.

The user reviews and promotes the draft outside the sandbox:

```bash
nono profile validate --draft pi-extra
nono profile promote pi-extra
```

Start future sessions with:

```bash
nono run --profile pi-extra -- pi
```

Use `read_file`, `write_file`, or `allow_file` only for exact single-file grants. Use `read`, `write`, or `allow` for directories.

## Pi-specific notes

- Pi state, package installs, sessions, auth data, and settings live under `~/.pi`. The base nono Pi profile grants this directory read/write because Pi needs its own state.
- The nono Pi pack installs itself as a Pi package by adding the pack directory to `~/.pi/agent/settings.json`.
- Prefer nono phantom credential routes for API keys. Pi's `~/.pi/agent/auth.json` is inside the sandbox because Pi must read it, so real API keys stored there are visible to the sandboxed process.
- The base Pi profile defines provider credential routes but enables none by default. Create an extending profile and list only the needed routes in `network.credentials`.
- Built-in credential route account names are `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `GITHUB_TOKEN`, and `GITLAB_TOKEN`. The Gemini route injects `GEMINI_API_KEY` into Pi while reading `GOOGLE_API_KEY` from the nono keychain.

## Do not do

- Do not suggest Full Disk Access, chmod, chown, or sudo for nono denials.
- Do not retry a blocked tool through a different path.
- Do not tell the user Pi approval can fix a nono denial.
- Do not edit registry-managed package files under `~/.config/nono/packages`; create a profile extension instead.
