# Working inside a nono sandbox

This document is rendered per nono session. It reflects the command you actually ran, so remediation examples match your real invocation.

## Session context

- **Command you ran:** `{{NONO_COMMAND}}`
- **Profile in use:** `{{NONO_PROFILE}}`
- **Capability manifest:** `{{NONO_CAP_FILE}}`

nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS) before Kimchi starts. Kimchi cannot expand nono access from inside the session — retries, approval prompts, chmod, chown, sudo, or macOS privacy settings do not grant new nono capabilities.

## Diagnosis

When a tool call, shell command, or provider request fails with `Operation not permitted`, `Permission denied`, `EACCES`, `EPERM`, `landlock`, or `sandbox denied`:

1. Start with `nono profile guide` to get a general idea of how to manage nono profiles.
2. Identify the concrete blocked path or network action from the failed tool call, stderr, traceback, or command arguments.
3. Use `nono why` to find out the failure reason:
    ```bash
    nono why --self --path /the/blocked/path --op read
    ```
    Use `--op write` for write-only failures and `--op readwrite` when the operation needs both.
4. Inspect the current sandbox state: `cat "{{NONO_CAP_FILE}}"`
5. Identify the most accurate fix:
   - Try to avoid giving permissions to a specific file if there are high chances that it will need access to a broader path. For example, if you see that there's a permission issue accessing a file in `$HOME/.config/some-tool/themes/dark.json`, chances are tool may need access to `$HOME/.config/some-tool/themes` instead of a specific file.
   - Use `groups.include` to allow broad toolset, such as GO, node, rust, or python. Groups are named, composable collections of security rules. Profiles reference groups by name in their `groups.include` field. List all groups with this command: `nono profile groups`

## Remediation options

Present up to three options to the user. At the end, suggest to the user which option is the most appropriate. 

Do not stick to A, B, C naming. For instance, if option B is not appropriate, but options A and C are, name them A and B, so that there are no gaps in the numbering.

### Option A: patch the existing profile (persistent)

Execute the following steps:
1. Read the current profile. It should be located here: `$HOME/.config/nono/profiles/{{NONO_PROFILE}}.json`
2. Modify the profile but save it in the drafts directory: `$HOME/.config/nono/profile-drafts/{{NONO_PROFILE}}.json`. You don't have permissions to modify profiles directly. User must promote a draft that you create outside of sandbox. If a draft file already exists, override it.
3. Validate the draft: `nono profile validate --draft {{NONO_PROFILE}}`
4. Important: `promote` on existing profile doesn't work out of the box. Create a `.base` file: `shasum -a 256 "$HOME/.config/nono/profiles/{{NONO_PROFILE}}.json" | awk '{print $1}' > "$HOME/.config/nono/profile-drafts/{{NONO_PROFILE}}.base"`. Without this step, `promote` will fail.
   a. make sure to use correct profile name for all files (source and generated): `{{NONO_PROFILE}}`

#### User actions

Explain to the user below:
- The user reviews and promotes the draft outside the sandbox: `nono profile promote {{NONO_PROFILE}}`
- Start future sessions with: `nono run --profile {{NONO_PROFILE}} -- {{NONO_TAIL}}`

### Option B: create a new profile (persistent)

Execute the following steps:
1. Give a name to a new profile. I'll reference this name as <name> from now on. Use a <name> specific to the diagnosed issue. You can use the profile name as a base, for example `{{NONO_PROFILE}}-go` if you're extending existing profile with GO runtime.
2. Check content of `$HOME/.config/nono/profile-drafts/` directory. Make sure the `<name>.json` file is not there. Do not override the existing drafts, use a different name instead.
3. Create a profile draft under `$HOME/.config/nono/profile-drafts/<name>.json` for the user, so that the user only needs to promote the profile. Example:
   ```json
   {
     "extends": "{{NONO_PROFILE}}",
     "meta": { "name": "<name>", "version": "1.0.0" },
     "groups": {
         "include": [
           "go_runtime"
         ]
     }
   }
   ```
4. Validate the draft: `nono profile validate --draft <name>`

#### User actions

Explain to the user below:
- The user reviews and promotes the draft outside the sandbox: `nono profile promote {{NONO_PROFILE}}`
- Start future sessions with: `nono run --profile {{NONO_PROFILE}} -- {{NONO_TAIL}}`

### Option C: one-off restart

Use this for a remediation needed only once:

```bash
nono run --profile {{NONO_PROFILE}} --allow /path/to/needed -- {{NONO_TAIL}}
```

## Do not

- Do not attempt to write to `$HOME/.config/nono/profiles` from inside the sandbox. It will be blocked anyway. Use the drafts directory instead: `$HOME/.config/nono/profile-drafts/`
- Do not suggest Full Disk Access, chmod, chown, or sudo for nono denials.
- Do not retry a blocked tool through a different path.
- Do not tell the user Kimchi approval can fix a nono denial.
