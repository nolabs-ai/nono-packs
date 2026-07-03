"""Hermes plugin for nono sandbox diagnostics."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any


DENIAL_RE = re.compile(
    r"operation not permitted|permission denied|eperm|eacces|landlock|sandbox.*denied",
    re.IGNORECASE,
)
PATH_RE = re.compile(r"(?:~/|/)[^\s\"'`,;:]+")
_ANNOUNCED: set[str] = set()
_PENDING_DENIAL_CONTEXT: dict[str, str] = {}
PROXY_ENV_NAMES = (
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "http_proxy",
    "https_proxy",
    "NO_PROXY",
    "no_proxy",
    "OPENAI_BASE_URL",
    "ANTHROPIC_BASE_URL",
    "GEMINI_BASE_URL",
    "SSL_CERT_FILE",
    "REQUESTS_CA_BUNDLE",
    "NODE_EXTRA_CA_CERTS",
    "CURL_CA_BUNDLE",
    "GIT_SSL_CAINFO",
    "NONO_PROXY_TOKEN",
)


def _session_key(args: tuple[Any, ...], kwargs: dict[str, Any]) -> str:
    return str(
        kwargs.get("session_id")
        or kwargs.get("task_id")
        or kwargs.get("conversation_id")
        or "default"
    )


def _cap_file() -> Path | None:
    value = os.environ.get("NONO_CAP_FILE")
    if not value:
        return None
    path = Path(value)
    if not path.is_file():
        return None
    return path


def _inside_nono() -> bool:
    return _cap_file() is not None


def _redact_env_value(name: str, value: str) -> str:
    if name == "NONO_PROXY_TOKEN":
        return "set"
    if name in {"HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"}:
        return re.sub(r"//[^/@]+@", "//<redacted>@", value)
    return value


def _proxy_status() -> dict[str, str]:
    status = {}
    for name in PROXY_ENV_NAMES:
        value = os.environ.get(name)
        if value:
            status[name] = _redact_env_value(name, value)
    return status


def _load_capabilities(limit: int = 24) -> str:
    path = _cap_file()
    if path is None:
        return "nono capability file is not available."

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return f"Could not read nono capabilities from {path}: {exc}"
    if not isinstance(data, dict):
        return f"Could not read nono capabilities from {path}: expected a JSON object."

    fs_entries = data.get("fs", [])
    if not isinstance(fs_entries, list):
        fs_entries = []
    lines = []
    for entry in fs_entries[:limit]:
        if not isinstance(entry, dict):
            lines.append("- <invalid capability entry>")
            continue
        resolved = entry.get("resolved") or entry.get("path") or "<unknown>"
        access = entry.get("access") or "unknown"
        lines.append(f"- {resolved} ({access})")
    if len(fs_entries) > limit:
        lines.append(f"- ... {len(fs_entries) - limit} more entries")

    network = "blocked" if data.get("net_blocked") else "allowed"
    if not lines:
        lines.append("- no filesystem capabilities listed")
    return "Filesystem:\n" + "\n".join(lines) + f"\nNetwork: {network}"


def _stringify(value: Any, max_chars: int = 6000) -> str:
    if isinstance(value, str):
        text = value
    else:
        try:
            text = json.dumps(value, sort_keys=True)
        except Exception:
            text = str(value)
    return text[:max_chars]


def _tool_fields(args: tuple[Any, ...], kwargs: dict[str, Any]) -> tuple[Any, Any, Any, Any]:
    tool_name = kwargs.get("tool_name") or kwargs.get("name")
    tool_args = kwargs.get("arguments") or kwargs.get("args") or kwargs.get("tool_input")
    result = kwargs.get("result")
    task_id = kwargs.get("task_id") or kwargs.get("tool_call_id")

    if tool_name is None and args:
        tool_name = args[0]
    if tool_args is None and len(args) > 1:
        tool_args = args[1]
    if result is None and len(args) > 2:
        result = args[2]
    if task_id is None and len(args) > 3:
        task_id = args[3]

    return tool_name, tool_args, result, task_id


def _extract_path(*values: Any) -> str | None:
    for value in values:
        text = _stringify(value)
        match = PATH_RE.search(text)
        if not match:
            continue
        candidate = match.group(0).rstrip(").]")
        if candidate.startswith("~/"):
            return str(Path.home() / candidate[2:])
        if candidate == "~":
            return str(Path.home())
        return candidate
    return None


def _denial_context(path: str | None, capabilities: str) -> str:
    display_path = path or "<blocked-path>"
    why = (
        f"nono why --self --path {display_path} --op read"
        if path
        else "nono why --self --path <blocked-path> --op read"
    )
    allow = (
        f"nono run --profile hermes --allow {display_path} -- hermes"
        if path
        else "nono run --profile hermes --allow <blocked-path> -- hermes"
    )

    return f"""[nono sandbox diagnostic]

