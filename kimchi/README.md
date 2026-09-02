<p align="center">
  <img src="./assets/logo.png" alt="nono kimchi" width="500" />
</p>


`kimchi` is a nono package for the [Kimchi Coding Agent](https://kimchi.dev). It provides a secure sandbox for running Kimchi and any tools it invokes, with built-in protections for your API keys, system credentials, and filesystem. Use it to safely run Kimchi on your machine and sleep a little easier knowing that even if Kimchi or a tool it runs goes rogue, your secrets and system are protected by nono's multi-layered security model.

## Install

Pull the package first, then create a custom profile before running. This avoids the interactive grants prompt that appears when nono encounters paths the base profile doesn't cover:

**Step 1 — pull the package:**

```bash
nono pull nolabs-ai/kimchi
```

**Step 2 — create a custom profile:**

```bash
nono profile init kimchi --extends nolabs-ai/kimchi --full
```

A custom profile is also where you add credential routes, API keys, tokens, extra filesystem grants, and any other customizations — see the sections below. It's worth running this step, even if you don't think you'll need any custom grants or credentials, just to avoid the grants prompt later.

**Step 3 — run Kimchi:**

```bash
nono run --profile kimchi --allow-cwd -- kimchi --yolo
```

Notice the `--yolo` flag. With nono sandbox it's much safer to run any agent, so you can use this flag to skip permission checks. Bear in mind though that even with nono it's still not perfectly safe to run `--yolo` mode, so do it at your own risk.

### First-run grants prompt

If you run nono before creating a custom profile, nono may detect paths that Kimchi needs but that the base profile doesn't cover — your shell config, a tool on a non-standard path, etc. When this happens you'll see a prompt like:

```
Sandbox denial: 3 paths blocked.
  ~/.config/gh (read)
  ~/dev/dotfiles/zsh (read)
  /usr/local/sbin (read)

[nono] Choose suppress to keep denying all listed paths and stop future save suggestions.
Save suggestions to a user profile? [g] grant / [s] suppress / [Enter] skip:
```

- **`g` (grant)** — saves the extra path grants to a user profile. Use the same name you plan to use for your custom profile (e.g. `kimchi`) so both sets of grants live in one place.
- **`s` (suppress)** — stops nono from suggesting these paths in future. The paths remain denied.
- **Enter (skip)** — skips saving for now. You'll be prompted again next time.

The cleanest approach is to skip (`Enter`) and add any extra paths manually to your child profile's `filesystem.read` or `filesystem.allow` block.

## Custom profiles

To create your own custom profile that extends the base `nolabs-ai/kimchi` profile, use the `nono profile init` command with the `--extends` flag. This allows you to inherit from the base profile while customizing specific aspects such as credential routes and network filtering.

> If you already created a profile via the first-run grants prompt, use that same name here — `nono profile init` will extend it rather than creating a second one.

```bash
nono profile init kimchi --extends nolabs-ai/kimchi --full
```

This will create a `~/.config/nono/profiles/kimchi.json` file that you can then customize to your needs. The `--full` flag ensures that the generated profile includes all sections, making it easier to see what you can customize.

### Runtime groups

The base `kimchi` profile includes only `git_config` and `unlink_protection` groups — it does not include language runtime groups (`node_runtime`, `python_runtime`, `rust_runtime`, `nix_runtime`). If your project uses these toolchains, add the relevant groups to your child profile:

```json
{
  "extends": "nolabs-ai/kimchi",
  "groups": {
    "include": ["node_runtime", "python_runtime"]
  }
}
```

List all available groups with:

```bash
nono profile groups
```

## Sandbox-aware diagnostics

The `kimchi` package ships a nono-sandbox extension that helps the agent diagnose and remediate sandbox denials automatically. It works in three parts:

1. **Session hook** — runs on the host before the session starts and captures the nono command line into `KIMCHI_NONO_COMMAND`.

2. **Per-session guidance doc** — at session start, the extension renders a guidance document from a template using the captured command line. This doc contains profile-specific remediation steps (patch existing profile, create a new profile, or one-off restart) tailored to the exact invocation you ran.

3. **Denial detection** — when a tool result matches sandbox denial patterns (`Operation not permitted`, `Permission denied`, `EACCES`, `EPERM`, `landlock`, `sandbox denied`), the extension sends a steering message to the agent with a pointer to the guidance doc. The agent then presents remediation options to the user.

## nono inbuilt helper commands

The nono-sandbox extension exposes the `/nono-status` command inside a running Kimchi session. It reads the nono capability manifest and asks the LLM to produce a concise, structured summary of what the sandbox allows and denies (filesystem paths, network egress, environment, other capabilities).

Inside a running Kimchi sandbox, use `nono why --self` so the query uses the sandbox context for any particular file or network access check:

```bash
nono why --self --path /path/to/some/file --op read
```

## Credential Protection

nono protects API keys using a **phantom credential** model. Rather than passing your real key into the sandbox, nono generates a short-lived random token and injects that into Kimchi instead. When Kimchi makes an outbound API call carrying the phantom token, nono's proxy intercepts the request, validates the token, fetches the real key from your system keystore (macOS Keychain, Linux Secret Service, 1Password, etc.), and swaps it in before the request leaves the machine. The real key is never visible to the sandboxed process, so even if Kimchi or a tool it runs were compromised, an attacker would obtain only the useless phantom — not the credential itself.

> **Do not store API keys in `~/.config/kimchi/config.json`.** Kimchi's own setup suggests this as an approach, but doing so places the real key directly in Kimchi's environment and bypasses nono's phantom credential protection entirely. Keep keys in nono's keychain (or a URI ref source) and let nono inject them.

### Setting up the Kimchi API credential route

The base `kimchi` profile does not enable any credential routes by default. Kimchi authenticates to `llm.kimchi.dev` using the `KIMCHI_API_KEY` environment variable sent as an `Authorization: Bearer <key>` header. To protect this key with nono's phantom credential model, add a custom credential route to your child profile.

#### Step 1 — store the key

**macOS Keychain:**

```bash
security add-generic-password -U -s "nono" -a "KIMCHI_API_KEY" -w
```

Keep `-w` last so macOS prompts for the value instead of recording it in shell history.

**Linux Secret Service:**

```bash
secret-tool store --label="nono: KIMCHI_API_KEY" \
  service nono username KIMCHI_API_KEY target default
```

On Linux this requires a running Secret Service provider such as GNOME Keyring or KWallet. In SSH-only or headless environments, check the nono credential docs before choosing a storage backend.

If your key lives somewhere other than the system keyring, point `credential_key` at it with a URI ref instead:

```json
"credential_key": "env://KIMCHI_API_KEY"
```
Reads the key from `KIMCHI_API_KEY` in nono's own environment. `env_var` is not required for this form.

```json
"credential_key": "op://Personal/Kimchi/credential",
"env_var": "KIMCHI_API_KEY"
```
Fetches the key from 1Password at runtime. `env_var` is required for `op://` so nono knows which variable to inject into the sandbox.

```json
"credential_key": "file:///run/secrets/kimchi.key",
"env_var": "KIMCHI_API_KEY"
```
Reads the key from a file. `env_var` is required for `file://`.

For the full credential URI ref model (`op://`, `apple-password://`, `file://`, `env://`), see:

- https://nono.sh/docs/cli/features/credential-injection

#### Step 2 — add the route to your profile

Open your child profile (`~/.config/nono/profiles/kimchi.json`) and update the `network` block:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["kimchi"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {
    "kimchi": {
      "upstream": "https://llm.kimchi.dev",
      "credential_key": "KIMCHI_API_KEY",
      "env_var": "KIMCHI_API_KEY"
    }
  }
}
```

The map key (`"kimchi"`) is the route name. **It must also appear in the `credentials` array** — nono only activates routes explicitly listed there. `inject_header` and `credential_format` are omitted because the defaults (`"Authorization"` and `"Bearer {}"`) already match what Kimchi expects.

For tighter control you can add `endpoint_rules` — a list of `{"method", "path"}` pairs that act as an L7 allow-list. When non-empty, the proxy rejects any request that doesn't match, even with a valid phantom token. This is useful if you want to restrict a credential to inference-only endpoints and block billing, account management, or other API surfaces the agent should never reach. Omit it, as above, to allow all paths under the route.

### Additional providers

You can enable multiple custom credential routes at once. For example, to add [OpenRouter](https://openrouter.ai) alongside the Kimchi API:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["kimchi", "openrouter"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {
    "kimchi": {
      "upstream": "https://llm.kimchi.dev",
      "credential_key": "KIMCHI_API_KEY",
      "env_var": "KIMCHI_API_KEY"
    },
    "openrouter": {
      "upstream": "https://openrouter.ai/api/v1",
      "credential_key": "OPENROUTER_API_KEY",
      "env_var": "OPENROUTER_API_KEY"
    }
  }
}
```

Store each key in the nono keychain using the account name that matches `credential_key`:

```bash
security add-generic-password -U -s "nono" -a "KIMCHI_API_KEY" -w
security add-generic-password -U -s "nono" -a "OPENROUTER_API_KEY" -w
```

#### How phantom credentials work

nono generates a phantom token and injects it into Kimchi as an environment variable. When Kimchi makes an outbound call, the proxy validates the phantom, fetches the real key from the keystore, and swaps it in before the request leaves the machine. The credential never enters the sandbox — Kimchi only ever sees the short-lived phantom.

Run Kimchi with your child profile:

```bash
nono run --profile kimchi -- kimchi
```

## Uninstalling the plugin

```bash
nono remove nolabs-ai/kimchi
```
