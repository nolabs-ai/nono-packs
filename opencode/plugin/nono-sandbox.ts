import * as fs from "fs"

const DENIAL_PATTERN =
  /operation not permitted|permission denied|eperm|eacces|sandbox.*denied|landlock/i

const PATH_RE = /(?:~\/|\/)[^\s"'`,;:]+/

// Static routes (openai, anthropic, gemini, github, gitlab) always carry
// both credential_key and inject_header.
// aws_auth routes (bedrock_<region>) carry neither — nono resolves and signs with real
// AWS credentials instead of injecting a stored key. The two shapes are mutually
// exclusive on every route this pack defines.
type StaticCredentialRoute = {
  upstream: string
  credential_key: string
  inject_header: string
  env_var?: string
}

type AwsAuthCredentialRoute = {
  upstream: string
  aws_auth: { profile?: string; region?: string; service?: string }
}

type CredentialRoute = StaticCredentialRoute | AwsAuthCredentialRoute

type Caps = {
  fs?: Array<{ path: string; resolved?: string; access: string }>
  net_blocked?: boolean
  allowed_domains?: string[]
  credentials?: Record<string, CredentialRoute>
  session_id?: string
}

function insideNono(): boolean {
  return Boolean(process.env.NONO_CAP_FILE)
}

function readCaps(): Caps | null {
  const capFile = process.env.NONO_CAP_FILE
  if (!capFile) return null
  try {
    return JSON.parse(fs.readFileSync(capFile, "utf8")) as Caps
  } catch {
    return null
  }
}

function extractPath(text: string): string | null {
  const match = PATH_RE.exec(text)
  if (!match) return null
  let candidate = match[0].replace(/[).\]]+$/, "")
  if (candidate.startsWith("~/")) {
    candidate = (process.env.HOME ?? "~") + "/" + candidate.slice(2)
  }
  return candidate || null
}

function nonoConfigHome(): string {
  return (process.env.XDG_CONFIG_HOME ?? `${process.env.HOME ?? "~"}/.config`) + "/nono"
}

function profileDraftsDir(): string {
  return nonoConfigHome() + "/profile-drafts"
}

function buildCredentialLines(caps: Caps): string {
  const routes = caps.credentials ?? {}
  const keys = Object.keys(routes)
  if (keys.length === 0) {
    // NONO_CAP_FILE never populates `credentials` on nono 0.69.0/0.70.0, even with
    // custom_credentials active, so this branch always runs. Don't claim "none enabled"
    // — with bedrock_* active by default that's false. Revisit if nono starts reporting it.
    return "  (not reported by this nono version — check network.credentials in policy.json for active routes)"
  }
  return keys
    .map(name => {
      // NONO_CAP_FILE is parsed from an external file at runtime (readCaps) and isn't
      // schema-validated against CredentialRoute, so `r` may be null, a primitive, or an
      // object shaped like neither known route type. Guard before any property access —
      // the `in` operator throws on null/non-object operands.
      const r = routes[name]
      if (r === null || typeof r !== "object") {
        return `  ${name}: [misconfigured — route entry is not an object]`
      }

      const hasAwsAuth =
        "aws_auth" in r && typeof r.aws_auth === "object" && r.aws_auth !== null && !Array.isArray(r.aws_auth)
      const hasCredentialKey = "credential_key" in r && typeof r.credential_key === "string" && r.credential_key !== ""
      const upstream = typeof r.upstream === "string" ? r.upstream : "<unknown upstream>"

      if (hasAwsAuth && hasCredentialKey) {
        // The two route shapes are mutually exclusive by design (see the type comment
        // above). A route carrying both is malformed data, not a valid aws_auth route —
        // report it as invalid rather than silently picking one mechanism over the other.
        return `  ${name}: ${upstream}  [misconfigured — route defines both aws_auth and credential_key]`
      }

      if (hasAwsAuth) {
        // Report whether a profile is pinned without echoing its name: this text can be
        // appended to tool-call results that flow back into the model's context, and a
        // profile name may be an internal alias the user doesn't want sent to a model provider.
        const desc =
          typeof r.aws_auth.profile === "string" && r.aws_auth.profile !== ""
            ? "SigV4 signed via a pinned AWS profile"
            : "SigV4 signed via default AWS credential chain (supports SSO)"
        return `  ${name}: ${upstream}  [${desc}]`
      }
      if (hasCredentialKey) {
        // env_var must also be a non-empty string — it's used as a process.env lookup key
        // below, and a malformed non-string value from an unvalidated NONO_CAP_FILE could
        // otherwise reach that indexing operation.
        const envVar =
          typeof r.env_var === "string" && r.env_var !== "" ? r.env_var : r.credential_key
        const present = Boolean(process.env[envVar])
        return `  ${name}: ${upstream}  [${present ? "key present" : "key missing — set " + envVar}]`
      }
      return `  ${name}: ${upstream}  [misconfigured — no credential mechanism defined]`
    })
    .join("\n")
}

