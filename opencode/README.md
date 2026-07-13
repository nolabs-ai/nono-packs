# opencode nono

`opencode` is a `nono` package for [opencode](https://github.com/opencode-ai/opencode).

It installs a sandbox profile, a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox — including credential injection, detach/attach session support, and denial diagnostics.

## What It Does

The pack provides:

- a sandbox profile (`policy.json`) granting the correct filesystem and network access, with credential injection routes for OpenAI, Anthropic, Gemini, GitHub, GitLab, and AWS Bedrock (SigV4/SSO, one route per supported Region)
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

nono intercepts outbound HTTPS and injects API keys from its keychain — opencode never sees the raw secret. Routes are defined in the profile but **disabled by default**.

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

The `bedrock_*` routes use a different mechanism than the static-key routes above: instead of injecting a header from a stored secret, nono intercepts the request and re-signs it with real AWS SigV4 credentials resolved from the standard AWS credential chain — including AWS SSO profiles. Requires `nono` >= `0.67.0`.

AWS SigV4 signing is pinned to a region (the signature covers the target region), so there is one route per Bedrock-supported AWS Region rather than a single generic `bedrock` route. Route names follow the pattern `bedrock_<region>` (e.g. `bedrock_us_east_1`, `bedrock_eu_west_1`, `bedrock_us_gov_west_1`), where `<region>` is the AWS region code with dashes replaced by underscores. Run `nono profile show opencode` or inspect `network.custom_credentials` in `policy.json` for the exact list of defined routes, and cross-reference the [official Amazon Bedrock endpoint list](https://docs.aws.amazon.com/general/latest/gr/bedrock.html) to find the region code matching your Bedrock access.

GovCloud routes (`bedrock_us_gov_east_1`, `bedrock_us_gov_west_1`) require a separate GovCloud AWS account and credential chain; they will not resolve credentials from a commercial-partition SSO profile.

Enable the route for your region the same way as any other route:

```json
{
  "extends": "opencode",
  "meta": { "name": "opencode-with-bedrock", "version": "1.0.0" },
  "network": { "credentials": ["bedrock_us_east_1"] }
}
```

By default a route resolves credentials from the host's default AWS profile (`~/.aws/config`/`~/.aws/credentials`, including `sso_session` profiles logged in via `aws sso login`). To pin a specific named profile, override `aws_auth.profile` in an extending profile:

```json
{
  "extends": "opencode",
  "meta": { "name": "opencode-with-bedrock", "version": "1.0.0" },
  "network": {
    "credentials": ["bedrock_us_east_1"],
    "custom_credentials": {
      "bedrock_us_east_1": { "aws_auth": { "profile": "my-sso-profile" } }
    }
  }
}
```

The base profile also denies `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, and `AWS_PROFILE` from reaching the sandboxed opencode process, replacing the access key pair with phantom placeholders. This keeps real AWS credentials off the sandboxed process entirely — opencode's AWS SDK client only ever sees the phantom values; nono strips them and substitutes the real SigV4 signature before the request leaves the proxy.

No keychain entry is needed for these routes; AWS credentials are read from the host's AWS config by the (unsandboxed) nono proxy, not from the keychain.

## Detach and Attach

Run opencode in a detached session that survives terminal disconnects:

```bash
nono run --profile opencode --detach -- opencode
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
