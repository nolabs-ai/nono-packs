# opencode nono

`opencode` is a `nono` package for [opencode](https://github.com/opencode-ai/opencode).

It installs a sandbox profile, a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox — including credential injection, detach/attach session support, and denial diagnostics.

## What It Does

The pack provides:

- a sandbox profile (`policy.json`) granting the correct filesystem and network access, with credential injection routes for OpenAI, Anthropic, Gemini, GitHub, GitLab (opt-in), and AWS Bedrock (SigV4/SSO, one route per supported Region, active by default)
- a `session_hooks.before` hook (`bin/ensure-dirs.sh`) that creates opencode's state directories on the host before the sandbox is applied, so first-run doesn't fail when a directory the profile grants access to doesn't exist yet
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that injects nono sandbox context at session start, detects denial signatures in tool results, appends capability context and Option A/B remediation guidance, surfaces the network egress allowlist, and registers a `nono-status` command
- a `nono-sandbox` skill that teaches the correct diagnostic flow for filesystem and network-egress denials, credential route setup, and detach/attach usage

## Behavior

When opencode is running inside a `nono` sandbox the installed plugin:

- no-ops if `NONO_CAP_FILE` is not set (not inside a nono session)
- injects sandbox context into the system prompt at session start so the model knows the rules before its first tool call
- surfaces the session ID (for `nono attach`) when running detached
- detects sandbox-denial signatures in tool results (`Operation not permitted`, `EACCES`, `EPERM`, `landlock`)
- appends the active capability set, credential route summary, and remediation instructions so the model always receives correct guidance
- reports the network egress allowlist (reachable hosts) with state-aware guidance for blocked, allowlisted, and unrestricted networking
- steers the model toward the two valid remediations: `--allow` restart or a persistent profile draft

This prevents common bad guidance such as retrying the same action, suggesting `chmod`, attempting network workarounds, or treating the failure as a macOS TCC issue.

## First-Run Directory Bootstrap

Landlock and Seatbelt can only grant a filesystem rule for a path that already exists. On a first run, a few state/cache/etc. directories don't exist yet, so the sandboxed opencode process fails immediately.

`policy.json` wires `bin/ensure-dirs.sh` as a `session_hooks.before` hook, which nono runs on the host before applying the sandbox to `mkdir -p` them first. Requires nono v0.63.0+ for `$PACK_DIR` expansion in `session_hooks`.

## Credential Injection

nono intercepts outbound HTTPS and injects API keys from its keychain — opencode never sees the raw secret. Routes other than `bedrock_<region>` (see below) are defined in the profile but **disabled by default**.

To enable a route, create an extending profile:

```json
{
  "extends": "opencode",
  "meta": { "name": "opencode-with-anthropic", "version": "1.0.0" },
  "network": { "credentials": ["anthropic"] }
}
```

Built-in route names: `openai`, `anthropic`, `gemini`, `github`, `gitlab`.

Store the corresponding secret in the nono keychain under the env-var-shaped account name (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.).

## AWS Bedrock (SigV4 / SSO)

The `bedrock_*` routes work differently from the static-key routes above. Instead of injecting a header from a stored secret, nono intercepts the request and re-signs it with real AWS SigV4 credentials from the standard AWS credential chain, including SSO profiles. This needs `nono` 0.70.0 or later. Earlier versions have a signing bug for any Bedrock model ID with a colon in it ([nolabs-ai/nono#1430](https://github.com/nolabs-ai/nono/pull/1430), which is every standard model ID), and 0.69.0 on its own has a separate regression that breaks all non-Bedrock traffic on an open-network profile like this one ([#1485](https://github.com/nolabs-ai/nono/issues/1485), fixed in [#1497](https://github.com/nolabs-ai/nono/pull/1497)).

SigV4 signatures are tied to a region, so there's one route per Bedrock region instead of a single `bedrock` route. Route names follow `bedrock_<region>`, for example `bedrock_us_east_1` or `bedrock_eu_west_1`. Check `network.custom_credentials` in `policy.json`, or run `nono profile show opencode`, for the full list, and match it against the [official Bedrock endpoint list](https://docs.aws.amazon.com/general/latest/gr/bedrock.html) for your region. GovCloud routes (`bedrock_us_gov_east_1`, `bedrock_us_gov_west_1`) need a separate GovCloud account and won't resolve from a commercial SSO profile.

Unlike the routes above, every `bedrock_<region>` route is active by default, listed directly in the base profile's own `network.credentials`. There's no secret to protect by gating activation. `aws_auth` just resolves whatever AWS credentials are already on the host at request time (env vars, the default profile, an active `aws sso login` session, an instance role), and fails the same way an unsandboxed call would if none exist. As long as you're logged in and opencode's `amazon-bedrock` provider points at a matching region, it just signs the request. You don't need an extending profile for that.

To pin a specific AWS profile instead of the default chain, override `aws_auth.profile` in an extending profile. The override replaces the whole entry, so you need to repeat `upstream` too, even though only `aws_auth` actually changes:

```json
{
  "extends": "opencode",
  "meta": { "name": "opencode-with-bedrock", "version": "1.0.0" },
  "network": {
    "custom_credentials": {
      "bedrock_us_east_1": {
        "upstream": "https://bedrock-runtime.us-east-1.amazonaws.com",
        "aws_auth": { "profile": "my-sso-profile" }
      }
    }
  }
}
```

The base profile also denies `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, and every other AWS credential variable, including legacy SDK aliases (`AWS_CONTAINER_*`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_ROLE_*`, `AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`, `AWS_ACCESS_KEY`, `AWS_SECRET_KEY`, `AWS_SECURITY_TOKEN`, `AWS_CREDENTIAL_FILE`), with phantom values for the access key pair and `AWS_EC2_METADATA_DISABLED=true` to block the instance metadata fallback too. opencode's AWS SDK only ever sees the phantoms, or nothing. nono strips whatever it sent and substitutes the real signature before the request leaves the proxy. You don't need a keychain entry here either, since credentials come straight from the host's AWS config, read by the unsandboxed proxy.

## Detach and Attach

Run opencode in a detached session that survives terminal disconnects:

```bash
nono run --profile opencode --detached -- opencode
```

Reattach from any terminal:

```bash
nono attach <session-id>
```

The `nono-status` command (registered by the plugin) shows the active session ID and capability set.

## Install

```bash
nono pull nolabs-ai/opencode
```

Or let nono prompt you on first use:

```bash
nono run --profile opencode -- opencode
```

## Activation

After pulling, opencode reads the plugin from `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts` and the skill from `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/SKILL.md`. Both are symlinked from the pack store and update automatically on `nono pull`. If `XDG_CONFIG_HOME` is unset, the default `~/.config` applies.

## Removing

```bash
nono remove nolabs-ai/opencode
```

## Package Metadata

- Name: `opencode`
- Version: `0.2.0`
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
