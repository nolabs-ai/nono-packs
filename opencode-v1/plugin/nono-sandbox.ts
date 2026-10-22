import { spawnSync } from "child_process"
import * as fs from "fs"
import * as path from "path"

const DENIAL_PATTERN =
  /operation not permitted|permission denied|eperm|eacces|sandbox.*denied|landlock/i

// Matches an absolute or home-relative path only at a token boundary (start
// of text, whitespace, or a quote/bracket). Anchoring matters: the previous
// unanchored pattern matched the first "/" inside a relative path, so
// "src/main.ts" fabricated the root-absolute path "/main.ts".
const ABS_PATH_RE = /(?:^|[\s"'`([{])((?:~\/|\/)[^\s"'`,;:]+)/

// Matches a complete relative path token ("src/main.ts",
// "./.opencode/package.json") so it can be resolved whole instead of being
// mistaken for an absolute path fragment.
const REL_PATH_RE = /(?:^|[\s"'`([{])((?:\.{1,2}\/)?[\w.-]+(?:\/[\w.-]+)+)/

// Appended when a failure looks like a permission denial but nono's role
// could not be confirmed. Mirrors the packs' shared guidance: without
// confirmation, do not present the failure as a sandbox denial or offer
// sandbox grants as the remedy.
const UNCONFIRMED_NOTE =
  "\n\n[nono sandbox] Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis."

const NONO_STATUS_DESCRIPTION = "Show nono sandbox status for this opencode session"

type CredentialRoute = {
  upstream: string
  credential_key: string
  inject_header: string
  env_var?: string
}

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
  const abs = ABS_PATH_RE.exec(text)
  if (abs) {
    const candidate = abs[1].replace(/[).\]]+$/, "")
    if (candidate.startsWith("~/")) {
      const expanded = (process.env.HOME ?? "~") + "/" + candidate.slice(2)
      return expanded.length > 1 ? expanded : null
    }
    if (candidate.length > 1) return candidate
  }
  const rel = REL_PATH_RE.exec(text)
  if (rel) {
    const candidate = rel[1].replace(/[).\]]+$/, "")
    // Reject slash-containing words that are not plausible paths ("and/or",
    // "example.com/a/b"): a relative path token either starts with a dot
    // segment (".opencode/...", "./...", "../...") or ends in a file-like
    // segment carrying an extension.
    const segments = candidate.split("/")
    const last = segments[segments.length - 1]
    if (candidate.startsWith(".") || last.includes(".")) {
      return path.resolve(process.cwd(), candidate)
    }
  }
  return null
}