// This pack activates several bedrock_<region> credential routes by default (see
// policy.json's network.credentials). On nono < 0.70.0 that alone silently narrows an
// otherwise-open network policy to only those routes' upstream hosts, while
// NONO_CAP_FILE still reports an empty allowlist (nolabs-ai/nono#1485, fixed in #1497 /
// v0.70.0). Without this caveat, buildEgressGuidance/buildStatusReport would tell the
// model "all outbound network is allowed" on exactly the versions where that's false.
const STALE_ALLOWLIST_CAVEAT =
  "Caveat: on nono older than 0.70.0, this pack's active AWS Bedrock credential routes can silently narrow this to only the Bedrock hosts (nolabs-ai/nono#1485, fixed in v0.70.0), even though this report says otherwise. If a non-Bedrock request unexpectedly fails despite this message, run `nono --version` and upgrade before concluding the connection is genuinely blocked."

function buildDomainLines(caps: Caps): string {
  const domains = caps.allowed_domains ?? []
  if (domains.length === 0) {
    return caps.net_blocked
      ? "  (all outbound network blocked)"
      : "  (no allowlist reported — all outbound network should be allowed; " + STALE_ALLOWLIST_CAVEAT + ")"
  }
  return domains.map(d => "  " + d).join("\n")
}

function buildEgressGuidance(caps: Caps): string {
  const domains = caps.allowed_domains ?? []
  if (caps.net_blocked) {
    return "All outbound network is blocked. Retries, alternate endpoints, or proxies cannot bypass this — do not attempt workarounds."
  }
  if (domains.length === 0) {
    return "No host allowlist is reported; all outbound network should be allowed. " + STALE_ALLOWLIST_CAVEAT
  }
  return [
    "Network egress is default-deny; only these hosts are reachable. Any other outbound connection fails by design — retries, alternate endpoints, or proxies cannot bypass it, so do not attempt workarounds:",
    buildDomainLines(caps),
  ].join("\n")
}

function buildGuidance(caps: Caps, blockedPath: string | null): string {
  const pathLines =
    (caps.fs ?? [])
      .map(e => "  " + (e.resolved ?? e.path) + " (" + e.access + ")")
      .join("\n") || "  (none)"
  const net = caps.net_blocked ? "blocked" : "allowed"
  const display = blockedPath ?? "<blocked-path>"
  const whyCmd = blockedPath
    ? `nono why --path ${blockedPath} --op read`
    : "nono why --path <blocked-path> --op read"
  const allowCmd = blockedPath
    ? `nono run --allow ${blockedPath} -- opencode`
    : "nono run --allow <blocked-path> -- opencode"

  return [
    "",
    "---",
    "**[nono sandbox]** This is a sandbox permission denial — not a Unix or macOS permissions issue.",
    "Do NOT suggest sudo, chmod, or system permission changes.",
    "",
    "Blocked path: " + display,
    "",
    "Allowed paths in this session:",
    pathLines,
    "Network: " + net,
    "",
    "Reachable hosts (allowlist):",
    buildDomainLines(caps),
    "",
    "Active credential routes:",
    buildCredentialLines(caps),
    "",
    "Next steps (in order):",
    "1. Run `" + whyCmd + "` and include output verbatim.",
    "2. Present the user with exactly these two options:",
    "   Option A (quick fix):  " + allowCmd,
    "   Option B (persistent): draft a profile to " + profileDraftsDir() + "/<name>.json",
    "                          extending `opencode`, add the path under `\"allow\"` or `\"read\"`,",
    "                          then tell the user: run `nono profile promote <name>`",
    "                          and start future sessions with `nono run --profile <name> -- opencode`",
  ].join("\n")
}

