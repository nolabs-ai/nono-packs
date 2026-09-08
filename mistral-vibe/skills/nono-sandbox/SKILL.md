---
name: nono-sandbox
description: Diagnose Mistral Vibe failures caused by the nono sandbox boundary.
user-invocable: false
---

# Mistral Vibe inside nono

When Vibe reports `Permission denied`, `Operation not permitted`, `EACCES`, or `EPERM`, treat it as a nono profile boundary. The operating system sandbox is the enforcement layer; retrying the same command or changing Vibe's own permissions cannot grant access.

For a one-off path, restart with a narrow grant:

```bash
nono run --profile mistral-vibe --allow /path/to/needed -- vibe
```

For repeated access, create a child profile extending `mistral-vibe`, add the path to its `filesystem.allow` or `filesystem.read`, validate it, and promote it outside the sandbox:

```bash
nono profile init mistral-vibe-local --extends mistral-vibe --full
nono profile validate mistral-vibe-local
nono profile promote mistral-vibe-local
```

Vibe's installed launcher is commonly `~/.local/bin/vibe`, backed by the `uv` tool environment at `~/.local/share/uv/tools/mistral-vibe`. If startup exits 127 and no path denial is reported, check that both locations are readable by the active profile.

Do not put API keys in Vibe config files. Enable the profile's `mistral` credential route in a child profile so nono can inject a short-lived credential instead.
