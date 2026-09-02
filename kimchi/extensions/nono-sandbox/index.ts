import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ToolResultEvent } from "@earendil-works/pi-coding-agent";
import { DENIAL_PATTERNS, denialGuidance, systemContext } from "./prompts";

function insideNono(): boolean {
	return Boolean(process.env.NONO_CAP_FILE);
}

// Path to the per-session rendered guidance doc, set by session_start.
// before_agent_start reads this to inject a pointer into the system prompt.
let renderedDocPath: string | null = null;

// Resolve the template path relative to this module so it works both in local
// dev and when installed under $NONO_PACKAGES/always-further/kimchi/.
function templatePath(): string | null {
	try {
		return join(dirname(fileURLToPath(import.meta.url)), "nono-sandbox.md.tpl");
	} catch {
		return null;
	}
}

// Parse --profile/-p and the tail (everything after --) from the nono
// command line. The before-hook captures the full command as a single
// string; we extract the parts here rather than tokenising in shell.
function parseNonoCommand(command: string): { profile: string; tail: string } {
	const tokens = command.split(/\s+/).filter((t) => t.length > 0);
	let profile = "";
	let tail = "";

	for (let i = 0; i < tokens.length; i++) {
		const tok = tokens[i];
		if ((tok === "--profile" || tok === "-p") && i + 1 < tokens.length) {
			profile = tokens[i + 1];
			i++;
		} else if (tok.startsWith("--profile=")) {
			profile = tok.slice("--profile=".length);
		} else if (tok.startsWith("-p=")) {
			profile = tok.slice("-p=".length);
		} else if (tok === "--") {
			tail = tokens.slice(i + 1).join(" ");
			break;
		}
	}

	return { profile, tail };
}

// Render the per-session guidance doc from the template using the command
// line captured by the nono before-hook (hooks/before.sh). Fail-soft:
// missing template or hook vars produce a minimal doc rather than throwing.
function renderGuidanceDoc(): string | null {
	const capFile = process.env.NONO_CAP_FILE;
	if (!capFile) return null;

	const command = process.env.KIMCHI_NONO_COMMAND || "";

	// Hook did not run or failed to populate the command line.
	if (!command) {
		return [
			"# Working inside a nono sandbox",
			"",
			"Per-session guidance is unavailable: the nono before-hook did not populate KIMCHI_NONO_COMMAND.",
			"Diagnose denials with:",
			"  nono why --self --path <blocked-path> --op <read|write|readwrite>",
			"",
			`Capability manifest: ${capFile}`,
		].join("\n");
	}

	const tplPath = templatePath();
	let template: string;
	try {
		template = tplPath ? readFileSync(tplPath, "utf8") : "";
	} catch {
		template = "";
	}
	if (!template) {
		return [
			"# Working inside a nono sandbox",
			"",
			"Guidance template is missing. Diagnose denials with:",
			"  nono why --self --path <blocked-path> --op <read|write|readwrite>",
			"",
			`Capability manifest: ${capFile}`,
		].join("\n");
	}

	const { profile, tail } = parseNonoCommand(command);
	const profileDisplay = profile || "(none)";
	const tailDisplay = tail || "(none)";

	return template
		.replaceAll("{{NONO_COMMAND}}", command)
		.replaceAll("{{NONO_PROFILE}}", profileDisplay)
		.replaceAll("{{NONO_TAIL}}", tailDisplay)
		.replaceAll("{{NONO_CAP_FILE}}", capFile);
}

function textFromEvent(event: ToolResultEvent): string {
	return event.content
		.filter((item) => item.type === "text")
		.map((item) => item.text)
		.join("\n");
}

function looksLikeDenial(event: ToolResultEvent): boolean {
	// Sandbox denials can appear as warnings in successful tool output (e.g.
	// `go env` exits 0 but prints 'operation not permitted' to stderr), so
	// we scan both error and success results. The patterns are specific
	// enough that false positives on normal output are unlikely.
	const haystack = [event.toolName, textFromEvent(event), JSON.stringify(event.details ?? {})].join("\n");
	return DENIAL_PATTERNS.some((pattern) => pattern.test(haystack));
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (!insideNono()) return;

		// Render the per-session guidance doc next to the cap file. The hook
		// (hooks/before.sh) populates KIMCHI_NONO_COMMAND on the host; this
		// parses it and writes a rendered .md the system prompt points at.
		const doc = renderGuidanceDoc();
		if (doc) {
			const outPath = `${process.env.NONO_CAP_FILE}.nono-sandbox.md`;
			try {
				writeFileSync(outPath, doc);
				renderedDocPath = outPath;
			} catch {
				renderedDocPath = null;
			}
		}

		if (ctx.hasUI) {
			ctx.ui.notify("running inside nono sandbox", "warning");
			ctx.ui.setStatus("nono", "nono sandbox");
		}
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!insideNono()) return undefined;
		if (!renderedDocPath) {
			ctx.ui.notify("failed to find nono docs file", "warning");
			return undefined;
		}
		return {
			systemPrompt: `${event.systemPrompt}\n\n${systemContext(renderedDocPath)}`,
		};
	});

	pi.on("tool_result", async (event, ctx) => {
		if (!insideNono() || !looksLikeDenial(event)) return undefined;

		if (ctx.hasUI && event.isError) {
			ctx.ui.notify("nono sandbox denial detected", "warning");
		}

		if (!renderedDocPath) {
			ctx.ui.notify("failed to find nono docs file", "warning");
			return undefined;
		}

		// Send the guidance as a steering message rather than mutating the tool
		// result. The model treats tool results as factual data about what the
		// tool returned, not as actionable instructions — burying guidance in
		// the error output causes it to be ignored. A steer message lands as a
		// separate user-role instruction the model will follow.
		pi.sendMessage(
			{ customType: "nono-sandbox-denial", content: [{ type: "text", text: denialGuidance(renderedDocPath) }], display: false },
			{ triggerTurn: true, deliverAs: "steer" },
		);
		return undefined;
	});

	pi.registerCommand("nono-status", {
		description: "Summarize nono sandbox capabilities for this Pi session using the LLM",
		handler: async (_args, ctx) => {
			const capFile = process.env.NONO_CAP_FILE;
			if (!capFile) {
				ctx.ui.notify("Kimchi is not running inside a nono session.", "info");
				return;
			}

			if (!existsSync(capFile)) {
				ctx.ui.notify(`nono capability file is not readable: ${capFile}`, "warning");
				return;
			}

			const contents = readFileSync(capFile, "utf8").trim();
			if (!contents) {
				ctx.ui.notify(`nono capability file is empty: ${capFile}`, "info");
				return;
			}

			const command = process.env.KIMCHI_NONO_COMMAND || "";
			const { profile } = parseNonoCommand(command);

			const prompt = [
				`Summarize the current nono sandbox capabilities below. Start with the profile name which for current session is: ${profile}`,
				"Give a concise, structured overview of what is allowed and what is denied (filesystem paths, network egress, environment, other capabilities).",
				"Do not suggest remediation — just describe the current state.",
				"",
				`Capability file: ${capFile}`,
				"",
				"```",
				contents,
				"```",
			].join("\n");

			ctx.ui.notify("Summarizing nono capabilities…", "info");

			pi.sendMessage(
				{ customType: "nono-status-request", content: prompt, display: false },
				{ triggerTurn: true, deliverAs: ctx.isIdle() ? "steer" : "followUp" },
			);
		},
	});
}