The previous Hermes tool call appears to have hit the outer nono OS sandbox.
This is not macOS TCC, chmod, sudo, or a Hermes approval issue.

Blocked path: {display_path}

Current nono capabilities:
{capabilities}

Next steps for the assistant:
1. Do not retry the blocked tool call.
2. Run this diagnosis command if the path is concrete:
   {why}
3. Present the user with exactly two remediation choices:
   A. One-off restart:
      {allow}
   B. Persistent profile:
      create or extend ~/.config/nono/profile-drafts/<name>.json with the minimum filesystem grant.
      The user must review and apply it with `nono profile promote <name>`.
4. Use read/read_file for view-only access and allow/allow_file only when writes are needed.
"""


def _startup_context() -> str:
    return """[nono sandbox context]

This Hermes session is running inside nono. Filesystem and network access are enforced by the operating system before Hermes starts. Hermes approvals, YOLO mode, chmod, sudo, and macOS privacy settings cannot expand nono capabilities from inside the session.

If a tool fails with "Operation not permitted", "Permission denied", EACCES, EPERM, "landlock", or "sandbox denied", diagnose the live sandbox with:
  nono why --self --path <path> --op read

Then offer either a one-off restart with an explicit nono grant or a persistent profile draft under ~/.config/nono/profile-drafts/. The user must review and apply drafts with `nono profile promote <name>`.
"""


def _nono_status(_params: dict[str, Any] | None = None, **_kwargs: Any) -> str:
    status = {
        "inside_nono": _inside_nono(),
        "capability_file": str(_cap_file()) if _cap_file() else None,
        "capabilities": _load_capabilities(),
        "proxy": _proxy_status(),
        "guidance": "Use nono why --self --path <path> --op <read|write|readwrite> for denied paths inside this sandbox.",
    }
    return json.dumps(status, indent=2)


def _nono_status_command(_raw_args: str = "") -> str:
    return _nono_status()


def _augment_tool_result(*args: Any, **kwargs: Any) -> str | None:
    if not _inside_nono():
        return None

    _tool_name, tool_args, result, _task_id = _tool_fields(args, kwargs)

    result_text = _stringify(result)
    if not DENIAL_RE.search(result_text):
        return None

    blocked_path = _extract_path(tool_args, result)
    return result_text + "\n\n" + _denial_context(blocked_path, _load_capabilities())


def _capture_tool_denial(*args: Any, **kwargs: Any) -> None:
    _tool_name, tool_args, result, _task_id = _tool_fields(args, kwargs)
    result_text = _stringify(result, max_chars=1000)
    denied = bool(DENIAL_RE.search(result_text))
    blocked_path = _extract_path(tool_args, result)
    session_id = _session_key(args, kwargs)
    if denied and _inside_nono():
        _PENDING_DENIAL_CONTEXT[session_id] = _denial_context(
            blocked_path,
            _load_capabilities(),
        )


def _inject_context(*args: Any, **kwargs: Any) -> dict[str, str] | None:
    if not _inside_nono():
        return None

    key = _session_key(args, kwargs)
    context_parts = []
    is_first_turn = bool(kwargs.get("is_first_turn"))
    if is_first_turn and key not in _ANNOUNCED:
        _ANNOUNCED.add(key)
        context_parts.append(_startup_context())

    denial_context = _PENDING_DENIAL_CONTEXT.pop(key, None)
    if denial_context:
        context_parts.append(denial_context)

    if not context_parts:
        return None

    return {"context": "\n\n".join(context_parts)}


def _register_tool(ctx: Any, schema: dict[str, Any]) -> None:
    try:
        ctx.register_tool(
            name="nono_status",
            toolset="nono",
            schema=schema,
            handler=_nono_status,
            description="Show the current nono sandbox capability summary.",
        )
    except TypeError:
        ctx.register_tool("nono_status", schema, _nono_status)


def _register_hook(ctx: Any, name: str, handler: Any) -> None:
    try:
        ctx.register_hook(name, handler)
    except Exception:
        return


def _register_command(ctx: Any) -> None:
    try:
        ctx.register_command(
            "nono-status",
            handler=_nono_status_command,
            description="Show the current nono sandbox status",
        )
    except Exception:
        return


def _register_skills(ctx: Any) -> None:
    skill = Path(__file__).resolve().parent / "skills" / "nono-sandbox" / "SKILL.md"
    if not skill.exists():
        return
    try:
        ctx.register_skill("nono-sandbox", skill)
    except Exception:
        return


def register(ctx: Any) -> None:
    schema = {
        "name": "nono_status",
        "description": "Show the current nono sandbox capability summary when Hermes is running inside nono.",
        "parameters": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    }

    _register_tool(ctx, schema)
    _register_command(ctx)
    _register_skills(ctx)
    _register_hook(ctx, "transform_tool_result", _augment_tool_result)
    _register_hook(ctx, "post_tool_call", _capture_tool_denial)
    _register_hook(ctx, "pre_llm_call", _inject_context)
