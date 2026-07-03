'use strict';
const fs = require('fs');

// Matches the same denial signatures as nono-hook.sh so both paths stay in sync.
const DENIAL_PATTERN =
  /operation not permitted|permission denied|eperm|eacces|sandbox.*denied|landlock/i;

/**
 * Registers a message_sending modifying hook that fires for ALL model types
 * in the native OpenClaw delivery path (Gemini, etc.).
 *
 * When NONO_CAP_FILE is set (i.e. we are inside a nono sandbox) and the
 * outgoing message content contains a sandbox-denial signature, the hook
 * appends the active capability set and remediation instructions so the user
 * always sees them — regardless of which model is running.
 *
 * For Claude / pi-embedded sessions the PostToolUseFailure hook in
 * settings.json fires instead (earlier, before the agent responds).
 */
module.exports = function register(api) {
  api.on('message_sending', async (event) => {
    const capFile = process.env.NONO_CAP_FILE;
    if (!capFile) return;

    const content = event.content;
    let text = '';
    if (typeof content === 'string') {
      text = content;
    } else if (Array.isArray(content)) {
      text = content.map(p => (p && typeof p.text === 'string' ? p.text : '')).join(' ');
    }
    if (!DENIAL_PATTERN.test(text)) return;

    let caps;
    try {
      caps = JSON.parse(fs.readFileSync(capFile, 'utf8'));
    } catch {
      return;
    }

    const pathLines = (caps.fs ?? [])
      .map(e => '  ' + (e.resolved ?? e.path) + ' (' + e.access + ')')
      .join('\n') || '  (none)';
    const net = caps.net_blocked ? 'blocked' : 'allowed';

    const context = [
      '',
      '---',
      '**[nono sandbox]** This is a sandbox permission denial — not a Unix or macOS permissions issue.',
      'Do NOT suggest sudo, chmod, or system permission changes.',
      '',
      'Allowed paths in this session:',
      pathLines,
      'Network: ' + net,
      '',
      'Next steps (in order):',
      '1. Run `nono why --path <blocked-path> --op read` immediately.',
      '   Include its output verbatim in your reply.',
      '2. Present the user with exactly these two options:',
      '   Option A (quick fix):  nono run --allow /path/to/needed -- openclaw',
      '   Option B (persistent): draft a profile to ~/.config/nono/profile-drafts/<name>.json',
      '                          (profiles/ is read-only from the sandbox by design),',
      '                          and if updating an existing user profile, write',
      '                          ~/.config/nono/profile-drafts/<name>.base with the',
      '                          SHA-256 of the original profile bytes.',
      '                          then tell the user: run `nono profile promote <name>`',
      '                          to review and apply, then start with',
      '                          `nono run --profile <name> -- openclaw`',
    ].join('\n');

    if (typeof content === 'string') {
      return { content: content + context };
    }
    // For array content, append context to the last text part
    const parts = content.slice();
    const lastTextIdx = parts.map(p => typeof p.text === 'string').lastIndexOf(true);
    if (lastTextIdx >= 0) {
      parts[lastTextIdx] = { ...parts[lastTextIdx], text: parts[lastTextIdx].text + context };
    } else {
      parts.push({ type: 'text', text: context });
    }
    return { content: parts };
  });
};
