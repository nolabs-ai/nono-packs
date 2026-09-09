---
name: nono-sandbox
description: Diagnose Mistral Vibe failures caused by the nono sandbox boundary.
user-invocable: false
---

# Mistral Vibe inside nono

Only output that explicitly names nono as the denying sandbox is conclusive by itself. `landlock` and `sandbox: deny` signal sandbox enforcement but do not identify its provenance; `Permission denied`, `Operation not permitted`, `EACCES`, and `EPERM` are also ambiguous. When a concrete path is known, run `nono why --self --path <path> --op <needed-op>`; a successful result with status `DENIED` confirms the nono boundary, even when the reason is `path_not_granted` and no policy source is reported. Otherwise report: `Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis.` For a confirmed nono denial, the OS sandbox is the enforcement layer; retrying the same command or changing Vibe's own permissions cannot grant access.

Never infer the active profile. Use the profile name supplied in the user's launch context, or ask which profile they started with before drafting or restarting.

For a one-off path, restart with a narrow grant:

```bash
nono run --profile <active-profile> --allow /path/to/needed -- vibe
```

For repeated access, create a child profile extending the user-provided active profile, add the path to its `filesystem.allow` or `filesystem.read`, validate it, and promote it outside the sandbox:

```bash
nono profile init mistral-vibe-local --extends <active-profile> --full
nono profile validate mistral-vibe-local
nono profile promote mistral-vibe-local
```

Vibe's installed launcher is commonly `~/.local/bin/vibe`, backed by the `uv` tool environment at `~/.local/share/uv/tools/mistral-vibe`. If startup exits 127 and no path denial is reported, check that both locations are readable by the active profile.

Do not put API keys in Vibe config files. Enable the profile's `mistral` credential route in a child profile so nono can inject a short-lived credential instead.