function buildSystemContext(caps: Caps): string {
  const sessionId = caps.session_id ?? process.env.NONO_SESSION_ID
  const reattachNote = sessionId
    ? `\nSession ID: ${sessionId}. To reattach after detaching: nono attach ${sessionId}`
    : ""

  return `
You are running inside nono, an OS-level security sandbox. nono enforces filesystem and network limits via Landlock (Linux) or Seatbelt (macOS) before opencode starts.

sudo, chmod, chown, retries, or macOS Full Disk Access cannot grant access that nono has not allowed.${reattachNote}

If a tool or shell command fails with "Operation not permitted", "Permission denied", EACCES, EPERM, landlock, or sandbox denied:
1. Run: nono why --path <blocked-path> --op <read|write|readwrite>
2. Offer the user exactly two options:
   Option A: nono run --allow /path/to/needed -- opencode
   Option B: draft ${profileDraftsDir()}/<name>.json extending "opencode", then have the user run nono profile promote <name>

Credential injection is active for configured routes. Do not read or write API keys directly — nono injects them transparently via its proxy.

${buildEgressGuidance(caps)}

Do not edit ${nonoConfigHome()}/profiles or ${nonoConfigHome()}/packages from inside the sandbox.
`.trim()
}

function buildStatusReport(caps: Caps | null): string {
  if (!caps) return "Not running inside a nono session (NONO_CAP_FILE is not set)."

  const sessionId = caps.session_id ?? process.env.NONO_SESSION_ID
  const net = caps.net_blocked ? "blocked" : "allowed"
  const fsPaths = (caps.fs ?? [])
    .map(e => "  " + (e.resolved ?? e.path) + " (" + e.access + ")")
    .join("\n") || "  (none)"

  const lines = [
    "nono sandbox: active",
    sessionId ? "session: " + sessionId + "  (reattach: nono attach " + sessionId + ")" : "",
    "network: " + net,
    "reachable hosts:",
    buildDomainLines(caps),
    "filesystem:",
    fsPaths,
    "credential routes:",
    buildCredentialLines(caps),
  ]
  return lines.filter(Boolean).join("\n")
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function appendGuidance(result: any, guidance: string): unknown {
  if (!result || typeof result !== "object") return result
  const r = result as Record<string, unknown>
  if (typeof r.content === "string") {
    return { ...r, content: r.content + guidance }
  }
  if (Array.isArray(r.content)) {
    const parts = [...r.content]
    const lastText = parts
      .map(p => typeof (p as { text?: unknown }).text === "string")
      .lastIndexOf(true)
    if (lastText >= 0) {
      parts[lastText] = {
        ...(parts[lastText] as object),
        text: (parts[lastText] as { text: string }).text + guidance,
      }
    } else {
      parts.push({ type: "text", text: guidance })
    }
    return { ...r, content: parts }
  }
  return result
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const NonoSandboxPlugin = async (ctx: any) => {
  if (!insideNono()) return {}

  const caps = readCaps()

  // Register nono-status command if the context supports it
  if (ctx && typeof ctx.registerCommand === "function") {
    ctx.registerCommand("nono-status", {
      description: "Show nono sandbox status for this opencode session",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      handler: async (_args: any) => buildStatusReport(readCaps()),
    })
  }

  return {
    // Inject nono context into the system prompt so the model knows the rules
    // before the first tool call. Fall back gracefully if opencode's plugin API
    // doesn't support this field yet.
    ...(caps ? { system: { inject: buildSystemContext(caps) } } : {}),

    tool: {
      execute: {
        description: "Internal middleware hook for the nono sandbox interception layer. Do not invoke directly.",
        // Fires after every tool call. When the result contains a denial
        // signature we append capability context and Option A/B remediation.
        after: async (input: unknown, result: unknown) => {
          if (!DENIAL_PATTERN.test(JSON.stringify(result))) return result

          const liveCaps = readCaps()
          if (!liveCaps) return result

          const inputText = JSON.stringify(input)
          const resultText = JSON.stringify(result)
          const blockedPath = extractPath(inputText) ?? extractPath(resultText)

          return appendGuidance(result, buildGuidance(liveCaps, blockedPath))
        },
      },
    },
  }
}
