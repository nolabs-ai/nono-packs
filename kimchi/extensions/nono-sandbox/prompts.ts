// nono sandbox prompts and denial patterns.
//
// SYSTEM_CONTEXT and DENIAL_GUIDANCE are kept deliberately short: the full
// remediation recipe (one-off restart, profile draft, nono why) lives in the
// per-session rendered doc at <renderedPath> (a sibling of NONO_CAP_FILE named
// <cap-file>.nono-sandbox.md, written by session_start). The path is injected
// at runtime by the extension's before_agent_start / tool_result handlers,
// since it depends on NONO_CAP_FILE which varies per session.

export const DENIAL_PATTERNS = [
	/operation not permitted/i,
	/permission denied/i,
	/\bEACCES\b/i,
	/\bEPERM\b/i,
	/landlock/i,
	/sandbox(?:ed)?:?\s+deny/i,
	/sandbox denied/i,
];

// Injected into the system prompt at before_agent_start when inside nono.
// `renderedPath` is the per-session guidance doc written by session_start;
// may be null if rendering failed, in which case we still tell the model it
// is sandboxed and how to recognize denials.
export function systemContext(renderedPath: string): string {
	return `
You are running inside nono, an outer OS-level sandbox. nono filesystem and network limits are enforced by the operating system before Kimchi starts. Kimchi approvals, retries, chmod, chown, sudo, or macOS Full Disk Access cannot grant access that nono has not allowed.

If a tool or shell command fails with Operation not permitted, Permission denied, EACCES, EPERM, landlock, sandbox deny, or sandbox denied, it could be a nono sandbox boundary, not a Unix permission problem.

If you're trying to execute go, python, rust, npm or any other developer tool and it fails for an unknown reason, chances are nono is blocking these tools. 

For remediation guidance, read: ${renderedPath}
`.trim();
}

// Appended to the tool_result content when a denial is detected.
// `renderedPath` is the per-session guidance doc; may be null.
export function denialGuidance(renderedPath: string): string {
	return `
[nono sandbox diagnostic]
This looks like an outer nono sandbox denial, not a Unix permission problem.

Next step:
  nono why --self --path <blocked-path> --op <read|write|readwrite>

Read this file for detailed guidance on how to fix this issue: ${renderedPath}

Do not suggest sudo, chmod, chown, Full Disk Access, or Kimchi approval changes for this denial.
Do not try to workaround the issue. Instead, follow guidelines here: ${renderedPath}
`.trim();
}