// Confirm with nono itself that the sandbox denies this path before any
// grant remediation is offered. `nono why --self` prints DENIED or ALLOWED
// as its first output line. Any failure to run or parse the check counts as
// unconfirmed: an unconfirmed failure must not be presented as a nono
// denial.
function confirmNonoDenial(blockedPath: string): boolean {
  try {
    const res = spawnSync("nono", ["why", "--self", "--path", blockedPath, "--op", "read"], {
      encoding: "utf8",
      timeout: 5000,
    })
    if (res.error || typeof res.stdout !== "string") return false
    const firstLine = res.stdout
      .replace(/\x1b\[[0-9;]*m/g, "")
      .split("\n")
      .map(l => l.trim())
      .find(l => l.length > 0)
    return firstLine === "DENIED"
  } catch {
    return false
  }
}

// A concrete path is only ever confirmed by `nono why` reporting DENIED for
// it. The word "nono" in the error text proves nothing about a path — it
// appears in paths themselves (including nono's own config directory, e.g.
// ~/.config/nono/profiles/...) and must never skip the provenance check.
// Only when no path could be extracted does error output that explicitly
// names nono count as self-attributed.
function isConfirmedDenial(text: string, blockedPath: string | null): boolean {
  if (blockedPath) return confirmNonoDenial(blockedPath)
  return /\bnono\b/i.test(text)
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
  if (keys.length === 0) return "  (none enabled — add routes to network.credentials in your profile)"
  return keys
    .map(name => {
      const r = routes[name]
      const envVar = r.env_var ?? r.credential_key
      const present = Boolean(process.env[envVar])
      return `  ${name}: ${r.upstream}  [${present ? "key present" : "key missing — set " + envVar}]`
    })
    .join("\n")
}

function buildDomainLines(caps: Caps): string {
  const domains = caps.allowed_domains ?? []
  if (domains.length === 0) {
    return caps.net_blocked
      ? "  (all outbound network blocked)"
      : "  (no allowlist — all outbound network allowed)"
  }
  return domains.map(d => "  " + d).join("\n")
}

function buildEgressGuidance(caps: Caps): string {
  const domains = caps.allowed_domains ?? []
  if (caps.net_blocked) {
    return "All outbound network is blocked. Retries, alternate endpoints, or proxies cannot bypass this — do not attempt workarounds."
  }
  if (domains.length === 0) {
    return "No host allowlist is in effect; all outbound network is allowed."
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
    ? `nono why --self --path ${blockedPath} --op read`
    : "nono why --self --path <blocked-path> --op read"
  const allowCmd = blockedPath
    ? `nono run --profile nolabs-ai/opencode-v1 --allow ${blockedPath} -- opencode`
    : "nono run --profile nolabs-ai/opencode-v1 --allow <blocked-path> -- opencode"

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
    "                          extending `nolabs-ai/opencode-v1`, add the path under `\"allow\"` or `\"read\"`,",
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
1. Run: nono why --self --path <blocked-path> --op <read|write|readwrite>
2. Offer the user exactly two options:
   Option A: nono run --profile nolabs-ai/opencode-v1 --allow /path/to/needed -- opencode
   Option B: draft ${profileDraftsDir()}/<name>.json extending "nolabs-ai/opencode-v1", then have the user run nono profile promote <name>

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

// Shared by both plugin generations: append a guidance block to a v2-style
// content value (a plain string or an array of { type: "text", text } parts),
// returning the updated value.
function appendContentGuidance(content: unknown, guidance: string): unknown {
  if (typeof content === "string") return content + guidance
  if (Array.isArray(content)) {
    const parts = [...content]
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
    return parts
  }
  if (content === undefined || content === null) {
    return [{ type: "text", text: guidance }]
  }
  return content
}

// v1 hook object. OpenCode 1.18.29+ calls server(); this path is kept until
// the v1 support window ends, then this function is deleted with the
// `async server()` binding below.
function v1Hooks() {
  const caps = readCaps()

  return {
    // Inject nono context into the system prompt so the model knows the rules
    ...(caps
      ? {
          "experimental.chat.system.transform": async (
            _input: unknown,
            output: { system: string[] },
          ) => {
            const context = buildSystemContext(caps)
            if (output.system.length > 0) output.system[0] += "\n\n" + context
            else output.system.push(context)
          },
        }
      : {}),

    // Custom tool nono_status that outputs caps
    tool: {
      nono_status: {
        description: NONO_STATUS_DESCRIPTION,
        args: {},
        execute: async () => ({
          title: "nono sandbox status",
          output: buildStatusReport(readCaps()),
        }),
      },
    },

    // Fires after every tool call. The v1 result carries no structured
    // status, so the result text is scanned for a denial signature — but
    // grant remediation is appended only once `nono why --self` reports
    // DENIED for the extracted path. With no extractable path there is
    // nothing to provenance-check, and the word fallback cannot confirm
    // anything here: v1 cannot distinguish a failed call from a successful
    // result whose content merely mentions nono and a denial, so nothing
    // is appended — a false notice is worse than none.
    "tool.execute.after": async (
      input: { tool: string; sessionID: string; callID: string; args: unknown },
      result: unknown,
    ) => {
      const resultText = JSON.stringify(result)
      if (!DENIAL_PATTERN.test(resultText)) return

      const liveCaps = readCaps()
      if (!liveCaps) return

      const blockedPath = extractPath(JSON.stringify(input)) ?? extractPath(resultText)
      if (!blockedPath) return
      if (!confirmNonoDenial(blockedPath)) return

      appendGuidance(result, buildGuidance(liveCaps, blockedPath))
    },
  }
}

// v1 result mutation. OpenCode v1 carries display text in `output`, while
// MCP-style tools can carry `content` parts.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function appendGuidance(result: any, guidance: string): void {
  if (!result || typeof result !== "object") return
  const r = result as Record<string, unknown>

  if (typeof r.output === "string") {
    r.output = r.output + guidance
    return
  }
  if (Array.isArray(r.content)) {
    r.content = appendContentGuidance(r.content, guidance)
  }
}

// The v2 loader validates the default export by shape: it needs `id` plus a
// `setup` function. `Plugin.define` from "@opencode/plugin" is only an
// identity helper, so we export the object literal directly instead. This
// keeps the plugin self-contained (no node_modules) so it loads as a raw
// file in both v1 (which calls `server`) and v2 (which calls `setup`).
export default {
  id: "nono-sandbox",

  // v2 default entrypoint. OpenCode 2.x calls setup(ctx); hooks, tools, and
  // transforms registered here are scoped to the plugin and disposed on
  // unload, so there is no cleanup function to return.
  async setup(ctx: any) {
    if (!insideNono()) return

    const caps = readCaps()

    // Inject nono context before each agent model request so the model knows
    // the rules. Context structures use a system parts array in v2.
    if (caps) {
      await ctx.session.hook("context", (event: any) => {
        const system = event.system ?? (event.system = [])
        system.push({ type: "text", text: buildSystemContext(caps) })
      })
    }

    // Custom tool nono_status that outputs caps. Tool schemas are JSON
    // Schema; execution returns structured content.
    await ctx.tool.transform((editor: any) => {
      editor.add({
        name: "nono_status",
        description: NONO_STATUS_DESCRIPTION,
        input: {
          type: "object",
          properties: {},
          additionalProperties: false,
        },
        execute: async () => ({ content: buildStatusReport(readCaps()) }),
      })
    })

    // Fires after every tool call. Detection is driven by the structured
    // outcome, never by scanning content: only error events are examined,
    // and only their error payload. A successful result is data — a file
    // that merely mentions "EPERM" or "permission denied" must not draw a
    // sandbox-denial notice. Before grant remediation is appended, nono's
    // role is confirmed (the error names nono, or `nono why --self` reports
    // DENIED for the extracted path); unconfirmed failures get a short note
    // saying so instead of definitive sandbox guidance.
    await ctx.tool.hook("execute.after", (event: any) => {
      if (event.status !== "error") return

      const errorText = JSON.stringify(event.error ?? "")
      if (!DENIAL_PATTERN.test(errorText)) return

      const liveCaps = readCaps()
      if (!liveCaps) return

      const blockedPath =
        extractPath(errorText) ?? extractPath(JSON.stringify(event.input ?? ""))
      const note = isConfirmedDenial(errorText, blockedPath)
        ? buildGuidance(liveCaps, blockedPath)
        : UNCONFIRMED_NOTE

      if (event.error && typeof event.error.message === "string") {
        event.error.message += note
      }
    })
  },

  // v1 entrypoint. OpenCode 1.18.29+ calls server(); remove this binding (and
  // v1Hooks above) once the v1 support window ends.
  async server() {
    if (!insideNono()) return {}
    return v1Hooks()
  },
}
